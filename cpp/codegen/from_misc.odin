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

package cpp_codegen

import "core:fmt"
import "core:os"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private)
struct_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "struct (unnamed") ||
        strings.has_prefix(display_name, "struct (anonymous") \
    )
}

@(private)
struct_is_unnamed_clang :: #force_inline proc(
    display_name: clang.String,
) -> bool {
    return struct_is_unnamed_string(clang_str(display_name))
}

@(private)
struct_is_unnamed :: proc {
    struct_is_unnamed_clang,
    struct_is_unnamed_string,
}

@(private)
enum_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "enum (unnamed") ||
        strings.has_prefix(display_name, "enum (anonymous") \
    )
}

@(private)
enum_is_unnamed_clang :: #force_inline proc(
    display_name: clang.String,
) -> bool {
    return enum_is_unnamed_string(clang_str(display_name))
}

@(private)
enum_is_unnamed :: proc {
    enum_is_unnamed_clang,
    enum_is_unnamed_string,
}

@(private)
union_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "union (unnamed") ||
        strings.has_prefix(display_name, "union (anonymous") \
    )
}

@(private)
union_is_unnamed_clang :: #force_inline proc(
    display_name: clang.String,
) -> bool {
    return union_is_unnamed_string(clang_str(display_name))
}

@(private)
union_is_unnamed :: proc {
    union_is_unnamed_clang,
    union_is_unnamed_string,
}

@(private)
clang_source_error :: proc(
    cursor: clang.Cursor,
    msg: string,
    args: ..any,
    loc := #caller_location,
) -> errors.Error {
    cursor_loc := clang.getCursorLocation(cursor)

    line, column, offset: u32 = ---, ---, ---
    file: clang.File = ---

    clang.getExpansionLocation(cursor_loc, &file, &line, &column, &offset)

    file_name := clang.getFileName(file)
    defer clang.disposeString(file_name)

    return errors.message(
        "{}:{}:{}: {}",
        clang.getCString(file_name),
        line,
        column,
        fmt.aprintf(msg, ..args, allocator = errors.error_allocator),
        loc = loc,
    )
}

@(private)
temp_file :: proc(
) -> (
    file: os.Handle,
    file_path: string,
    err: errors.Error,
) {
    file_name: strings.Builder

    when ODIN_OS == .Windows {
        os.make_directory("C:\\temp")
        strings.write_string(&file_name, "C:\\temp\\runic_macros")
    } else {
        strings.write_string(&file_name, "/tmp/runic_macros")
    }

    MAX_TRIES :: 100

    for _ in 0 ..< MAX_TRIES {
        strings.write_rune(&file_name, '_')

        os_err: os.Error = ---
        file, os_err = os.open(
            strings.to_string(file_name),
            os.O_WRONLY | os.O_CREATE | os.O_EXCL,
            0o777,
        )
        if os_err == nil {
            file_path = strings.to_string(file_name)
            return
        }
    }

    err = errors.message("MAX_TRIES reached")
    return
}

@(private)
clang_get_cursor_extent :: proc(cursor: clang.Cursor) -> string {
    range := clang.getCursorExtent(cursor)

    start := clang.getRangeStart(range)
    end := clang.getRangeEnd(range)

    start_offset, end_offset: u32 = ---, ---
    file: clang.File = ---
    clang.getExpansionLocation(start, &file, nil, nil, &start_offset)
    clang.getExpansionLocation(end, nil, nil, nil, &end_offset)

    if file == nil do return ""

    unit := clang.Cursor_getTranslationUnit(cursor)
    buffer_size: u64 = ---
    buf := cast([^]byte)clang.getFileContents(unit, file, &buffer_size)

    if buffer_size == 0 do return ""

    spel := strings.string_from_ptr(buf, int(buffer_size))
    spel = spel[start_offset:end_offset]

    return spel
}

@(private)
clang_typedef_get_type_hint :: proc(cursor: clang.Cursor) -> Maybe(string) {
    extent := clang_get_cursor_extent(cursor)
    split := strings.split_multi(extent, {" ", "\n", "\r", "\t"})
    defer delete(split)

    if len(split) != 3 do return nil

    type_hint := strings.trim_right(split[1], "*")
    if strings.contains(type_hint, "*") do return nil

    return type_hint
}

