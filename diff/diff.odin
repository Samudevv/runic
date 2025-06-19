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

package diff

import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:testing"

expect_diff_files :: proc(
    t: ^testing.T,
    old_path, new_path: string,
    loc := #caller_location,
) -> bool {
    command: [dynamic]string
    defer delete(command)

    if program_installed("difft") {
        c := [?]string {
            "difft",
            "--display",
            "side-by-side-show-both",
            "--exit-code",
            "--color=always",
            old_path,
            new_path,
        }
        append(&command, ..c[:])
    } else if program_installed("diff") {
        c := [?]string {
            "diff",
            "-y",
            "--suppress-common-lines",
            old_path,
            new_path,
        }
        append(&command, ..c[:])
    } else {
        old, old_err := os.read_entire_file(old_path, context.allocator)
        if !testing.expect_value(t, old_err, nil) do return false
        defer delete(old)

        new, new_err := os.read_entire_file(new_path, context.allocator)
        if !testing.expect_value(t, new_err, nil) do return false
        defer delete(new)

        if !testing.expect_value(t, len(new), len(old)) ||
           !testing.expect_value(t, string(new), string(old)) {
            return false
        }

        return true
    }

    env, _ := os.environ(context.allocator)
    defer delete(env)
    defer for e in env do delete(e)

    diff_process := os.Process_Desc {
        command = command[:],
        env     = env,
    }

    state, stdout, stderr, exec_err := os.process_exec(
        diff_process,
        context.allocator,
    )
    if !testing.expect_value(t, exec_err, nil) do return false
    defer delete(stdout)
    defer delete(stderr)

    if !testing.expect(t, state.exited) {
        return false
    }

    if !state.success {
        if len(stderr) != 0 do log.errorf("{}\n{}\n\n", loc, string(stderr))
        if len(stdout) != 0 do log.errorf("{}\n{}\n\n", loc, string(stdout))
        return false
    }

    return true
}

expect_diff_strings :: proc(
    t: ^testing.T,
    old_string, new_string: string,
    file_ext: string = ".txt",
    loc := #caller_location,
) -> bool {
    tmp, tmp_err := os.temp_directory(context.allocator)
    if !testing.expect_value(t, tmp_err, nil) do return false

    old_file, new_file: ^os.File
    old_file_name, new_file_name: string
    for i := 0;; i += 1 {
        old_file_base := fmt.aprintf("test_old_diff_%3v%v", i, file_ext)
        new_file_base := fmt.aprintf("test_new_diff_%3v%v", i, file_ext)
        defer delete(old_file_base)
        defer delete(new_file_base)

        join_err: os.Error = ---
        old_file_name, join_err = os.join_path(
            {tmp, old_file_base},
            context.allocator,
        )
        if join_err != nil do continue

        new_file_name, join_err = os.join_path(
            {tmp, new_file_base},
            context.allocator,
        )
        if join_err != nil {
            delete(old_file_name)
            continue
        }

        file_err: os.Error = ---
        old_file, file_err = os.open(
            old_file_name,
            {.Write, .Create, .Trunc, .Excl},
            0o644,
        )
        if file_err != nil {
            delete(old_file_name)
            delete(new_file_name)
            continue
        }

        new_file, file_err = os.open(
            new_file_name,
            {.Write, .Create, .Trunc, .Excl},
            0o644,
        )
        if file_err != nil {
            delete(old_file_name)
            delete(new_file_name)
            continue
        }

        break
    }

    delete(tmp)

    defer delete(old_file_name)
    defer delete(new_file_name)

    _, write_err := os.write_string(old_file, old_string)
    if !testing.expect_value(t, write_err, nil) {
        os.close(old_file)
        os.close(new_file)
        return false
    }

    _, write_err = os.write_string(new_file, new_string)
    if !testing.expect_value(t, write_err, nil) {
        os.close(old_file)
        os.close(new_file)
        return false
    }

    os.close(old_file)
    os.close(new_file)

    defer os.remove(old_file_name)
    defer os.remove(new_file_name)

    return expect_diff_files(t, old_file_name, new_file_name, loc)
}

@(private)
program_installed :: proc(prog_name: string) -> bool {
    when ODIN_OS == .Windows {
        prog_name := prog_name
        prog_name = fmt.aprintf("{}.exe", prog_name)
        defer delete(prog_name)
    }

    PATH, found := os.lookup_env("PATH", context.allocator)
    if !found do return false
    defer delete(PATH)

    PATHs, err := os.split_path_list(PATH, context.allocator)
    if err != nil do return false
    defer delete(PATHs)
    defer for p in PATHs do delete(p)

    for p in PATHs {
        prog_path, join_err := os.join_path({p, prog_name}, context.allocator)
        if join_err != nil do continue
        defer delete(prog_path)

        if os.is_file(prog_path) {
            return true
        }
    }

    return false
}
