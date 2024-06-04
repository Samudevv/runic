/*
This file is part of runic.

Runic is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2
as published by the Free Software Foundation.

Runic is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with runic.  If not, see <http://www.gnu.org/licenses/>.

*/

package exec

import "base:runtime"
import "core:bytes"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "root:errors"

Env :: enum {
    Parent,
    None,
}

ParentAnd :: struct {
    vars: []string,
}

Environ :: union #no_nil {
    Env,
    []string,
    ParentAnd,
}

@(private)
RWPipe :: struct {
    r: os.Handle,
    w: os.Handle,
}

@(private)
StreamData :: struct {
    hd:     os.Handle,
    stream: io.Stream,
    err:    io.Error,
    wg:     ^sync.Wait_Group,
}

Stream :: union {
    os.Handle,
    io.Stream,
}

@(private)
stream_to_pipe :: proc(
    s: Stream,
    loc := #caller_location,
) -> (
    p: Maybe(RWPipe),
    err: errors.Error,
) {
    if s == nil do return nil, nil

    switch str in s {
    case os.Handle:
        p = RWPipe {
            r = str,
            w = str,
        }
    case io.Stream:
        p = pipe()
        if p == nil do return nil, errors.empty(loc = loc)
    }

    return
}

command :: proc(
    name: string,
    args: []string = {},
    stdout: Stream = nil,
    stderr: Stream = nil,
    stdin: Stream = nil,
    env: Environ = Env.Parent,
) -> (
    status: int,
    err: errors.Error,
) {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    abs_name: string = ---
    if filepath.is_abs(name) {
        abs_name = name
    } else {
        if strings.contains_rune(name, filepath.SEPARATOR) ||
           strings.contains_rune(name, '/') {
            abs_name = filepath.join(
                {os.get_current_directory(), name},
                arena_alloc,
            )
            if !os.is_file(abs_name) do return 1, errors.message("name not found: \"{}\"", abs_name)
        } else {
            if path_name, ok := lookup_path(name, arena_alloc); !ok {
                status = 1
                err = errors.message("name not found: \"{}\"", name)
                return
            } else {
                abs_name = path_name
            }
        }
    }

    pipeout := stream_to_pipe(stdout) or_return
    pipeerr := stream_to_pipe(stderr) or_return
    pipein := stream_to_pipe(stdin) or_return

    child_process := start_child_process(
        abs_name,
        args,
        pipeout,
        pipeerr,
        pipein,
        env,
        arena_alloc,
    ) or_return
    defer cleanup_child_process(child_process)

    stream_threads := make([dynamic]^thread.Thread, 0, 3, arena_alloc)
    stream_datas: [3]StreamData

    write_pipe :: proc(data: rawptr) {
        strd := cast(^StreamData)data
        defer sync.wait_group_done(strd.wg)
        defer os.close(strd.hd)
        _, strd.err = io.copy(strd.stream, os.stream_from_handle(strd.hd))
        if strd.err == .Unknown do strd.err = .None
    }
    read_pipe :: proc(data: rawptr) {
        strd := cast(^StreamData)data
        defer sync.wait_group_done(strd.wg)
        defer os.close(strd.hd)
        _, strd.err = io.copy(os.stream_from_handle(strd.hd), strd.stream)
        if strd.err == .Unknown do strd.err = .None
    }

    wg: sync.Wait_Group

    if po, ok := pipeout.?; ok && po.r != po.w {
        context.allocator = arena_alloc

        stream_datas[0] = StreamData {
            hd     = po.r,
            stream = stdout.(io.Stream),
            wg     = &wg,
        }
        sync.wait_group_add(&wg, 1)
        append(
            &stream_threads,
            thread.create_and_start_with_data(&stream_datas[0], write_pipe),
        )
    }
    if pe, ok := pipeerr.?; ok && pe.r != pe.w {
        context.allocator = arena_alloc

        stream_datas[1] = StreamData {
            hd     = pe.r,
            stream = stderr.(io.Stream),
            wg     = &wg,
        }
        sync.wait_group_add(&wg, 1)
        append(
            &stream_threads,
            thread.create_and_start_with_data(&stream_datas[1], write_pipe),
        )
    }
    if pi, ok := pipein.?; ok && pi.r != pi.w {
        context.allocator = arena_alloc

        stream_datas[2] = StreamData {
            hd     = pi.w,
            stream = stdin.(io.Stream),
            wg     = &wg,
        }
        sync.wait_group_add(&wg, 1)
        append(
            &stream_threads,
            thread.create_and_start_with_data(&stream_datas[2], read_pipe),
        )
    }

    sync.wait_group_wait(&wg)
    for td in stream_threads do thread.join(td)
    wait_for_child_process(child_process)

    errors.wrap(stream_datas[0].err) or_return
    errors.wrap(stream_datas[1].err) or_return
    errors.wrap(stream_datas[2].err) or_return

    status = get_exit_code(child_process) or_return
    return
}

