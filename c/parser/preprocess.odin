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

package parser

import "base:runtime"
import "core:bufio"
import "core:bytes"
import "core:fmt"
import "core:io"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import ctz "root:c/tokenizer"
import "root:errors"
import "root:exec"
import "root:runic"

PREPREPROCESS_PREFIX :: "__PPP__"
MACRO_VAR :: PREPREPROCESS_PREFIX + "macro_var"
MACRO_FUNC :: PREPREPROCESS_PREFIX + "macro_func"
INCLUDE_SYS :: PREPREPROCESS_PREFIX + "include_sys"
INCLUDE_REL :: PREPREPROCESS_PREFIX + "include_rel"
INCLUDE_END :: PREPREPROCESS_PREFIX + "include_end"


PREPROCESS_PROGRAM :: "zig"
PREPROCESS_FLAGS :: []string{"cc", "-E", "-w", "--std=c99", "-xc", "-"}

preprocess_file :: proc(
    plat: runic.Platform,
    input: io.Reader,
    out: io.Writer,
    pp_program := PREPROCESS_PROGRAM,
    pp_defines := [][2]string{},
    pp_includes := []string{},
    pp_flags := PREPROCESS_FLAGS,
) -> (
    err: errors.Error,
) {
    arena: runtime.Arena
    arena_alloc := runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)

    pp_call := make([dynamic]string, arena_alloc)
    append(&pp_call, ..pp_flags)

    for d in pp_defines {
        append(
            &pp_call,
            strings.concatenate({"-D", d[0], "=", d[1]}, arena_alloc),
        )
    }

    for i in pp_includes {
        append(&pp_call, strings.concatenate({"-I", i}, arena_alloc))
    }

    append(&pp_call, "-target")

    os_str, arch_str: string

    switch plat.os {
    case .Any:
        panic("invalid os Any")
    case .Linux:
        os_str = "linux"
    case .Windows:
        os_str = "windows"
    case .Macos:
        os_str = "macos"
    case .BSD:
        os_str = "freebsd"
    }
    switch plat.arch {
    case .Any:
        panic("invalid arch Any")
    case .x86_64:
        arch_str = "x86_64"
    case .arm64:
        arch_str = "aarch64"
    case .x86:
        arch_str = "x86"
    case .arm32:
        arch_str = "arm"
    }

    append(&pp_call, strings.concatenate({arch_str, "-", os_str}, arena_alloc))

    pp_build: strings.Builder
    strings.builder_init(&pp_build, arena_alloc)

    when ODIN_DEBUG {
        fmt.eprintfln(
            "PP Call \"{} {}\"",
            pp_program,
            strings.join(pp_call[:], " ", arena_alloc),
        )
    }

    status := exec.command(
        pp_program,
        pp_call[:],
        stdout = strings.to_stream(&pp_build),
        stdin = input,
        env = exec.Env.Parent,
    ) or_return

    if status != 0 do return errors.message("exit status {}", status)

    // Remove leading '#'
    pp_reader: strings.Reader
    pp_stream := strings.to_reader(&pp_reader, strings.to_string(pp_build))
    line_reader: bufio.Reader
    bufio.reader_init(&line_reader, pp_stream)
    defer bufio.reader_destroy(&line_reader)

    line: []u8 = ---
    bufio_err: io.Error = ---
    line_loop: for line, bufio_err = bufio.reader_read_slice(
            &line_reader,
            '\n',
        );
        bufio_err == .None;
        line, bufio_err = bufio.reader_read_slice(&line_reader, '\n') {

        if strings.has_prefix(string(line), "#") do continue
        if _, io_err := io.write_ptr(out, raw_data(line), len(line));
           io_err != .None {
            err = errors.wrap(io_err)
            return
        }
    }

    if bufio_err != .EOF && bufio_err != .None do err = errors.wrap(bufio_err)
    return
}