@(private)
clang_var_decl_get_type_hint :: proc(cursor: clang.Cursor) -> Maybe(string) {
    extent := clang_get_cursor_extent(cursor)
    split := strings.split_multi(extent, {" ", "\n", "\r", "\t"})
    defer delete(split)

    if len(split) != 2 do return nil

    type_hint := strings.trim_right(split[0], "*")
    if strings.contains(type_hint, "*") do return nil

    return type_hint
}

@(private)
clang_func_return_type_get_type_hint :: proc(
    cursor: clang.Cursor,
) -> Maybe(string) {
    extent := clang_get_cursor_extent(cursor)
    rt_func := strings.split_n(extent, "(", 2)
    defer delete(rt_func)

    if len(rt_func) != 2 do return nil

    split := strings.split_multi(rt_func[0], {" ", "\n", "\r", "\t"})
    defer delete(split)

    if len(split) != 2 do return nil

    type_hint := strings.trim_right(split[0], "*")
    if strings.contains(type_hint, "*") do return nil

    return type_hint
}

clang_str :: #force_inline proc(clang_str: clang.String) -> string {
    cstr := clang.getCString(clang_str)
    return strings.string_from_ptr(cast(^byte)cstr, len(cstr))
}

generate_clang_flags :: proc(
    plat: runic.Platform,
    disable_stdint_macros: bool,
    defines: map[string]string,
    include_dirs: []string,
    enable_host_includes: bool,
    stdinc_gen_dir: Maybe(string),
    flags: []cstring,
    allocator := context.allocator,
) -> (
    clang_flags: [dynamic]cstring,
) {
    clang_flags = make([dynamic]cstring, context.allocator)

    // Macros for all operating systems: https://sourceforge.net/p/predef/wiki/OperatingSystems/
    // Macros for all architectures: https://sourceforge.net/p/predef/wiki/Architectures/
    // Undefine all platform related macros
    UNDEFINES :: [?]cstring {
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
    }
    for u in UNDEFINES {
        append(&clang_flags, u)
    }

    // Define platform related macros
    platform_defines: []cstring
    switch plat.os {
    case .Linux:
        platform_defines = []cstring {
            "-D__GLIBC__",
            "-D__gnu_linux__",
            "-D__linux__",
            "-Dlinux",
            "-D__linux",
        }
    case .Macos:
        platform_defines = []cstring {
            "-Dmacintosh",
            "-DMacintosh",
            "-D__APPLE__",
            "-D__MACH__",
        }
    case .Windows:
        platform_defines = []cstring{"-D_WIN16", "-D_WIN32", "-D_WIN64"}
    case .BSD:
        platform_defines = []cstring {
            "-D__FreeBSD__",
            "-D__FreeBSD_kernel__",
            "-D__bsdi__",
            "-D_SYSTYPE_BSD",
            "-DBSD",
        }
    case .Any:
    // Everything stays undefined
    }

    append(&clang_flags, ..platform_defines)


    switch plat.arch {
    case .x86:
        platform_defines = []cstring {
            "-Di386",
            "-D__i386",
            "-D__i386__",
            "-D__i486__",
            "-D__i586__",
            "-D__i686__",
        }
    case .x86_64:
        platform_defines = []cstring {
            "-D__amd64__",
            "-D__amd64",
            "-D__x86_64__",
            "-D__x86_64",
        }
    case .arm32:
        platform_defines = []cstring{"-D__arm__"}
    case .arm64:
        platform_defines = []cstring{"-D__arm__", "-D__aarch64__"}
    case .Any:
    // Everything stays undefined
    }

    append(&clang_flags, ..platform_defines)

    if !disable_stdint_macros {
        // Macros for stdint (+ stdbool) types
        stdint_macros := [?]cstring {
            "-Dint8_t=signed char",
            "-Dint16_t=signed short",
            "-Dint32_t=signed int",
            "-Dint64_t=signed long long",
            "-Duint8_t=unsigned char",
            "-Duint16_t=unsigned short",
            "-Duint32_t=unsigned int",
            "-Duint64_t=unsigned long long",
            "-Dbool=_Bool",
        }

        append(&clang_flags, ..stdint_macros[:])
    }

    target_flag: cstring = ---
    switch plat.os {
    case .Linux:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-linux-gnu"
        case .arm64:
            target_flag = "--target=aarch64-linux-gnu"
        case .x86:
            target_flag = "--target=i686-linux-gnu"
        case .arm32:
            target_flag = "--target=arm-linux-gnu"
        case .Any:
            target_flag = "--target=unknown-linux-gnu"
        }
    case .Windows:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-windows-msvc"
        case .arm64:
            target_flag = "--target=aarch64-windows-msvc"
        case .x86:
            target_flag = "--target=i686-windows-msvc"
        case .arm32:
            target_flag = "--target=arm-windows-msvc"
        case .Any:
            target_flag = "--target=unknown-windows-msvc"
        }
    case .Macos:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-apple-darwin"
        case .arm64:
            target_flag = "--target=aarch64-apple-darwin"
        case .x86:
            target_flag = "--target=i686-apple-darwin"
        case .arm32:
            target_flag = "--target=arm-apple-darwin"
        case .Any:
            target_flag = "--target=unknown-apple-darwin"
        }
    case .BSD:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-unknown-freebsd"
        case .arm64:
            target_flag = "--target=aarch64-unknown-freebsd"
        case .x86:
            target_flag = "--target=i686-unknown-freebsd"
        case .arm32:
            target_flag = "--target=arm-unknown-freebsd"
        case .Any:
            target_flag = "--target=unknown-unknown-freebsd"
        }
    case .Any:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-unknown-none"
        case .arm64:
            target_flag = "--target=aarch64-unknown-none"
        case .x86:
            target_flag = "--target=i686-unknown-none"
        case .arm32:
            target_flag = "--target=arm-unknown-none"
        case .Any:
            target_flag = "--target=unknown-unknown-none"
        }
    }

    append(&clang_flags, target_flag)
    if plat.arch == .arm32 && plat.os != .Windows {
        append(&clang_flags, "-mfloat-abi=soft")
    }

    for name, value in defines {
        arg := strings.clone_to_cstring(
            fmt.aprintf("-D{}={}", name, value, allocator = allocator),
            allocator,
        )

        append(&clang_flags, arg)
    }

    for inc in include_dirs {
        arg := strings.clone_to_cstring(
            fmt.aprintf("-I{}", inc, allocator = allocator),
            allocator,
        )

        append(&clang_flags, arg)
    }

    if !enable_host_includes {
        append(&clang_flags, "-nostdinc")

        if inc, ok := stdinc_gen_dir.?; ok {
            arg := strings.clone_to_cstring(
                fmt.aprintf("-I{}", inc, allocator = allocator),
                allocator,
            )

            append(&clang_flags, arg)
        }
    }

    append(&clang_flags, ..flags)

    return
}

@(private)
make_forward_decls_into_actual_types :: proc(
    data: ^ClientData,
    forward_decls: [dynamic]string,
    forward_decl_type: runic.Type,
    included_file_name: Maybe(string) = nil,
    extern: []string = nil,
) {
    for decl in forward_decls {
        if decl in data.included_types do continue

        // If is extern
        if extern != nil &&
           included_file_name != nil &&
           runic.single_list_glob(extern, included_file_name.?) {
            when ODIN_DEBUG {
                fmt.eprintfln(
                    "debug: forward declaration \"{}\" will be added to externs as defined by \"from.forward_decl_type\" (default: '#Opaque')",
                    decl,
                )
            }

            om.insert(
                &data.rs.externs,
                decl,
                runic.Extern {
                    source = strings.clone(
                        included_file_name.?,
                        data.ctx.allocator,
                    ),
                    type = forward_decl_type,
                },
            )
        } else {
            if om.contains(data.rs.types, decl) do continue

            when ODIN_DEBUG {
                fmt.eprintfln(
                    "debug: forward declaration \"{}\" will be added to types as defined by \"from.forward_decl_type\" (default: '#Opaque')",
                    decl,
                )
            }

            om.insert(&data.rs.types, decl, forward_decl_type)
        }
    }
}