pipe_commands :: proc(
    cmds: [][]string,
    stdout: Stream = nil,
    stderr: Stream = nil,
    stdin: Stream = nil,
    env: Environ = Env.Parent,
) -> (
    status: int,
    err: errors.Error,
) {
    stdin_buffer: bytes.Buffer
    stdin_from_stdout: bytes.Reader
    stdout_to_stdin: bytes.Buffer
    bytes.buffer_init_allocator(
        &stdout_to_stdin,
        0,
        0,
        runtime.default_allocator(),
    )
    bytes.buffer_init_allocator(
        &stdin_buffer,
        0,
        0,
        runtime.default_allocator(),
    )
    defer bytes.buffer_destroy(&stdin_buffer)
    defer bytes.buffer_destroy(&stdout_to_stdin)

    for c, i in cmds {
        c_stdout: Stream
        c_stdin: Stream

        if i == 0 {
            c_stdin = stdin
        } else {
            bytes.buffer_grow(
                &stdin_buffer,
                bytes.buffer_length(&stdout_to_stdin),
            )
            bytes.buffer_reset(&stdin_buffer)
            bytes.buffer_write_to(
                &stdout_to_stdin,
                bytes.buffer_to_stream(&stdin_buffer),
            )
            bytes.reader_init(
                &stdin_from_stdout,
                bytes.buffer_to_bytes(&stdin_buffer),
            )
            c_stdin = bytes.reader_to_stream(&stdin_from_stdout)
        }

        if i == len(cmds) - 1 {
            c_stdout = stdout
        } else {
            bytes.buffer_reset(&stdout_to_stdin)
            c_stdout = bytes.buffer_to_stream(&stdout_to_stdin)
        }

        status = command(
            c[0],
            c[1:],
            stdout = c_stdout,
            stderr = stderr,
            stdin = c_stdin,
            env = env,
        ) or_return

        if status != 0 do return
    }

    return
}

lookup_path :: proc(
    name: string,
    allocator := context.allocator,
) -> (
    string,
    bool,
) #optional_ok {
    paths, p_ok := executable_paths(allocator)
    if !p_ok do return "", false
    defer delete(paths, allocator)
    defer delete(paths[0], allocator)

    extensions, ok := executable_extensions(allocator)
    if !ok do return "", false
    defer delete(extensions, allocator)
    defer delete(extensions[0], allocator)

    for p in paths {
        for ext in extensions {
            joined_path := filepath.join({p, name}, allocator)
            full_path := strings.concatenate({joined_path, ext}, allocator)
            delete(joined_path, allocator)

            if st, os_err := os.stat(full_path, allocator);
               os_err != 0 || st.is_dir {
                delete(full_path, allocator)
            } else {
                // MAYBEDO: check if file is executable by the current user
                os.file_info_delete(st, allocator)
                return full_path, true
            }
        }
    }

    return "", false
}

@(private)
paths_of_PATH :: #force_inline proc(
    allocator := context.allocator,
) -> (
    []string,
    bool,
) #optional_ok {
    path_var := os.get_env("PATH", allocator)
    if len(path_var) == 0 do return {}, false

    paths, a_err := strings.split(
        path_var,
        rune_to_string(filepath.LIST_SEPARATOR, allocator),
        allocator,
    )
    if a_err != .None do return {}, false

    return paths, true
}

@(private = "file")
rune_to_string :: #force_inline proc(
    r: rune,
    allocator := context.allocator,
) -> string {
    out: strings.Builder
    strings.builder_init(&out, allocator)
    strings.write_rune(&out, r)
    return strings.to_string(out)
}

@(private = "file")
executable_extensions :: proc(
    allocator := context.allocator,
) -> (
    []string,
    bool,
) #optional_ok {
    pathext_var := os.get_env("PATHEXT", allocator)
    if len(pathext_var) == 0 {
        path_extensions := make([dynamic]string, allocator)
        append(&path_extensions, "")
        return path_extensions[:], true
    }

    path_exts, a_err := strings.split(
        pathext_var,
        rune_to_string(filepath.LIST_SEPARATOR, allocator),
        allocator,
    )
    if a_err != .None {
        return {}, false
    }
    defer delete(path_exts, allocator)

    path_extensions := make([dynamic]string, allocator)
    append(&path_extensions, ..path_exts)
    append(&path_extensions, "")

    return path_extensions[:], true
}

