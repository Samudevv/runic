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

// TODO: handle param names and such that are keywords or types and such
package cpp_codegen

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ccdg "root:c/codegen"
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
    isz:            ccdg.Int_Sizes,
    included_types: ^map[string]clang.CXType,
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

    included_types := make(map[string]clang.CXType, allocator = arena_alloc)
    macros := om.make(string, Macro, allocator = arena_alloc)
    anon_idx: int
    data := ClientData {
        rs             = &rs,
        allocator      = rs_arena_alloc,
        arena_alloc    = arena_alloc,
        isz            = ccdg.int_sizes_from_platform(plat),
        included_types = &included_types,
        macros         = &macros,
        anon_idx       = &anon_idx,
    }
    index := clang.createIndex(0, 0)
    defer clang.disposeIndex(index)
    units := make([dynamic]clang.CXTranslationUnit, arena_alloc)
    defer for unit in units {
        clang.disposeTranslationUnit(unit)
    }


    for header in headers {
        header_cstr := strings.clone_to_cstring(header, arena_alloc)

        unit := clang.parseTranslationUnit(
            index,
            header_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            u32(
                clang.CXTranslationUnit_Flags.CXTranslationUnit_DetailedPreprocessingRecord |
                clang.CXTranslationUnit_Flags.CXTranslationUnit_SkipFunctionBodies,
            ),
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
                case .CXDiagnostic_Error:
                    fmt.eprint("ERROR: ")
                case .CXDiagnostic_Fatal:
                    fmt.eprint("FATAL: ")
                case .CXDiagnostic_Warning:
                    fmt.eprint("WARNING: ")
                case .CXDiagnostic_Note:
                    fmt.eprint("NOTE: ")
                case .CXDiagnostic_Ignored:
                    fmt.eprint("IGNORED: ")
                }

                fmt.eprintln(dig_str)
            }
        }

        rs.constants = om.make(
            string,
            runic.Constant,
            allocator = rs_arena_alloc,
        )
        rs.symbols = om.make(string, runic.Symbol, allocator = rs_arena_alloc)
        rs.types = om.make(string, runic.Type, allocator = rs_arena_alloc)

        cursor := clang.getTranslationUnitCursor(unit)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.CXCursor,
                client_data: clang.CXClientData,
            ) -> clang.CXChildVisitResult {
                data := cast(^ClientData)client_data
                context = runtime.default_context()
                rs_arena_alloc := data.allocator

                cursor_kind := clang.getCursorKind(cursor)
                cursor_type := clang.getCursorType(cursor)
                cursor_location := clang.getCursorLocation(cursor)
                display_name := clang.getCursorDisplayName(cursor)
                storage_class := clang.Cursor_getStorageClass(cursor)

                defer clang.disposeString(display_name)

                if clang.Location_isFromMainFile(cursor_location) == 0 {
                    #partial switch cursor_kind {
                    case .CXCursor_TypedefDecl:
                        typedef := clang.getTypedefDeclUnderlyingType(cursor)

                        type_name := clang.getTypedefName(cursor_type)
                        defer clang.disposeString(type_name)

                        data.included_types[strings.clone_from_cstring(clang.getCString(type_name), data.arena_alloc)] =
                            typedef
                    case .CXCursor_StructDecl:
                        if struct_is_unnamed(display_name) do break

                        data.included_types[strings.clone_from_cstring(clang.getCString(display_name), data.arena_alloc)] =
                            cursor_type
                    case .CXCursor_EnumDecl:
                        if enum_is_unnamed(display_name) do break

                        data.included_types[strings.clone_from_cstring(clang.getCString(display_name), data.arena_alloc)] =
                            cursor_type
                    case .CXCursor_UnionDecl:
                        if union_is_unnamed(display_name) do break

                        data.included_types[strings.clone_from_cstring(clang.getCString(display_name), data.arena_alloc)] =
                            cursor_type
                    }

                    return .CXChildVisit_Continue
                }

                #partial switch cursor_kind {
                case .CXCursor_TypedefDecl:
                    typedef := clang.getTypedefDeclUnderlyingType(cursor)

                    type_name := clang.getTypedefName(cursor_type)
                    defer clang.disposeString(type_name)

                    if typedef.kind == .CXType_Elaborated {
                        named_type := clang.Type_getNamedType(typedef)
                        named_cursor := clang.getTypeDeclaration(named_type)

                        named_name := clang.getCursorDisplayName(named_cursor)
                        defer clang.disposeString(named_name)

                        if !(struct_is_unnamed(named_name) ||
                               enum_is_unnamed(named_name) ||
                               union_is_unnamed(named_name)) {
                            if clang.getCString(named_name) !=
                               clang.getCString(type_name) {
                                spec := handle_builtin_int(
                                    named_name,
                                    data.isz,
                                    rs_arena_alloc,
                                )
                                type := runic.Type {
                                    spec = spec,
                                }

                                om.insert(
                                    &data.rs.types,
                                    strings.clone_from_cstring(
                                        clang.getCString(type_name),
                                        rs_arena_alloc,
                                    ),
                                    type,
                                )
                            }
                        } else {
                            type: runic.Type = ---
                            types: om.OrderedMap(string, runic.Type) = ---
                            type, types, data.err = clang_type_to_runic_type(
                                named_type,
                                named_cursor,
                                data.isz,
                                data.anon_idx,
                                rs_arena_alloc,
                            )

                            om.extend(&data.rs.types, types)
                            om.delete(types)

                            if data.err != nil {
                                fmt.eprintln(data.err, "\n")
                                data.err = nil
                                return .CXChildVisit_Continue
                            }

                            om.insert(
                                &data.rs.types,
                                strings.clone_from_cstring(
                                    clang.getCString(type_name),
                                    rs_arena_alloc,
                                ),
                                type,
                            )
                        }

                        break
                    }

                    type: runic.Type = ---
                    types: om.OrderedMap(string, runic.Type) = ---
                    type, types, data.err = clang_type_to_runic_type(
                        typedef,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        rs_arena_alloc,
                    )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    om.insert(
                        &data.rs.types,
                        strings.clone_from_cstring(
                            clang.getCString(type_name),
                            rs_arena_alloc,
                        ),
                        type,
                    )
                case .CXCursor_VarDecl:
                    switch storage_class {
                    case .CX_SC_Invalid,
                         .CX_SC_Static,
                         .CX_SC_OpenCLWorkGroupLocal,
                         .CX_SC_PrivateExtern:
                        return .CXChildVisit_Continue
                    case .CX_SC_Auto,
                         .CX_SC_None,
                         .CX_SC_Register,
                         .CX_SC_Extern:
                    }

                    if cursor_type.kind == .CXType_Elaborated {
                        named_type := clang.Type_getNamedType(cursor_type)
                        named_cursor := clang.getTypeDeclaration(named_type)

                        named_name := clang.getCursorDisplayName(named_cursor)
                        defer clang.disposeString(named_name)

                        if struct_is_unnamed(named_name) ||
                           enum_is_unnamed(named_name) ||
                           union_is_unnamed(named_name) {
                            type: runic.Type = ---
                            types: om.OrderedMap(string, runic.Type) = ---
                            type, types, data.err = clang_type_to_runic_type(
                                named_type,
                                named_cursor,
                                data.isz,
                                data.anon_idx,
                                rs_arena_alloc,
                            )

                            om.extend(&data.rs.types, types)
                            om.delete(types)

                            if data.err != nil {
                                fmt.eprintln(data.err, "\n")
                                data.err = nil
                                return .CXChildVisit_Continue
                            }

                            var_name := strings.clone_from_cstring(
                                clang.getCString(display_name),
                                rs_arena_alloc,
                            )

                            handle_anon_type(
                                &type,
                                &data.rs.types,
                                data.anon_idx,
                                var_name,
                                rs_arena_alloc,
                            )

                            om.insert(
                                &data.rs.symbols,
                                var_name,
                                runic.Symbol{value = type},
                            )
                            break
                        }
                    }

                    type: runic.Type = ---
                    types: om.OrderedMap(string, runic.Type) = ---
                    type, types, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        rs_arena_alloc,
                    )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    var_name := strings.clone_from_cstring(
                        clang.getCString(display_name),
                        rs_arena_alloc,
                    )

                    om.insert(
                        &data.rs.symbols,
                        var_name,
                        runic.Symbol{value = type},
                    )
                case .CXCursor_StructDecl:
                    if struct_is_unnamed(display_name) do return .CXChildVisit_Continue

                    type: runic.Type = ---
                    types: om.OrderedMap(string, runic.Type) = ---
                    type, types, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        rs_arena_alloc,
                    )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    if len(type.spec.(runic.Struct).members) == 0 {
                        break
                    }

                    om.insert(
                        &data.rs.types,
                        strings.clone_from_cstring(
                            clang.getCString(display_name),
                            rs_arena_alloc,
                        ),
                        type,
                    )
                case .CXCursor_EnumDecl:
                    if enum_is_unnamed(display_name) do return .CXChildVisit_Continue

                    type: runic.Type = ---
                    types: om.OrderedMap(string, runic.Type) = ---
                    type, types, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        rs_arena_alloc,
                    )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    om.insert(
                        &data.rs.types,
                        strings.clone_from_cstring(
                            clang.getCString(display_name),
                            rs_arena_alloc,
                        ),
                        type,
                    )
                case .CXCursor_UnionDecl:
                    if union_is_unnamed(display_name) do return .CXChildVisit_Continue

                    type: runic.Type = ---
                    types: om.OrderedMap(string, runic.Type) = ---
                    type, types, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        data.anon_idx,
                        rs_arena_alloc,
                    )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    union_name := strings.clone_from_cstring(
                        clang.getCString(display_name),
                        rs_arena_alloc,
                    )

                    om.insert(&data.rs.types, union_name, type)
                case .CXCursor_FunctionDecl:
                    // NOTE: defining structs, unions and enums with a name inside the parameter list is not supported
                    switch storage_class {
                    case .CX_SC_Invalid,
                         .CX_SC_Static,
                         .CX_SC_OpenCLWorkGroupLocal,
                         .CX_SC_PrivateExtern:
                        return .CXChildVisit_Continue
                    case .CX_SC_Auto,
                         .CX_SC_None,
                         .CX_SC_Register,
                         .CX_SC_Extern:
                    }
                    if clang.Cursor_isFunctionInlined(cursor) != 0 do return .CXChildVisit_Continue

                    cursor_return_type := clang.getCursorResultType(cursor)
                    num_params := clang.Cursor_getNumArguments(cursor)

                    func: runic.Function

                    func_name := clang.getCursorSpelling(cursor)
                    defer clang.disposeString(func_name)

                    if cursor_return_type.kind == .CXType_Elaborated {
                        named_type := clang.Type_getNamedType(
                            cursor_return_type,
                        )
                        named_cursor := clang.getTypeDeclaration(named_type)

                        named_name := clang.getCursorDisplayName(named_cursor)
                        defer clang.disposeString(named_name)

                        if struct_is_unnamed(named_name) ||
                           enum_is_unnamed(named_name) ||
                           union_is_unnamed(named_name) {

                            type: runic.Type = ---
                            elab_types: om.OrderedMap(string, runic.Type) = ---
                            type, elab_types, data.err =
                                clang_type_to_runic_type(
                                    named_type,
                                    named_cursor,
                                    data.isz,
                                    data.anon_idx,
                                    rs_arena_alloc,
                                )

                            om.extend(&data.rs.types, elab_types)
                            om.delete(elab_types)

                            if data.err != nil {
                                fmt.eprintln(data.err, "\n")
                                data.err = nil
                                return .CXChildVisit_Continue
                            }

                            func_name_str := strings.string_from_ptr(
                                cast([^]byte)clang.getCString(func_name),
                                len(clang.getCString(func_name)),
                            )

                            handle_anon_type(
                                &type,
                                &data.rs.types,
                                data.anon_idx,
                                func_name_str,
                                rs_arena_alloc,
                            )

                            func.return_type = type
                        }
                    }

                    types: om.OrderedMap(string, runic.Type) = ---
                    func.return_type, types, data.err =
                        clang_type_to_runic_type(
                            cursor_return_type,
                            cursor,
                            data.isz,
                            data.anon_idx,
                            rs_arena_alloc,
                        )

                    om.extend(&data.rs.types, types)
                    om.delete(types)

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

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
                        param_name := clang.getCursorSpelling(param_cursor)

                        defer clang.disposeString(param_name)

                        param_name_str := strings.clone_from_cstring(
                            clang.getCString(param_name),
                            rs_arena_alloc,
                        )
                        if param_name_str == "" {
                            param_name_str = fmt.aprintf(
                                "param{}",
                                idx,
                                allocator = rs_arena_alloc,
                            )
                        }

                        if param_type.kind == .CXType_Elaborated {
                            named_type := clang.Type_getNamedType(param_type)
                            named_cursor := clang.getTypeDeclaration(
                                named_type,
                            )

                            named_name := clang.getCursorDisplayName(
                                named_cursor,
                            )
                            defer clang.disposeString(named_name)

                            if struct_is_unnamed(named_name) ||
                               enum_is_unnamed(named_name) ||
                               union_is_unnamed(named_name) {

                                type: runic.Type = ---
                                elab_types: om.OrderedMap(
                                    string,
                                    runic.Type,
                                ) = ---
                                type, elab_types, data.err =
                                    clang_type_to_runic_type(
                                        named_type,
                                        named_cursor,
                                        data.isz,
                                        data.anon_idx,
                                        rs_arena_alloc,
                                    )

                                om.extend(&data.rs.types, elab_types)
                                om.delete(elab_types)

                                if data.err != nil {
                                    fmt.eprintln(data.err, "\n")
                                    data.err = nil
                                    return .CXChildVisit_Continue
                                }

                                handle_anon_type(
                                    &type,
                                    &data.rs.types,
                                    data.anon_idx,
                                    param_name_str,
                                    rs_arena_alloc,
                                )

                                append(
                                    &func.parameters,
                                    runic.Member {
                                        name = param_name_str,
                                        type = type,
                                    },
                                )

                                continue
                            }
                        }

                        type: runic.Type = ---
                        type, types, data.err = clang_type_to_runic_type(
                            param_type,
                            param_cursor,
                            data.isz,
                            data.anon_idx,
                            rs_arena_alloc,
                        )

                        om.extend(&data.rs.types, types)
                        om.delete(types)

                        if data.err != nil {
                            fmt.eprintln(data.err, "\n")
                            data.err = nil
                            return .CXChildVisit_Continue
                        }

                        append(
                            &func.parameters,
                            runic.Member{name = param_name_str, type = type},
                        )
                    }

                    om.insert(
                        &data.rs.symbols,
                        strings.clone_from_cstring(
                            clang.getCString(func_name),
                            rs_arena_alloc,
                        ),
                        runic.Symbol{value = func},
                    )
                case .CXCursor_MacroDefinition:
                    cursor_extent := clang.getCursorExtent(cursor)
                    cursor_start := clang.getRangeStart(cursor_extent)
                    cursor_end := clang.getRangeEnd(cursor_extent)

                    start_offset, end_offset: u32 = ---, ---
                    file: clang.CXFile = ---
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

                    buffer_size: clang.size_t = ---
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
                case .CXCursor_MacroExpansion, .CXCursor_InclusionDirective:
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

                return .CXChildVisit_Continue
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

            if included_type.kind == .CXType_Elaborated {
                named_type := clang.Type_getNamedType(included_type)
                named_cursor := clang.getTypeDeclaration(named_type)

                named_name := clang.getCursorDisplayName(named_cursor)
                defer clang.disposeString(named_name)

                type: runic.Type = ---
                types: om.OrderedMap(string, runic.Type) = ---
                type, types, data.err = clang_type_to_runic_type(
                    named_type,
                    named_cursor,
                    data.isz,
                    data.anon_idx,
                    rs_arena_alloc,
                )

                for &entry in types.data {
                    t := &entry.value
                    unknowns := check_for_unknown_types(t, data.rs.types)
                    extend_unknown_types(&unknown_types, unknowns)
                }

                om.extend(&rs.types, types)
                om.delete(types)

                if data.err != nil {
                    fmt.eprintln(data.err, "\n")
                    data.err = nil
                    continue
                }

                unknowns := check_for_unknown_types(&type, data.rs.types)
                extend_unknown_types(&unknown_types, unknowns)

                om.insert(&data.rs.types, unknown, type)
                continue
            }

            type: runic.Type = ---
            types: om.OrderedMap(string, runic.Type) = ---
            type, types, data.err = clang_type_to_runic_type(
                included_type,
                cursor,
                data.isz,
                data.anon_idx,
                rs_arena_alloc,
            )

            for &entry in types.data {
                t := &entry.value
                unknowns := check_for_unknown_types(t, data.rs.types)
                extend_unknown_types(&unknown_types, unknowns)
            }

            om.extend(&data.rs.types, types)
            om.delete(types)

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
            u32(
                clang.CXTranslationUnit_Flags.CXTranslationUnit_SkipFunctionBodies |
                clang.CXTranslationUnit_Flags.CXTranslationUnit_SingleFileParse,
            ),
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
                cursor, parent: clang.CXCursor,
                client_data: clang.CXClientData,
            ) -> clang.CXChildVisitResult {
                data := cast(^ClientData)client_data
                context = runtime.default_context()

                cursor_kind := clang.getCursorKind(cursor)

                #partial switch cursor_kind {
                case .CXCursor_VarDecl:
                    var_name := clang.getCursorSpelling(cursor)
                    defer clang.disposeString(var_name)

                    var_name_str := strings.clone_from_cstring(
                        clang.getCString(var_name),
                        data.allocator,
                    )

                    start: int = ---
                    for r, idx in var_name_str {
                        if r == 'R' {
                            start = idx
                            break
                        }
                    }
                    start += 1

                    var_name_str = var_name_str[start:]

                    om.insert(
                        &data.rs.constants,
                        var_name_str,
                        runic.Constant{},
                    )
                case .CXCursor_StringLiteral:
                    const_value := clang.getCursorSpelling(cursor)
                    defer clang.disposeString(const_value)

                    const_str := strings.string_from_ptr(
                        cast(^byte)clang.getCString(const_value),
                        len(clang.getCString(const_value)),
                    )
                    const_str = const_str[1:len(const_str) - 1]

                    entry := &data.rs.constants.data[len(data.rs.constants.data) - 1]
                    const := &entry.value
                    const.type.spec = runic.Builtin.Untyped

                    if strings.has_prefix(const_str, "\"") &&
                       strings.has_suffix(const_str, "\"") {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_str, "\""),
                                "\"",
                            ),
                            data.allocator,
                        )
                        const.type.spec = runic.Builtin.String
                    } else if strings.has_prefix(const_str, "'") &&
                       strings.has_suffix(const_str, "'") &&
                       len(const_str) == 3 {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_str, "'"),
                                "'",
                            ),
                            data.allocator,
                        )
                        const.type.spec = runic.Builtin.SInt8
                    } else if value_i64, ok_i64 := strconv.parse_i64(
                        const_str,
                    ); ok_i64 {
                        const.value = value_i64
                    } else if value_f64, ok_f64 := strconv.parse_f64(
                        const_str,
                    ); ok_f64 {
                        const.value = value_f64
                    } else {
                        name := entry.key

                        for &sym_entry in data.rs.symbols.data {
                            sym_name, sym := sym_entry.key, &sym_entry.value
                            if const_str == sym_name {
                                append(&sym.aliases, name)
                                om.delete_key(&data.rs.constants, name)
                                return .CXChildVisit_Recurse
                            }
                        }

                        for type_entry in data.rs.types.data {
                            type_name := type_entry.key

                            if const_str == type_name {
                                om.insert(
                                    &data.rs.types,
                                    name,
                                    runic.Type{spec = type_name},
                                )
                                om.delete_key(&data.rs.constants, name)
                                return .CXChildVisit_Recurse
                            }
                        }

                        const.value = strings.clone(const_str, data.allocator)
                    }
                }

                return .CXChildVisit_Recurse
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