prepreprocess_file :: proc(
    path: string,
    out: io.Writer,
    input: Maybe(io.Reader) = nil,
) -> (
    err: union {
        errors.Error,
        io.Error,
    },
) {
    arena: runtime.Arena
    arena_alloc := runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)

    abs_dirname: string = ---
    dirname := filepath.dir(path, arena_alloc)
    if !filepath.is_abs(dirname) {
        ok: bool = ---
        abs_dirname, ok = filepath.abs(dirname, arena_alloc)
        errors.wrap(ok) or_return
    } else {
        abs_dirname = dirname
    }

    in_stream: io.Reader
    in_hd: os.Handle
    defer os.close(in_hd)

    if input != nil {
        in_stream = input.?
    } else {
        os_err: os.Error = ---
        in_hd, os_err = os.open(path)
        if os_err != nil {
            err = errors.Error(
                errors.message("\"{}\": {}", path, errors.wrap(os_err)),
            )
            return
        }
        in_stream = os.stream_from_handle(in_hd)
    }

    input: bufio.Reader

    bufio.reader_init(&input, in_stream)
    defer bufio.reader_destroy(&input)

    line_count: int = 1
    line: []u8
    bufio_err: io.Error
    line_loop: for line, bufio_err = bufio.reader_read_slice(&input, '\n');
        bufio_err == .None;
        line, bufio_err = bufio.reader_read_slice(&input, '\n') {
        defer line_count += 1

        if !strings.has_prefix(strings.trim_left_space(string(line)), "#") {
            io.write_ptr(out, raw_data(line), len(line)) or_return
            continue
        }

        line = line[:len(line) - 1]
        if line[len(line) - 1] == '\r' {
            line = line[:len(line) - 1]
        }

        if len(line) >= 1 && line[len(line) - 1] == '\\' {
            line_buf: bytes.Buffer
            bytes.buffer_init_allocator(&line_buf, 0, 0, arena_alloc)
            bytes.buffer_write_ptr(&line_buf, &line[0], len(line) - 1)

            for {
                next_line, slash_err := bufio.reader_read_slice(&input, '\n')
                if bufio_err = slash_err; bufio_err != .None do break line_loop

                next_line = next_line[:len(next_line) - 1]
                if next_line[len(next_line) - 1] == '\r' {
                    next_line = next_line[:len(next_line) - 1]
                }

                if len(next_line) >= 1 &&
                   next_line[len(next_line) - 1] == '\\' {
                    bytes.buffer_write_ptr(
                        &line_buf,
                        &next_line[0],
                        len(next_line) - 1,
                    )
                } else {
                    bytes.buffer_write_ptr(
                        &line_buf,
                        &next_line[0],
                        len(next_line),
                    )
                    break
                }
            }

            line = bytes.buffer_to_bytes(&line_buf)
        }

        token: ^ctz.Token = ---

        {
            context.allocator = arena_alloc

            tz: ctz.Tokenizer
            tz_file := ctz.add_new_file(&tz, path, line, 1)
            token = ctz.tokenize(&tz, tz_file)
        }

        errors.assert(token != nil) or_return

        macro_name: string
        macro_value: string
        macro_params := make([dynamic]string, arena_alloc)

        #partial kind_switch: switch token.kind {
        case .Punct:
            switch token.lit {
            case "#":
                token = token.next
                switch token.lit {
                case "define":
                    token = token.next
                    if token.kind != .Ident {
                        token.pos.line = line_count
                        err = errors_ident(token)
                        return
                    }

                    macro_name = token.lit

                    if !token.next.has_space && token.next.lit == "(" {
                        param_loop: for token = token.next.next;
                            token != nil &&
                            token.kind != .EOF &&
                            token.lit != ")";
                            token = token.next {
                            if token.kind != .Ident {
                                token.pos.line = line_count
                                err = errors_ident(token)
                                return
                            }

                            append(&macro_params, token.lit)

                            token = token.next
                            switch token.lit {
                            case ",":
                                continue
                            case ")":
                                break param_loop
                            case:
                                token.pos.line = line_count
                                err = errors_expect(token, ", or )")
                                return
                            }
                        }
                    }


                    sb: strings.Builder
                    strings.builder_init_none(&sb, arena_alloc)
                    last_offset := token.pos.offset + len(token.lit)

                    for token = token.next;
                        token != nil && token.kind != .EOF;
                        token = token.next {
                        defer last_offset = token.pos.offset + len(token.lit)

                        if token.has_space {
                            for _ in 0 ..< (token.pos.offset - last_offset) {
                                strings.write_rune(&sb, ' ')
                            }
                        }

                        strings.write_string(&sb, token.lit)
                    }
                    macro_value = strings.to_string(sb)
                case "include":
                    token = token.next

                    inc: Include

                    if token.kind == .String {
                        inc.type = .Relative
                        inc.path = strings.trim_suffix(
                            strings.trim_prefix(token.lit, `"`),
                            `"`,
                        )
                    } else if token.kind != .Punct {
                        err = errors_expect(token, "\" or <")
                        return
                    } else if token.lit == "<" {
                        inc.type = .System

                        path: strings.Builder
                        strings.builder_init_none(&path, arena_alloc)

                        for token = token.next;
                            token != nil &&
                            token.kind != .EOF &&
                            (token.kind != .Punct || token.lit != ">");
                            token = token.next {
                            strings.write_string(&path, token.lit)
                        }

                        inc.path = strings.to_string(path)
                    } else {
                        err = errors_expect(token, "\" or <")
                        return
                    }

                    if inc.type == .Relative {
                        abs_path: string = ---
                        if filepath.is_abs(inc.path) {
                            abs_path = inc.path
                        } else {
                            abs_path = filepath.join(
                                {abs_dirname, inc.path},
                                arena_alloc,
                            )
                        }

                        if !os.exists(abs_path) {
                            inc.type = .System
                        }
                    }

                    switch inc.type {
                    case .Relative:
                        io.write_string(out, INCLUDE_REL) or_return
                    case .System:
                        io.write_string(out, INCLUDE_SYS) or_return
                    }

                    io.write_string(out, ` "`) or_return
                    io.write_string(out, inc.path) or_return
                    io.write_string(out, "\"\n") or_return

                    if inc.type == .Relative && !filepath.is_abs(inc.path) {
                        abs_path := filepath.join(
                            {abs_dirname, inc.path},
                            arena_alloc,
                        )

                        io.write_string(out, "#include \"") or_return
                        io.write_string(out, abs_path) or_return
                        io.write_string(out, "\"\n") or_return
                    } else {
                        io.write_ptr(out, raw_data(line), len(line)) or_return
                        io.write_rune(out, '\n') or_return
                    }

                    io.write_string(out, INCLUDE_END) or_return
                    io.write_rune(out, '\n') or_return

                    continue line_loop
                }
            }
        }

        if len(macro_name) != 0 {
            // First output the original line
            io.write_ptr(out, raw_data(line), len(line)) or_return
            io.write_rune(out, '\n') or_return

            if len(macro_params) != 0 {
                fmt.wprintf(
                    out,
                    "{}macro_func {}{}",
                    PREPREPROCESS_PREFIX,
                    PREPREPROCESS_PREFIX,
                    macro_name,
                )
                fmt.wprint(
                    out,
                    "(",
                    strings.join(macro_params[:], ",", arena_alloc),
                    ")",
                )
            } else {
                fmt.wprintf(
                    out,
                    "{}macro_var {}{}",
                    PREPREPROCESS_PREFIX,
                    PREPREPROCESS_PREFIX,
                    macro_name,
                )
            }
            if len(macro_value) != 0 {
                fmt.wprintf(out, " = (( {} ))", macro_value)
            }
            io.write_string(out, ";\n") or_return
        } else {
            io.write_ptr(out, raw_data(line), len(line)) or_return
            io.write_rune(out, '\n') or_return
        }
    }

    return
}

reserve_random_file :: proc(format: string) -> string {
    for {
        rd_str := fmt.aprintf("%06v", rand.uint64() % 1000000)
        defer delete(rd_str)

        rd_file_name := fmt.aprintf(format, rd_str)
        f, err := os.open(rd_file_name, os.O_CREATE | os.O_EXCL, 0b110110110)
        if err != 0 {
            delete(rd_file_name)
        } else {
            os.close(f)
            return rd_file_name
        }
    }
}

