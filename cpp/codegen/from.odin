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

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
Macro :: struct {
    def:  string,
    func: bool,
}

@(private)
IncludedType :: struct {
    type:      union {
        clang.Type,
        runic.Type,
    },
    file_name: string,
    system:    bool,
}

@(private = "file")
ClientData :: struct {
    rs:             ^runic.Runestone,
    allocator:      runtime.Allocator,
    arena_alloc:    runtime.Allocator,
    err:            errors.Error,
    isz:            Int_Sizes,
    included_types: ^map[string]IncludedType,
    included_anons: ^om.OrderedMap(string, runic.Type),
    macros:         ^om.OrderedMap(string, Macro),
    anon_idx:       ^int,
    rune_file_name: string,
}

generate_runestone :: proc(
    plat: runic.Platform,
    rune_file_name: string,
    rf: runic.From,
) -> (
    rs: runic.Runestone,
    err: errors.Error,
) {
    if !filepath.is_abs(rune_file_name) do return rs, errors.message("Internal Error: rune_file_name (\"{}\") needs to be absolute for cpp_codegen.generate_runestone", rune_file_name)

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    rs_arena_alloc := runic.init_runestone(&rs)

    rs.platform = plat
    runic.set_library(plat, &rs, rf)

    clang_flags := make([dynamic]cstring, arena_alloc)

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

    if disable_stdint_macros, ok := runic.platform_value_get(
        bool,
        rf.disable_stdint_macros,
        plat,
    ); !(ok && disable_stdint_macros) {

        // Macros for stdint (+ size_t) types
        stdint_macros: []cstring
        switch plat.os {
        case .Windows:
            switch plat.arch {
            case .x86_64, .arm64:
                stdint_macros = []cstring {
                    "-Dint8_t=signed char",
                    "-Dint16_t=signed short",
                    "-Dint32_t=signed int",
                    "-Dint64_t=signed long long",
                    "-Duint8_t=unsigned char",
                    "-Duint16_t=unsigned short",
                    "-Duint32_t=unsigned int",
                    "-Duint64_t=unsigned long long",
                    "-Dbool=_Bool",
                    "-Dsize_t=unsigned long long",
                    "-Dintptr_t=signed long long",
                    "-Duintptr_t=unsigned long long",
                    "-Dptrdiff_t=signed long long",
                }
            case .x86, .arm32:
                stdint_macros = []cstring {
                    "-Dint8_t=signed char",
                    "-Dint16_t=signed short",
                    "-Dint32_t=signed int",
                    "-Dint64_t=signed long long",
                    "-Duint8_t=unsigned char",
                    "-Duint16_t=unsigned short",
                    "-Duint32_t=unsigned int",
                    "-Duint64_t=unsigned long long",
                    "-Dbool=_Bool",
                    "-Dsize_t=unsigned long",
                    "-Dintptr_t=signed long",
                    "-Duintptr_t=unsigned long",
                    "-Dptrdiff_t=signed long",
                }
            case .Any:
            // Leave it empty, but should be unreachable
            }
        case .Linux, .BSD, .Macos:
            stdint_macros = []cstring {
                "-Dint8_t=signed char",
                "-Dint16_t=signed short",
                "-Dint32_t=signed int",
                "-Dint64_t=signed long long",
                "-Duint8_t=unsigned char",
                "-Duint16_t=unsigned short",
                "-Duint32_t=unsigned int",
                "-Duint64_t=unsigned long long",
                "-Dbool=_Bool",
                "-Dsize_t=unsigned long",
                "-Dintptr_t=signed long",
                "-Duintptr_t=unsigned long",
                "-Dptrdiff_t=signed long",
            }
        case .Any:
        // Leave it empty, but should be unreachable
        }

        append(&clang_flags, ..stdint_macros)
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
            target_flag = "--target=any-linux-gnu"
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
            target_flag = "--target=any-windows-msvc"
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
            target_flag = "--target=any-apple-darwin"
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
            target_flag = "--target=any-unknown-freebsd"
        }
    case .Any:
        switch plat.arch {
        case .x86_64:
            target_flag = "--target=x86_64-any-none"
        case .arm64:
            target_flag = "--target=aarch64-any-none"
        case .x86:
            target_flag = "--target=i686-any-none"
        case .arm32:
            target_flag = "--target=arm-any-none"
        case .Any:
            target_flag = "--target=any-any-none"
        }
    }

    append(&clang_flags, target_flag)
    if plat.arch == .arm32 {
        append(&clang_flags, "-mfloat-abi=soft")
    }

    if rune_defines, ok := runic.platform_value_get(
        map[string]string,
        rf.defines,
        plat,
    ); ok {
        for name, value in rune_defines {
            arg := strings.clone_to_cstring(
                fmt.aprintf("-D{}={}", name, value, allocator = arena_alloc),
                arena_alloc,
            )

            append(&clang_flags, arg)
        }
    }

    if include_dirs, ok := runic.platform_value_get(
        []string,
        rf.includedirs,
        plat,
    ); ok {
        for inc in include_dirs {
            arg := strings.clone_to_cstring(
                fmt.aprintf("-I{}", inc, allocator = arena_alloc),
                arena_alloc,
            )

            append(&clang_flags, arg)
        }
    }

    // Generate system includes as empty files just for placeholders
    stdinc_gen_dir: Maybe(string)
    defer if gen_dir, ok := stdinc_gen_dir.?; ok {
        delete_system_includes(gen_dir)
    }

    if enable_host_includes, ok := runic.platform_value_get(
        bool,
        rf.enable_host_includes,
        plat,
    ); !(ok && enable_host_includes) {
        append(&clang_flags, "-nostdinc")

        if disable_system_include_gen, gen_ok := runic.platform_value_get(
            bool,
            rf.disable_system_include_gen,
            plat,
        ); !(gen_ok && disable_system_include_gen) {
            stdinc_gen_dir_ok: bool = ---
            stdinc_gen_dir, stdinc_gen_dir_ok = system_includes_gen_dir(
                plat,
                arena_alloc,
            )

            if stdinc_gen_dir_ok {
                ok = generate_system_includes(stdinc_gen_dir.?)

                if ok {
                    include_dir := strings.concatenate(
                        {"-I", stdinc_gen_dir.?},
                        arena_alloc,
                    )
                    include_dir_cstr := strings.clone_to_cstring(
                        include_dir,
                        arena_alloc,
                    )
                    append(&clang_flags, include_dir_cstr)
                } else {
                    fmt.eprintfln(
                        "FATAL: failed to generate system includes for platform {}.{} into \"{}\"",
                        plat.os,
                        plat.arch,
                        stdinc_gen_dir,
                    )
                }
            } else {
                stdinc_gen_dir = nil
                fmt.eprintfln(
                    "FATAL: failed to create temporary directory for system includes for platform {}.{}",
                    plat.os,
                    plat.arch,
                )
            }
        }
    }

    if flags, ok := runic.platform_value_get([]cstring, rf.flags, plat); ok {
        for f in flags {
            append(&clang_flags, f)
        }
    }

    headers := runic.platform_value_get([]string, rf.headers, plat)
    ignore := runic.platform_value_get(runic.IgnoreSet, rf.ignore, plat)

    included_types := make(map[string]IncludedType)
    defer delete(included_types)

    included_anons := om.make(string, runic.Type)
    defer om.delete(included_anons)

    macros := om.make(string, Macro)
    defer om.delete(macros)

    anon_idx: int
    data := ClientData {
        rs             = &rs,
        allocator      = rs_arena_alloc,
        arena_alloc    = arena_alloc,
        isz            = int_sizes_from_platform(plat),
        included_types = &included_types,
        included_anons = &included_anons,
        macros         = &macros,
        anon_idx       = &anon_idx,
        rune_file_name = rune_file_name,
    }
    index := clang.createIndex(0, 0)
    defer clang.disposeIndex(index)
    units := make(
        [dynamic]clang.TranslationUnit,
        allocator = arena_alloc,
        len = len(headers),
        cap = len(headers),
    )
    defer for unit in units {
        clang.disposeTranslationUnit(unit)
    }

    when ODIN_DEBUG {
        fmt.eprint("clang flags: ")
        for flag in clang_flags {
            fmt.eprintf("\"{}\" ", flag)
        }
        fmt.eprintln()
    }

    for header in headers {
        _, os_stat := os.stat(header, arena_alloc)
        #partial switch stat in os_stat {
        case os.General_Error:
            if stat == .Not_Exist {
                err = errors.message(
                    "failed to find header file: \"{}\"",
                    header,
                )
                return
            }
            err = errors.message(
                "failed to open header file \"{}\": {}",
                header,
                stat,
            )
            return
        case nil:
        case:
            err = errors.message(
                "failed to open header file \"{}\": {}",
                header,
                stat,
            )
            return
        }

        fmt.eprintfln("Parsing \"{}\" ...", header)

        header_cstr := strings.clone_to_cstring(header, arena_alloc)

        unit := clang.parseTranslationUnit(
            index,
            header_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            .DetailedPreprocessingRecord | .SkipFunctionBodies,
        )

        if unit == nil {
            err = errors.message(
                "\"{}\" failed to parse translation unit",
                header,
            )
            return
        }

        append(&units, unit)

        is_fatal: bool
        num_diag := clang.getNumDiagnostics(unit)
        if num_diag != 0 {
            for idx in 0 ..< num_diag {
                dig := clang.getDiagnostic(unit, idx)
                defer clang.disposeDiagnostic(dig)

                sev := clang.getDiagnosticSeverity(dig)
                dig_msg := clang.formatDiagnostic(
                    dig,
                    clang.defaultDiagnosticDisplayOptions(),
                )
                defer clang.disposeString(dig_msg)
                dig_str := clang.getCString(dig_msg)

                switch sev {
                case .Error:
                    fmt.eprint("ERROR: ")
                    is_fatal = true
                case .Fatal:
                    fmt.eprint("FATAL: ")
                    is_fatal = true
                case .Warning:
                    fmt.eprint("WARNING: ")
                case .Note:
                    fmt.eprint("NOTE: ")
                case .Ignored:
                    fmt.eprint("IGNORED: ")
                }

                fmt.eprintln(dig_str)
            }
        }

        if is_fatal {
            fmt.eprintln(
                "Errors occurred. The resulting runestone can not be trusted! Make sure to fix the errors accordingly. If system includes can not be found you may want to add them from https://git.musl-libc.org/cgit/musl/",
            )
        }

        cursor := clang.getTranslationUnitCursor(unit)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.Cursor,
                client_data: clang.ClientData,
            ) -> clang.ChildVisitResult {
                data := cast(^ClientData)client_data
                context = runtime.default_context()
                rs_arena_alloc := data.allocator

                cursor_kind := clang.getCursorKind(cursor)
                cursor_type := clang.getCursorType(cursor)
                cursor_location := clang.getCursorLocation(cursor)
                display_name_clang := clang.getCursorDisplayName(cursor)
                display_name := clang_str(display_name_clang)
                storage_class := clang.Cursor_getStorageClass(cursor)

                defer clang.disposeString(display_name_clang)

                if !clang.Location_isFromMainFile(cursor_location) {
                    file: clang.File = ---
                    clang.getSpellingLocation(
                        cursor_location,
                        &file,
                        nil,
                        nil,
                        nil,
                    )
                    file_name_clang := clang.getFileName(file)
                    defer clang.disposeString(file_name_clang)
                    file_name, _ := strings.replace_all(
                        clang_str(file_name_clang),
                        "\\",
                        "/",
                        data.arena_alloc,
                    )
                    rel_file_name, rel_ok := runic.absolute_to_file(
                        data.rune_file_name,
                        file_name,
                        data.arena_alloc,
                    )
                    if rel_ok do file_name = rel_file_name

                    #partial switch cursor_kind {
                    case .TypedefDecl:
                        typedef := clang.getTypedefDeclUnderlyingType(cursor)

                        type_name_clang := clang.getTypedefName(cursor_type)
                        type_name := strings.clone(
                            clang_str(type_name_clang),
                            data.arena_alloc,
                        )
                        clang.disposeString(type_name_clang)

                        if !(type_name in data.included_types) {
                            // TODO: handle pointers to function pointers
                            if typedef.kind == .Pointer {
                                pointee := clang.getPointeeType(typedef)
                                if pointee.kind == .FunctionProto ||
                                   pointee.kind == .FunctionNoProto {
                                    type: runic.Type = ---
                                    type, data.err = clang_type_to_runic_type(
                                        typedef,
                                        cursor,
                                        data.isz,
                                        data.anon_idx,
                                        data.included_anons,
                                        rs_arena_alloc,
                                        nil,
                                        type_name,
                                    )
                                    if data.err != nil {
                                        // TODO: add file name and line, column to the error output
                                        fmt.eprintfln(
                                            "{}: failed to parse function pointer: {}",
                                            type_name,
                                            data.err,
                                        )
                                        data.err = nil
                                        break
                                    }

                                    data.included_types[type_name] =
                                        IncludedType {
                                            file_name = strings.clone(
                                                file_name,
                                                data.arena_alloc,
                                            ),
                                            type      = type,
                                            system    = bool(
                                                clang.Location_isInSystemHeader(
                                                    cursor_location,
                                                ),
                                            ),
                                        }
                                    break
                                }
                            }

                            data.included_types[type_name] = IncludedType {
                                    file_name = strings.clone(
                                        file_name,
                                        data.arena_alloc,
                                    ),
                                    type      = typedef,
                                    system    = bool(
                                        clang.Location_isInSystemHeader(
                                            cursor_location,
                                        ),
                                    ),
                                }
                        }
                    case .StructDecl:
                        if struct_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        if !(display_name in data.included_types) {
                            data.included_types[display_name] = IncludedType {
                                file_name = strings.clone(
                                    file_name,
                                    data.arena_alloc,
                                ),
                                type      = cursor_type,
                                system    = bool(
                                    clang.Location_isInSystemHeader(
                                        cursor_location,
                                    ),
                                ),
                            }
                        }
                    case .EnumDecl:
                        if enum_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        if !(display_name in data.included_types) {
                            data.included_types[display_name] = IncludedType {
                                file_name = strings.clone(
                                    file_name,
                                    data.arena_alloc,
                                ),
                                type      = cursor_type,
                                system    = bool(
                                    clang.Location_isInSystemHeader(
                                        cursor_location,
                                    ),
                                ),
                            }
                        }
                    case .UnionDecl:
                        if union_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        if !(display_name in data.included_types) {
                            data.included_types[display_name] = IncludedType {
                                file_name = strings.clone(
                                    file_name,
                                    data.arena_alloc,
                                ),
                                type      = cursor_type,
                                system    = bool(
                                    clang.Location_isInSystemHeader(
                                        cursor_location,
                                    ),
                                ),
                            }
                        }
                    }

                    return .Continue
                }

                #partial cursor_kind_switch: switch cursor_kind {
                case .TypedefDecl:
                    typedef := clang.getTypedefDeclUnderlyingType(cursor)

                    type_name_clang := clang.getTypedefName(cursor_type)
                    type_name := clang_str(type_name_clang)
                    defer clang.disposeString(type_name_clang)

                    type_hint: Maybe(string)
                    if typedef.kind == .Int {
                        type_hint = clang_typedef_get_type_hint(cursor)
                    }

                    if typedef.kind == .Elaborated {
                        named_type := clang.Type_getNamedType(typedef)
                        named_cursor := clang.getTypeDeclaration(named_type)

                        named_name_clang := clang.getCursorDisplayName(
                            named_cursor,
                        )
                        named_name := clang_str(named_name_clang)
                        defer clang.disposeString(named_name_clang)

                        if named_name == type_name {
                            break
                        }
                    }

                    type: runic.Type = ---
                    type, data.err = clang_type_to_runic_type(
                        typedef,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        &data.rs.types,
                        rs_arena_alloc,
                        type_hint,
                        type_name,
                    )
                    if data.err != nil do break

                    om.insert(
                        &data.rs.types,
                        strings.clone(type_name, rs_arena_alloc),
                        type,
                    )
                case .VarDecl:
                    switch storage_class {
                    case .Invalid,
                         .Static,
                         .OpenCLWorkGroupLocal,
                         .PrivateExtern:
                        return .Continue
                    case .Auto, .None, .Register, .Extern:
                    }

                    type_hint: Maybe(string)
                    if cursor_type.kind == .Int {
                        type_hint = clang_var_decl_get_type_hint(cursor)
                    }

                    type: runic.Type = ---
                    type, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        &data.rs.types,
                        rs_arena_alloc,
                        type_hint,
                        display_name,
                    )
                    if data.err != nil do break

                    var_name := strings.clone(display_name, rs_arena_alloc)

                    if _, ok := type.spec.(runic.FunctionPointer); !ok {
                        handle_anon_type(
                            &type,
                            &data.rs.types,
                            data.anon_idx,
                            var_name,
                            data.allocator,
                        )
                    }

                    om.insert(
                        &data.rs.symbols,
                        var_name,
                        runic.Symbol{value = type},
                    )
                case .StructDecl, .UnionDecl, .EnumDecl:
                    if cursor_kind == .StructDecl && struct_is_unnamed(display_name) do return .Continue
                    if cursor_kind == .UnionDecl && union_is_unnamed(display_name) do return .Continue
                    if cursor_kind == .EnumDecl && enum_is_unnamed(display_name) do return .Continue

                    type: runic.Type = ---
                    type, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        &data.rs.types,
                        rs_arena_alloc,
                        name_hint = display_name,
                    )
                    if data.err != nil do break

                    #partial switch spec in type.spec {
                    case runic.Struct:
                        if len(spec.members) == 0 do return .Continue
                    case runic.Union:
                        if len(spec.members) == 0 do return .Continue
                    case runic.Enum:
                        if len(spec.entries) == 0 {
                            type.spec = spec.type
                        }
                    }

                    om.insert(
                        &data.rs.types,
                        strings.clone(display_name, rs_arena_alloc),
                        type,
                    )
                case .FunctionDecl:
                    // NOTE: defining structs, unions and enums with a name inside the parameter list is not supported
                    switch storage_class {
                    case .Invalid,
                         .Static,
                         .OpenCLWorkGroupLocal,
                         .PrivateExtern:
                        return .Continue
                    case .Auto, .None, .Register, .Extern:
                    }
                    if clang.Cursor_isFunctionInlined(cursor) do return .Continue

                    cursor_return_type := clang.getCursorResultType(cursor)
                    num_params := clang.Cursor_getNumArguments(cursor)

                    func: runic.Function

                    func_name_clang := clang.getCursorSpelling(cursor)
                    func_name := clang_str(func_name_clang)
                    defer clang.disposeString(func_name_clang)

                    type_hint := clang_func_return_type_get_type_hint(cursor)

                    return_type_name_hint := strings.concatenate(
                        {func_name, "_return_type"},
                    )
                    defer delete(return_type_name_hint)

                    func.return_type, data.err = clang_type_to_runic_type(
                        cursor_return_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        &data.rs.types,
                        rs_arena_alloc,
                        type_hint,
                        return_type_name_hint,
                    )
                    if data.err != nil do break

                    handle_anon_type(
                        &func.return_type,
                        &data.rs.types,
                        data.anon_idx,
                        func_name,
                        rs_arena_alloc,
                    )

                    func.parameters = make(
                        [dynamic]runic.Member,
                        allocator = rs_arena_alloc,
                        len = 0,
                        cap = num_params,
                    )
                    func.variadic = bool(
                        num_params != 0 &&
                        clang.isFunctionTypeVariadic(cursor_type),
                    )

                    for idx in 0 ..< num_params {
                        param_cursor := clang.Cursor_getArgument(
                            cursor,
                            u32(idx),
                        )
                        param_type := clang.getCursorType(param_cursor)
                        param_name_clang := clang.getCursorSpelling(
                            param_cursor,
                        )
                        param_name := clang_str(param_name_clang)

                        defer clang.disposeString(param_name_clang)

                        param_name_str: string = ---
                        if len(param_name) == 0 {
                            param_name_str = fmt.aprintf(
                                "param{}",
                                idx,
                                allocator = rs_arena_alloc,
                            )
                        } else {
                            param_name_str = strings.clone(
                                param_name,
                                rs_arena_alloc,
                            )
                        }

                        type_hint = nil
                        if param_type.kind == .Int {
                            type_hint = clang_var_decl_get_type_hint(
                                param_cursor,
                            )
                        }

                        type: runic.Type = ---
                        type, data.err = clang_type_to_runic_type(
                            param_type,
                            param_cursor,
                            data.isz,
                            data.anon_idx,
                            &data.rs.types,
                            rs_arena_alloc,
                            type_hint,
                            param_name,
                        )
                        if data.err != nil do break cursor_kind_switch

                        handle_anon_type(
                            &type,
                            &data.rs.types,
                            data.anon_idx,
                            param_name_str,
                            rs_arena_alloc,
                        )

                        append(
                            &func.parameters,
                            runic.Member{name = param_name_str, type = type},
                        )
                    }

                    if len(func.parameters) != 0 {
                        has_va_list: bool

                        #partial switch spec in
                            func.parameters[len(func.parameters) - 1].type.spec {
                        case string:
                            if spec == "va_list" do has_va_list = true
                        case runic.Unknown:
                            if spec == "va_list" do has_va_list = true
                        }

                        if has_va_list {
                            pop(&func.parameters)
                            func.variadic = true
                        }
                    }

                    om.insert(
                        &data.rs.symbols,
                        strings.clone(func_name, rs_arena_alloc),
                        runic.Symbol{value = func},
                    )
                case .MacroDefinition:
                    cursor_extent := clang.getCursorExtent(cursor)
                    cursor_start := clang.getRangeStart(cursor_extent)
                    cursor_end := clang.getRangeEnd(cursor_extent)

                    start_offset, end_offset: u32 = ---, ---
                    file: clang.File = ---
                    clang.getSpellingLocation(
                        cursor_start,
                        &file,
                        nil,
                        nil,
                        &start_offset,
                    )
                    clang.getSpellingLocation(
                        cursor_end,
                        nil,
                        nil,
                        nil,
                        &end_offset,
                    )

                    unit := clang.Cursor_getTranslationUnit(cursor)

                    buffer_size: u64 = ---
                    buf := clang.getFileContents(unit, file, &buffer_size)
                    buffer := strings.string_from_ptr(
                        cast(^byte)buf,
                        int(buffer_size),
                    )

                    macro_def := buffer[start_offset:end_offset]
                    macro_name_value := strings.split_after_n(
                        macro_def,
                        " ",
                        2,
                        data.arena_alloc,
                    )

                    macro_name := macro_name_value[0]
                    macro_value: string = ---
                    if len(macro_name_value) == 2 {
                        macro_value = macro_name_value[1]
                    } else {
                        macro_value = ""
                    }

                    om.insert(
                        data.macros,
                        strings.trim_right_space(macro_name),
                        Macro {
                            def = strings.trim_left_space(macro_value),
                            func = bool(
                                clang.Cursor_isMacroFunctionLike(cursor),
                            ),
                        },
                    )
                case .MacroExpansion, .InclusionDirective:
                // Ignore
                case:
                    fmt.eprintln(
                        clang_source_error(
                            cursor,
                            fmt.aprintf(
                                "Other Cursor Type: {}\n\n\n",
                                cursor_kind,
                                allocator = errors.error_allocator,
                            ),
                        ),
                    )
                }

                if data.err != nil {
                    fmt.eprintln(data.err, "\n")
                    data.err = nil
                }

                return .Continue
            },
            &data,
        )

        if data.err != nil {
            err = data.err
            return
        }
    }

    runic.ignore_types(&rs.types, ignore)

    // Look for unknown types
    unknown_types := runic.check_for_unknown_types(&rs, arena_alloc)

    // Try to find the unknown types in the includes
    unknown_anons := om.make(string, runic.Type)
    for unknown in unknown_types {
        if included_type_value, ok := included_types[unknown]; ok {
            type: runic.Type = ---
            switch &included_type in included_type_value.type {
            case clang.Type:
                cursor := clang.getTypeDeclaration(included_type)

                if included_type.kind == .Elaborated {
                    named_type := clang.Type_getNamedType(included_type)
                    named_cursor := clang.getTypeDeclaration(named_type)
                    named_name_clang := clang.getCursorDisplayName(
                        named_cursor,
                    )
                    named_name := clang_str(named_name_clang)
                    defer clang.disposeString(named_name_clang)

                    if named_name == unknown {
                        file: clang.File = ---
                        named_location := clang.getCursorLocation(named_cursor)
                        clang.getSpellingLocation(
                            named_location,
                            &file,
                            nil,
                            nil,
                            nil,
                        )
                        file_name_clang := clang.getFileName(file)
                        defer clang.disposeString(file_name_clang)
                        file_name := clang_str(file_name_clang)

                        included_type = named_type
                        included_type_value.file_name = strings.clone(
                            file_name,
                            arena_alloc,
                        )
                        cursor = named_cursor
                    }
                }

                type, data.err = clang_type_to_runic_type(
                    included_type,
                    cursor,
                    data.isz,
                    data.anon_idx,
                    &unknown_anons,
                    rs_arena_alloc,
                    name_hint = unknown,
                )
            case runic.Type:
                type = included_type

                #partial switch spec in type.spec {
                case runic.Struct:
                    for member in spec.members {
                        #partial switch m in member.type.spec {
                        case string:
                            if anon, a_ok := om.get(included_anons, m); a_ok {
                                om.insert(&unknown_anons, m, anon)
                            }
                        }
                    }
                case runic.Union:
                    for member in spec.members {
                        #partial switch m in member.type.spec {
                        case string:
                            if anon, a_ok := om.get(included_anons, m); a_ok {
                                om.insert(&unknown_anons, m, anon)
                            }
                        }
                    }
                case runic.FunctionPointer:
                    for param in spec.parameters {
                        #partial switch p in param.type.spec {
                        case string:
                            if anon, a_ok := om.get(included_anons, p); a_ok {
                                om.insert(&unknown_anons, p, anon)
                            }
                        }
                    }
                    #partial switch rv in spec.return_type.spec {
                    case string:
                        if anon, a_ok := om.get(included_anons, rv); a_ok {
                            om.insert(&unknown_anons, rv, anon)
                        }
                    }
                case string:
                    if anon, a_ok := om.get(included_anons, spec); a_ok {
                        om.insert(&unknown_anons, spec, anon)
                    }
                }
            }

            included_file_name := strings.clone(
                included_type_value.file_name,
                rs_arena_alloc,
            )
            is_extern := runic.single_list_glob(rf.extern, included_file_name)

            for &entry in unknown_anons.data {
                anon_name, t := entry.key, &entry.value

                if b, b_ok := t.spec.(runic.Builtin); b_ok && b == .Untyped {
                    // This means that there was a forward declaration used inside a Struct etc. therefore we can ignore this
                    continue
                }

                if is_extern {
                    unknowns := runic.check_for_unknown_types(t, rs.externs)
                    runic.extend_unknown_types(&unknown_types, unknowns)

                    om.insert(
                        &rs.externs,
                        anon_name,
                        runic.Extern{source = included_file_name, type = t^},
                    )
                } else {
                    unknowns := runic.check_for_unknown_types(t, data.rs.types)
                    runic.extend_unknown_types(&unknown_types, unknowns)

                    om.insert(&rs.types, anon_name, t^)
                }
            }
            om.delete(unknown_anons)
            unknown_anons = om.make(string, runic.Type)

            if data.err != nil {
                fmt.eprintln(data.err, "\n")
                data.err = nil
                continue
            }


            if is_extern {
                unknowns := runic.check_for_unknown_types(
                    &type,
                    data.rs.externs,
                )
                runic.extend_unknown_types(&unknown_types, unknowns)

                om.insert(
                    &data.rs.externs,
                    unknown,
                    runic.Extern{source = included_file_name, type = type},
                )
            } else {
                unknowns := runic.check_for_unknown_types(&type, data.rs.types)
                runic.extend_unknown_types(&unknown_types, unknowns)

                om.insert(&data.rs.types, unknown, type)
            }
        } else {
            // If the type is #Untyped then it technically exists and we don't need to notify the user about it
            if !(om.contains(data.rs.types, unknown) ||
                   om.contains(data.rs.externs, unknown)) {
                fmt.eprintfln(
                    "Unknown type \"{}\" has not been found in the includes",
                    unknown,
                )
            }
        }
    }
    om.delete(unknown_anons)

    runic.ignore_types(&rs.types, ignore)

    // Remove all types that are they same inside of the externs
    // If a type is Untyped then the same type of the externs takes
    // precedence
    for entry in rs.externs.data {
        name := entry.key
        if om.contains(rs.types, name) {
            om.delete_key(&rs.types, name)
        }
    }

    // Handle Macros
    if om.length(macros) != 0 {
        macro_file_name: string = ---
        {
            macro_file: os.Handle = ---
            macro_file_err: errors.Error = ---
            macro_file, macro_file_name, macro_file_err = temp_file()
            if macro_file_err != nil {
                err = errors.message(
                    "failed to create macro file: {}",
                    macro_file_err,
                )
                return
            }
            defer os.close(macro_file)

            stringify_name, stringify2_name: strings.Builder
            strings.builder_init(&stringify_name, arena_alloc)
            strings.builder_init(&stringify2_name, arena_alloc)

            strings.write_rune(&stringify_name, 'S')
            strings.write_string(&stringify2_name, "SS")

            for om.contains(macros, strings.to_string(stringify_name)) {
                strings.write_rune(&stringify_name, '_')
            }
            for om.contains(macros, strings.to_string(stringify2_name)) {
                strings.write_rune(&stringify2_name, '_')
            }

            fmt.fprintf(
                macro_file,
                `#define {}(X) #X
#define {}(X) {}(X)
`,
                strings.to_string(stringify2_name),
                strings.to_string(stringify_name),
                strings.to_string(stringify2_name),
            )

            for entry in macros.data {
                name, macro := entry.key, entry.value

                fmt.fprintfln(macro_file, "#define {} {}", name, macro.def)
            }

            os.write_string(macro_file, "const char")

            for entry, idx in macros.data {
                name, macro := entry.key, entry.value
                if macro.func || len(macro.def) == 0 do continue

                prefix_name := strings.concatenate({"R", name}, arena_alloc)
                for om.contains(macros, prefix_name) {
                    prefix_name = strings.concatenate(
                        {"_", prefix_name},
                        arena_alloc,
                    )
                }

                fmt.fprintf(
                    macro_file,
                    "*{}={}({})",
                    prefix_name,
                    strings.to_string(stringify_name),
                    name,
                )
                if idx == om.length(macros) - 1 {
                    os.write_rune(macro_file, ';')
                } else {
                    os.write_rune(macro_file, ',')
                }
            }
        }

        defer delete(macro_file_name)
        defer os.remove(macro_file_name)

        macro_file_name_cstr := strings.clone_to_cstring(
            macro_file_name,
            arena_alloc,
        )

        macro_index := clang.createIndex(0, 0)
        defer clang.disposeIndex(macro_index)

        append(&clang_flags, "-xc")
        append(&clang_flags, "--std=c99")
        unit := clang.parseTranslationUnit(
            macro_index,
            macro_file_name_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            .SkipFunctionBodies | .SingleFileParse,
        )
        if unit == nil {
            err = errors.message("failed to parse macro file")
            return
        }
        defer clang.disposeTranslationUnit(unit)

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

                #partial switch cursor_kind {
                case .VarDecl:
                    var_name_clang := clang.getCursorSpelling(cursor)
                    var_name := clang_str(var_name_clang)
                    defer clang.disposeString(var_name_clang)

                    start: int = ---
                    for r, idx in var_name {
                        if r == 'R' {
                            start = idx
                            break
                        }
                    }
                    start += 1

                    var_name_str := strings.clone(
                        var_name[start:],
                        data.allocator,
                    )

                    om.insert(
                        &data.rs.constants,
                        var_name_str,
                        runic.Constant{},
                    )
                case .StringLiteral:
                    const_value_clang := clang.getCursorSpelling(cursor)
                    const_value := clang_str(const_value_clang)
                    defer clang.disposeString(const_value_clang)

                    const_value = const_value[1:len(const_value) - 1]

                    entry := &data.rs.constants.data[len(data.rs.constants.data) - 1]
                    const := &entry.value
                    const.type.spec = runic.Builtin.Untyped

                    if strings.has_prefix(const_value, "\"") &&
                       strings.has_suffix(const_value, "\"") {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_value, "\""),
                                "\"",
                            ),
                            data.allocator,
                        )
                        const.type.spec = runic.Builtin.String
                    } else if strings.has_prefix(const_value, "'") &&
                       strings.has_suffix(const_value, "'") &&
                       len(const_value) == 3 {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_value, "'"),
                                "'",
                            ),
                            data.allocator,
                        )
                        const.type.spec = runic.Builtin.SInt8
                    } else if value_i64, ok_i64 := strconv.parse_i64(
                        const_value,
                    ); ok_i64 {
                        const.value = value_i64
                    } else if value_f64, ok_f64 := strconv.parse_f64(
                        const_value,
                    ); ok_f64 {
                        const.value = value_f64
                    } else {
                        name := entry.key

                        for &sym_entry in data.rs.symbols.data {
                            sym_name, sym := sym_entry.key, &sym_entry.value
                            if const_value == sym_name {
                                append(&sym.aliases, name)
                                om.delete_key(&data.rs.constants, name)
                                return .Recurse
                            }
                        }

                        for type_entry in data.rs.types.data {
                            type_name := type_entry.key

                            if const_value == type_name {
                                om.insert(
                                    &data.rs.types,
                                    name,
                                    runic.Type{spec = type_name},
                                )
                                om.delete_key(&data.rs.constants, name)
                                return .Recurse
                            }
                        }

                        const.value = strings.clone(
                            const_value,
                            data.allocator,
                        )
                    }
                }

                return .Recurse
            },
            &data,
        )
    }

    return
}

