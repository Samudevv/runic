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

@(private = "file")
ClientData :: struct {
    rs:             ^runic.Runestone,
    allocator:      runtime.Allocator,
    arena_alloc:    runtime.Allocator,
    err:            errors.Error,
    isz:            Int_Sizes,
    included_types: ^map[string]clang.Type,
    macros:         ^om.OrderedMap(string, Macro),
    anon_idx:       ^int,
}

generate_runestone :: proc(
    plat: runic.Platform,
    rune_file_name: string,
    rf: runic.From,
) -> (
    rs: runic.Runestone,
    err: errors.Error,
) {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)

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
    for d in platform_defines {
        append(&clang_flags, d)
    }

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

    headers := runic.platform_value_get([]string, rf.headers, plat)
    overwrite := runic.platform_value_get(
        runic.OverwriteSet,
        rf.overwrite,
        plat,
    )
    ignore := runic.platform_value_get(runic.IgnoreSet, rf.ignore, plat)

    included_types := make(map[string]clang.Type, allocator = arena_alloc)
    macros := om.make(string, Macro, allocator = arena_alloc)
    anon_idx: int
    data := ClientData {
        rs             = &rs,
        allocator      = rs_arena_alloc,
        arena_alloc    = arena_alloc,
        isz            = int_sizes_from_platform(plat),
        included_types = &included_types,
        macros         = &macros,
        anon_idx       = &anon_idx,
    }
    index := clang.createIndex(0, 0)
    defer clang.disposeIndex(index)
    units := make([dynamic]clang.TranslationUnit, arena_alloc)
    defer for unit in units {
        clang.disposeTranslationUnit(unit)
    }

    rs.constants = om.make(string, runic.Constant, allocator = rs_arena_alloc)
    rs.symbols = om.make(string, runic.Symbol, allocator = rs_arena_alloc)
    rs.types = om.make(string, runic.Type, allocator = rs_arena_alloc)

    for header in headers {
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
                case .Fatal:
                    fmt.eprint("FATAL: ")
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

                if clang.Location_isFromMainFile(cursor_location) == 0 {
                    #partial switch cursor_kind {
                    case .TypedefDecl:
                        typedef := clang.getTypedefDeclUnderlyingType(cursor)

                        type_name_clang := clang.getTypedefName(cursor_type)
                        type_name := strings.clone(
                            clang_str(type_name_clang),
                            data.arena_alloc,
                        )
                        clang.disposeString(type_name_clang)

                        data.included_types[type_name] = typedef
                    case .StructDecl:
                        if struct_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        data.included_types[display_name] = cursor_type
                    case .EnumDecl:
                        if enum_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        data.included_types[display_name] = cursor_type
                    case .UnionDecl:
                        if union_is_unnamed(display_name) do break
                        display_name = strings.clone(
                            display_name,
                            data.arena_alloc,
                        )

                        data.included_types[display_name] = cursor_type
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
                    if clang.Cursor_isFunctionInlined(cursor) != 0 do return .Continue

                    cursor_return_type := clang.getCursorResultType(cursor)
                    num_params := clang.Cursor_getNumArguments(cursor)

                    func: runic.Function

                    func_name_clang := clang.getCursorSpelling(cursor)
                    func_name := clang_str(func_name_clang)
                    defer clang.disposeString(func_name_clang)

                    type_hint := clang_func_return_type_get_type_hint(cursor)

                    func.return_type, data.err = clang_type_to_runic_type(
                        cursor_return_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        &data.rs.types,
                        rs_arena_alloc,
                        type_hint,
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
                        rs_arena_alloc,
                    )
                    func.variadic =
                        num_params != 0 &&
                        clang.isFunctionTypeVariadic(cursor_type) != 0

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
                            func = clang.Cursor_isMacroFunctionLike(cursor) !=
                            0,
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
    unknown_types := make([dynamic]string, arena_alloc)
    for &entry in rs.types.data {
        type := &entry.value
        unknowns := check_for_unknown_types(type, rs.types)
        extend_unknown_types(&unknown_types, unknowns)
    }

    for &entry in rs.symbols.data {
        sym := &entry.value

        switch &value in sym.value {
        case runic.Function:
            unknowns := check_for_unknown_types(&value.return_type, rs.types)
            extend_unknown_types(&unknown_types, unknowns)

            for &param in value.parameters {
                unknowns = check_for_unknown_types(&param.type, rs.types)
                extend_unknown_types(&unknown_types, unknowns)
            }
        case runic.Type:
            unknowns := check_for_unknown_types(&value, rs.types)
            extend_unknown_types(&unknown_types, unknowns)
        }
    }

    // Try to find the unknown types in the includes
    for unknown in unknown_types {
        if included_type, ok := included_types[unknown]; ok {
            cursor := clang.getTypeDeclaration(included_type)

            prev_idx := om.length(rs.types)

            if included_type.kind == .Elaborated {
                named_type := clang.Type_getNamedType(included_type)
                named_cursor := clang.getTypeDeclaration(named_type)
                named_name_clang := clang.getCursorDisplayName(named_cursor)
                named_name := clang_str(named_name_clang)
                defer clang.disposeString(named_name_clang)

                if named_name == unknown {
                    included_type = named_type
                    cursor = named_cursor
                }
            }

            type: runic.Type = ---
            type, data.err = clang_type_to_runic_type(
                included_type,
                cursor,
                data.isz,
                data.anon_idx,
                &rs.types,
                rs_arena_alloc,
            )

            for &entry in rs.types.data[prev_idx:] {
                t := &entry.value
                unknowns := check_for_unknown_types(t, data.rs.types)
                extend_unknown_types(&unknown_types, unknowns)
            }

            if data.err != nil {
                fmt.eprintln(data.err, "\n")
                data.err = nil
                continue
            }

            unknowns := check_for_unknown_types(&type, data.rs.types)
            extend_unknown_types(&unknown_types, unknowns)

            om.insert(&data.rs.types, unknown, type)
        }
    }

    runic.ignore_types(&rs.types, ignore)

    // Validate unknown types
    // Check if the previously unknown types are now known
    // If so change the spec to a string
    for &entry in rs.types.data {
        type := &entry.value
        validate_unknown_types(type, rs.types)
    }

    for &entry in rs.symbols.data {
        sym := &entry.value

        switch &value in sym.value {
        case runic.Function:
            validate_unknown_types(&value.return_type, rs.types)

            for &param in value.parameters {
                validate_unknown_types(&param.type, rs.types)
            }
        case runic.Type:
            validate_unknown_types(&value, rs.types)
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

    // Ignore stuff
    runic.ignore_constants(&rs.constants, ignore)
    runic.ignore_symbols(&rs.symbols, ignore)

    // Overwrite stuff
    for name in overwrite.constants {
        if idx, ok := om.index(rs.constants, name); ok {
            ow_const, ow_err := runic.overwrite_constant(overwrite, name)
            if ow_err != nil {
                fmt.eprintfln(
                    "Constant \"{}\" failed to overwrite: {}",
                    name,
                    ow_err,
                )
                continue
            }

            if ow_const == nil do continue

            rs.constants.data[idx].value = ow_const.?
        }
    }

    for name in overwrite.functions {
        if idx, ok := om.index(rs.symbols, name); ok {
            if _, is_func := rs.symbols.data[idx].value.value.(runic.Function); !is_func do continue

            ow_func, ow_err := runic.overwrite_func(overwrite, name)
            if ow_err != nil {
                fmt.eprintfln(
                    "Function \"{}\" failed to overwrite: {}",
                    name,
                    ow_err,
                )
                continue
            }

            if ow_func == nil do continue

            rs.symbols.data[idx].value.value = ow_func.?
        }
    }

    for name in overwrite.variables {
        if idx, ok := om.index(rs.symbols, name); ok {
            if _, is_var := rs.symbols.data[idx].value.value.(runic.Type); !is_var do continue

            ow_var, ow_err := runic.overwrite_var(overwrite, name)
            if ow_err != nil {
                fmt.eprintfln(
                    "Variable \"{}\" failed to overwrite: {}",
                    name,
                    ow_err,
                )
                continue
            }

            if ow_var == nil do continue

            rs.symbols.data[idx].value.value = ow_var.?
        }
    }

    for name in overwrite.types {
        if idx, ok := om.index(rs.types, name); ok {
            ow_type, ow_err := runic.overwrite_type(overwrite, name)
            if ow_err != nil {
                fmt.eprintfln(
                    "Type \"{}\" failed to overwrite: {}",
                    name,
                    ow_err,
                )
                continue
            }

            if ow_type == nil do continue

            rs.types.data[idx].value = ow_type.?
        }
    }


    return
}
