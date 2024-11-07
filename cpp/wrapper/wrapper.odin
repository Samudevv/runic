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

package cpp_wrapper

import "base:runtime"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "root:errors"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
ClientData :: struct {
    header: io.Writer,
    source: io.Writer,
}

generate_wrapper :: proc(rn: runic.Wrapper) -> (err: union {
        errors.Error,
        io.Error,
    }) {
    arena: runtime.Arena
    errors.wrap(runtime.arena_init(&arena, 0, context.allocator)) or_return
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    clang_flags := [?]cstring {
        // Android
        "-U__ANDROID__",
        // BSD
        "-U__FreeBSD__",
        "-U__FreeBSD_kernel__",
        "-U__NetBSD__",
        "-U__OpenBSD__",
        "-U__bsdi__",
        "-U__DragonFly__",
        "-U_SYSTYPE_BSD",
        "-UBSD",
        // Linux
        "-U__GLIBC__",
        "-U__gnu_linux__",
        "-U__linux__",
        "-Ulinux",
        "-U__linux",
        // MacOS
        "-Umacintosh",
        "-UMacintosh",
        "-U__APPLE__",
        "-U__MACH__",
        // Windows
        "-U_WIN16",
        "-U_WIN32",
        "-U_WIN64",
        // AMD64 & x86_64
        "-U__amd64__",
        "-U__amd64",
        "-U__x86_64__",
        "-U__x86_64",
        // ARM
        "-U__arm__",
        "-U__thumb__",
        "-U__aarch64__",
        // x86
        "-Ui386",
        "-U__i386",
        "-U__i386__",
        "-U__i486__",
        "-U__i586__",
        "-U__i686__",

        // Linux
        "-D__GLIBC__",
        "-D__gnu_linux__",
        "-D__linux__",
        "-Dlinux",
        "-D__linux",
        // x86_64
        "-D__amd64__",
        "-D__amd64",
        "-D__x86_64__",
        "-D__x86_64",
        // Target
        "--target=x86_64-linux-gnu",
    }

    out_header, out_header_err := os.open(
        rn.out_header,
        os.O_CREATE | os.O_TRUNC | os.O_WRONLY,
        0o644,
    )
    errors.wrap(out_header_err, "failed to create out header") or_return
    defer os.close(out_header)
    out_source, out_source_err := os.open(
        rn.out_source,
        os.O_CREATE | os.O_TRUNC | os.O_WRONLY,
        0o644,
    )
    errors.wrap(out_source_err, "failed to create out source") or_return
    defer os.close(out_source)

    data := ClientData {
        header = os.stream_from_handle(out_header),
        source = os.stream_from_handle(out_source),
    }

    index := clang.createIndex(0, 0)
    defer clang.disposeIndex(index)
    units := make(
        [dynamic]clang.TranslationUnit,
        allocator = arena_alloc,
        len = len(rn.in_headers),
        cap = len(rn.in_headers),
    )
    defer for unit in units {
        clang.disposeTranslationUnit(unit)
    }

    io.write_string(data.header, "#pragma once\n\n") or_return
    for in_header in rn.in_headers {
        rel_in_header, rel_err := filepath.rel(
            filepath.dir(rn.out_header, arena_alloc),
            in_header,
            arena_alloc,
        )
        if rel_err != .None do rel_in_header = in_header

        io.write_string(data.header, "#include \"") or_return
        io.write_string(data.header, rel_in_header) or_return
        io.write_string(data.header, "\"\n") or_return
    }

    rel_out_header, rel_err := filepath.rel(
        filepath.dir(rn.out_source, arena_alloc),
        rn.out_header,
        arena_alloc,
    )
    if rel_err != .None do rel_out_header = rn.out_header

    io.write_rune(data.header, '\n') or_return
    io.write_string(data.source, "#include \"") or_return
    io.write_string(data.source, rel_out_header) or_return
    io.write_string(data.source, "\"\n\n") or_return

    for in_header in rn.in_headers {
        _, os_stat := os.stat(in_header, arena_alloc)
        #partial switch stat in os_stat {
        case os.General_Error:
            if stat == .Not_Exist {
                err = errors.Error(
                    errors.message(
                        "failed to find header file: \"{}\"",
                        in_header,
                    ),
                )
                return
            }
            err = errors.Error(
                errors.message("failed to open header file: {}", stat),
            )
            return
        case nil:
        case:
            err = errors.Error(
                errors.message("failed to open header file: {}", stat),
            )
            return
        }

        in_header_cstr := strings.clone_to_cstring(in_header, arena_alloc)

        unit := clang.parseTranslationUnit(
            index,
            in_header_cstr,
            raw_data(clang_flags[:]),
            i32(len(clang_flags)),
            nil,
            0,
            .SkipFunctionBodies,
        )

        if unit == nil {
            err = errors.Error(
                errors.message(
                    "\"{}\" failed to parse translation unit",
                    in_header,
                ),
            )
            return
        }

        append(&units, unit)

        cursor := clang.getTranslationUnitCursor(unit)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.Cursor,
                client_data: clang.ClientData,
            ) -> clang.ChildVisitResult {
                data := cast(^ClientData)client_data
                context = runtime.default_context()

                cursor_kind := clang.getCursorKind(cursor)
                // cursor_type := clang.getCursorType(cursor)
                cursor_location := clang.getCursorLocation(cursor)
                display_name_clang := clang.getCursorDisplayName(cursor)
                // display_name := clang_str(display_name_clang)
                storage_class := clang.Cursor_getStorageClass(cursor)

                defer clang.disposeString(display_name_clang)

                if !clang.Location_isFromMainFile(cursor_location) do return .Continue

                #partial cursor_kind_switch: switch cursor_kind {
                case .FunctionDecl:
                    if !(storage_class == .Static || clang.Cursor_isFunctionInlined(cursor)) do return .Continue

                    cursor_return_type := clang.getCursorResultType(cursor)
                    return_type_spelling_clang := clang.getTypeSpelling(
                        cursor_return_type,
                    )
                    return_type_spelling := clang_str(
                        return_type_spelling_clang,
                    )
                    num_params := clang.Cursor_getNumArguments(cursor)
                    func_name_clang := clang.getCursorSpelling(cursor)
                    func_name := clang_str(func_name_clang)

                    defer clang.disposeString(func_name_clang)
                    defer clang.disposeString(return_type_spelling_clang)

                    // TODO: handle io errors
                    io.write_string(data.header, "extern ")
                    io.write_string(data.header, return_type_spelling)
                    io.write_rune(data.header, ' ')
                    io.write_string(data.header, func_name)
                    io.write_string(data.header, "_wrapper")
                    io.write_rune(data.header, '(')

                    io.write_string(data.source, return_type_spelling)
                    io.write_rune(data.source, ' ')
                    io.write_string(data.source, func_name)
                    io.write_string(data.source, "_wrapper")
                    io.write_rune(data.source, '(')


                    for idx in 0 ..< num_params {
                        param_cursor := clang.Cursor_getArgument(
                            cursor,
                            u32(idx),
                        )
                        param_type := clang.getCursorType(param_cursor)
                        param_type_spelling_clang := clang.getTypeSpelling(
                            param_type,
                        )
                        param_type_spelling := clang_str(
                            param_type_spelling_clang,
                        )
                        param_name_clang := clang.getCursorSpelling(
                            param_cursor,
                        )
                        param_name := clang_str(param_name_clang)
                        defer clang.disposeString(param_type_spelling_clang)
                        defer clang.disposeString(param_name_clang)

                        io.write_string(data.header, param_type_spelling)
                        io.write_rune(data.header, ' ')
                        io.write_string(data.header, param_name)
                        if idx != num_params - 1 do io.write_string(data.header, ", ")

                        io.write_string(data.source, param_type_spelling)
                        io.write_rune(data.source, ' ')
                        io.write_string(data.source, param_name)
                        if idx != num_params - 1 do io.write_string(data.source, ", ")
                    }

                    io.write_string(data.header, ");\n")

                    io.write_string(data.source, ") {\n    ")
                    if return_type_spelling != "void" {
                        io.write_string(data.source, "return ")
                    }
                    io.write_string(data.source, func_name)
                    io.write_rune(data.source, '(')

                    for idx in 0 ..< num_params {
                        param_cursor := clang.Cursor_getArgument(
                            cursor,
                            u32(idx),
                        )
                        param_name_clang := clang.getCursorSpelling(
                            param_cursor,
                        )
                        param_name := clang_str(param_name_clang)
                        defer clang.disposeString(param_name_clang)

                        io.write_string(data.source, param_name)
                        if idx != num_params - 1 do io.write_string(data.source, ", ")
                    }

                    io.write_string(data.source, ");\n}\n\n")
                }

                return .Continue
            },
            &data,
        )
    }

    return
}

@(private)
clang_str :: #force_inline proc(clang_str: clang.String) -> string {
    cstr := clang.getCString(clang_str)
    return strings.string_from_ptr(cast(^byte)cstr, len(cstr))
}

