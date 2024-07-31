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
import "core:strings"
import ccdg "root:c/codegen"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
ClientData :: struct {
    rs:             ^runic.Runestone,
    allocator:      runtime.Allocator,
    arena_alloc:    runtime.Allocator,
    err:            errors.Error,
    isz:            ccdg.Int_Sizes,
    included_types: ^map[string]clang.CXType,
}

@(private = "file")
RecordData :: struct {
    members:   ^[dynamic]runic.Member,
    allocator: runtime.Allocator,
    err:       errors.Error,
    isz:       ccdg.Int_Sizes,
    types:     ^om.OrderedMap(string, runic.Type),
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

    headers := runic.platform_value_get([]string, rf.headers, plat)
    /*overwrite := runic.platform_value_get(
        runic.OverwriteSet,
        rf.overwrite,
        plat,
    )
    ignore := runic.platform_value_get(runic.IgnoreSet, rf.ignore, plat)*/

    included_types := make(map[string]clang.CXType, allocator = arena_alloc)
    data := ClientData {
        rs             = &rs,
        allocator      = rs_arena_alloc,
        arena_alloc    = arena_alloc,
        isz            = ccdg.int_sizes_from_platform(plat),
        included_types = &included_types,
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
            u32(clang.CXTranslationUnit_Flags.CXTranslationUnit_None),
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
            err_msg: strings.Builder
            strings.builder_init(&err_msg, errors.error_allocator)

            for idx in 0 ..< num_diag {
                dig := clang.getDiagnostic(unit, idx)
                defer clang.disposeDiagnostic(dig)

                sev := clang.getDiagnosticSeverity(dig)

                #partial switch sev {
                case .CXDiagnostic_Error, .CXDiagnostic_Fatal:
                    dig_msg := clang.formatDiagnostic(
                        dig,
                        clang.defaultDiagnosticDisplayOptions(),
                    )
                    defer clang.disposeString(dig_msg)

                    dig_str := strings.clone_from_cstring(
                        clang.getCString(dig_msg),
                        arena_alloc,
                    )

                    strings.write_string(&err_msg, dig_str)
                    strings.write_rune(&err_msg, '\n')
                }
            }

            if strings.builder_len(err_msg) != 0 {
                err = errors.message(
                    "\"{}\": {}",
                    header,
                    strings.to_string(err_msg),
                )
                return
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

                // TODO: handle unknown types
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

                // TODO: correctly handle elaborated types
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
                                type := runic.Type {
                                    spec = strings.clone_from_cstring(
                                        clang.getCString(named_name),
                                        rs_arena_alloc,
                                    ),
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
                                &data.rs.symbols,
                                strings.clone_from_cstring(
                                    clang.getCString(display_name),
                                    rs_arena_alloc,
                                ),
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
                        &data.rs.symbols,
                        strings.clone_from_cstring(
                            clang.getCString(display_name),
                            rs_arena_alloc,
                        ),
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
                case:
                    fmt.eprintfln("Other Cursor Type: {}", cursor_kind)
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

    // TODO: duplicate unknowns
    // Look for unknown types
    unknown_types := make([dynamic]string, arena_alloc)
    for &entry in rs.types.data {
        type := &entry.value
        unknowns := check_for_unknown_types(type, rs.types)

        for u in unknowns {
            append(&unknown_types, u)
        }
        delete(unknowns)
    }

    for &entry in rs.symbols.data {
        sym := &entry.value

        switch &value in sym.value {
        case runic.Function:
            unknowns := check_for_unknown_types(&value.return_type, rs.types)
            for u in unknowns {
                append(&unknown_types, u)
            }
            delete(unknowns)

            for &param in value.parameters {
                unknowns = check_for_unknown_types(&param.type, rs.types)
                for u in unknowns {
                    append(&unknown_types, u)
                }
                delete(unknowns)
            }
        case runic.Type:
            unknowns := check_for_unknown_types(&value, rs.types)

            for u in unknowns {
                append(&unknown_types, u)
            }
            delete(unknowns)
        }
    }

    // Look for unknown types in includes
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
                    rs_arena_alloc,
                )

                // TODO: handle unknown of these types

                om.extend(&rs.types, types)
                om.delete(types)

                if data.err != nil {
                    fmt.eprintln(data.err, "\n")
                    data.err = nil
                    continue
                }

                om.insert(&data.rs.types, unknown, type)
                continue
            }

            type: runic.Type = ---
            types: om.OrderedMap(string, runic.Type) = ---
            type, types, data.err = clang_type_to_runic_type(
                included_type,
                cursor,
                data.isz,
                rs_arena_alloc,
            )

            // TODO: handle unknowns

            om.extend(&data.rs.types, types)
            om.delete(types)

            if data.err != nil {
                fmt.eprintln(data.err, "\n")
                data.err = nil
                continue
            }

            // TODO: Insert unknowns at the top
            om.insert(&data.rs.types, unknown, type)
        }
    }

    // Validate unknown types
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

    return
}

struct_is_unnamed :: proc(display_name: clang.CXString) -> bool {
    str := strings.clone_from_cstring(clang.getCString(display_name))
    defer delete(str)

    return str == "" || strings.has_prefix(str, "struct (unnamed")
}

enum_is_unnamed :: proc(display_name: clang.CXString) -> bool {
    str := strings.clone_from_cstring(clang.getCString(display_name))
    defer delete(str)

    return str == "" || strings.has_prefix(str, "enum (unnamed")
}

union_is_unnamed :: proc(display_name: clang.CXString) -> bool {
    str := strings.clone_from_cstring(clang.getCString(display_name))
    defer delete(str)

    return str == "" || strings.has_prefix(str, "union (unnamed")
}

clang_type_to_runic_type :: proc(
    type: clang.CXType,
    cursor: clang.CXCursor,
    isz: ccdg.Int_Sizes,
    allocator := context.allocator,
) -> (
    tp: runic.Type,
    types: om.OrderedMap(string, runic.Type),
    err: errors.Error,
) {
    #partial switch type.kind {
    case .CXType_Void:
        tp.spec = runic.Builtin.Void
    case .CXType_Bool:
        tp.spec = ccdg.bool_type(isz._Bool)
    case .CXType_Char_U:
        tp.spec = ccdg.int_type(isz.char, false)
    case .CXType_UChar:
        tp.spec = ccdg.int_type(isz.char, false)
    case .CXType_Char16:
        tp.spec = runic.Builtin.SInt16
    case .CXType_Char32:
        tp.spec = runic.Builtin.SInt32
    case .CXType_UShort:
        tp.spec = ccdg.int_type(isz.short, false)
    case .CXType_UInt:
        tp.spec = ccdg.int_type(isz.Int, false)
    case .CXType_ULong:
        tp.spec = ccdg.int_type(isz.long, false)
    case .CXType_ULongLong:
        tp.spec = ccdg.int_type(isz.longlong, false)
    case .CXType_UInt128:
        tp.spec = runic.Builtin.SInt128
    case .CXType_Char_S:
        tp.spec = ccdg.int_type(isz.char, true)
    case .CXType_SChar:
        tp.spec = ccdg.int_type(isz.char, true)
    case .CXType_WChar:
        // TODO: find out about wchar_t
        tp.spec = runic.Builtin.UInt32
    case .CXType_Short:
        tp.spec = ccdg.int_type(isz.short, true)
    case .CXType_Int:
        tp.spec = ccdg.int_type(isz.Int, true)
    case .CXType_Long:
        tp.spec = ccdg.int_type(isz.long, true)
    case .CXType_LongLong:
        tp.spec = ccdg.int_type(isz.longlong, true)
    case .CXType_Int128:
        tp.spec = runic.Builtin.SInt128
    case .CXType_Float:
        tp.spec = ccdg.float_type(isz.float)
    case .CXType_Double:
        tp.spec = ccdg.float_type(isz.double)
    case .CXType_LongDouble:
        tp.spec = ccdg.float_type(isz.long_double)
    case .CXType_Float128:
        tp.spec = runic.Builtin.Float128
    case .CXType_Elaborated:
        named_type := clang.Type_getNamedType(type)
        named_cursor := clang.getTypeDeclaration(named_type)

        named_name := clang.getCursorDisplayName(named_cursor)
        defer clang.disposeString(named_name)

        tp.spec = strings.clone_from_cstring(
            clang.getCString(named_name),
            allocator,
        )
    case .CXType_Pointer:
        pointee := clang.getPointeeType(type)
        tp, types = clang_type_to_runic_type(pointee, cursor, isz) or_return

        if pointee.kind == .CXType_Void {
            tp.spec = runic.Builtin.RawPtr
        } else {
            // NOTE: Not Sure
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.count += 1
            } else {
                tp.pointer_info.count += 1
            }
        }

        if clang.isConstQualifiedType(pointee) != 0 {
            // NOTE: Not Sure
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.read_only =
                    true
            } else {
                tp.pointer_info.read_only = true
            }
        }
    case .CXType_ConstantArray:
        arr_type := clang.getArrayElementType(type)
        tp, types = clang_type_to_runic_type(
            arr_type,
            cursor,
            isz,
            allocator,
        ) or_return

        // NOTE: Probably dangerous, because it uses the values and sizes from the host platform
        arr_size := clang.getArraySize(type)

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, allocator)
        }

        append(&tp.array_info, runic.Array{})
        for i := len(tp.array_info) - 1; i > 0; i -= 1 {
            tp.array_info[i] = tp.array_info[i - 1]
        }
        tp.array_info[0] = runic.Array {
            size = u64(arr_size),
        }
    case .CXType_IncompleteArray:
        arr_type := clang.getArrayElementType(type)
        tp, types = clang_type_to_runic_type(
            arr_type,
            cursor,
            isz,
            allocator,
        ) or_return

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, allocator)
        }

        append(&tp.array_info, runic.Array{})
        for i := len(tp.array_info) - 1; i > 0; i -= 1 {
            tp.array_info[i] = tp.array_info[i - 1]
        }
        tp.array_info[0] = runic.Array {
            size = nil,
        }
    case .CXType_Typedef:
        type_name := clang.getTypedefName(type)
        defer clang.disposeString(type_name)

        tp.spec = strings.clone_from_cstring(
            clang.getCString(type_name),
            allocator,
        )
    case .CXType_Record:
        cursor_kind := clang.getCursorKind(cursor)

        members := make([dynamic]runic.Member, allocator)
        types = om.make(string, runic.Type)

        data := RecordData {
            members   = &members,
            allocator = allocator,
            isz       = isz,
            types     = &types,
        }

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.CXCursor,
                client_data: clang.CXClientData,
            ) -> clang.CXChildVisitResult {
                data := cast(^RecordData)client_data
                context = runtime.default_context()

                cursor_type := clang.getCursorType(cursor)
                cursor_kind := clang.getCursorKind(cursor)
                display_name := clang.getCursorDisplayName(cursor)

                defer clang.disposeString(display_name)

                if (cursor_type.kind == .CXType_Record &&
                       (struct_is_unnamed(display_name) ||
                               union_is_unnamed(display_name))) ||
                   (cursor_type.kind == .CXType_Enum &&
                           enum_is_unnamed(display_name)) {
                    return .CXChildVisit_Continue
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
                        elab_types: om.OrderedMap(string, runic.Type) = ---
                        type, elab_types, data.err = clang_type_to_runic_type(
                            named_type,
                            named_cursor,
                            data.isz,
                            data.allocator,
                        )

                        om.extend(data.types, elab_types)
                        om.delete(elab_types)

                        if data.err != nil {
                            return .CXChildVisit_Break
                        }

                        append(
                            data.members,
                            runic.Member {
                                name = strings.clone_from_cstring(
                                    clang.getCString(display_name),
                                    data.allocator,
                                ),
                                type = type,
                            },
                        )

                        return .CXChildVisit_Continue
                    }
                }

                type: runic.Type = ---
                elab_types: om.OrderedMap(string, runic.Type) = ---
                type, elab_types, data.err = clang_type_to_runic_type(
                    cursor_type,
                    cursor,
                    data.isz,
                    data.allocator,
                )

                om.extend(data.types, elab_types)
                om.delete(elab_types)

                if data.err != nil {
                    return .CXChildVisit_Break
                }

                type_name := strings.clone_from_cstring(
                    clang.getCString(display_name),
                    data.allocator,
                )

                #partial switch cursor_kind {
                case .CXCursor_FieldDecl:
                    append(
                        data.members,
                        runic.Member{name = type_name, type = type},
                    )
                case:
                    om.insert(data.types, type_name, type)
                }

                return .CXChildVisit_Continue
            },
            &data,
        )

        err = data.err

        #partial switch cursor_kind {
        case .CXCursor_StructDecl:
            tp.spec = runic.Struct{members}
        case .CXCursor_UnionDecl:
            tp.spec = runic.Union{members}
        }
    case .CXType_Enum:
        e: runic.Enum
        // TODO: get correct enum type
        e.type = .SInt32
        e.entries = make([dynamic]runic.EnumEntry, allocator)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.CXCursor,
                client_data: clang.CXClientData,
            ) -> clang.CXChildVisitResult {
                e := cast(^runic.Enum)client_data
                context = runtime.default_context()
                rs_arena_alloc := e.entries.allocator

                display_name := clang.getCursorDisplayName(cursor)

                defer clang.disposeString(display_name)

                value := clang.getEnumConstantDeclValue(cursor)

                append(
                    &e.entries,
                    runic.EnumEntry {
                        name = strings.clone_from_cstring(
                            clang.getCString(display_name),
                            rs_arena_alloc,
                        ),
                        value = i64(value),
                    },
                )

                return .CXChildVisit_Continue
            },
            &e,
        )

        tp.spec = e
    case:
        type_spell := clang.getTypeKindSpelling(type.kind)
        defer clang.disposeString(type_spell)

        err = clang_source_error(
            cursor,
            "unsupported type \"{}\"",
            clang.getCString(type_spell),
        )
        return
    }

    if clang.isConstQualifiedType(type) != 0 {
        if len(tp.array_info) != 0 {
            tp.array_info[len(tp.array_info) - 1].read_only = true
        }
        tp.read_only = true
    }

    if b, ok := tp.spec.(runic.Builtin); ok && b == .SInt8 {
        if tp.pointer_info.count != 0 {
            tp.spec = runic.Builtin.String
            tp.pointer_info.count -= 1
        }
    }

    return
}

clang_source_error :: proc(
    cursor: clang.CXCursor,
    msg: string,
    args: ..any,
    loc := #caller_location,
) -> errors.Error {
    cursor_loc := clang.getCursorLocation(cursor)

    line, column, offset: u32 = ---, ---, ---
    file: clang.CXFile = ---

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

check_for_unknown_types :: proc(
    type: ^runic.Type,
    types: om.OrderedMap(string, runic.Type),
) -> (
    unknowns: [dynamic]string,
) {
    #partial switch &t in type.spec {
    case string:
        if !om.contains(types, t) {
            append(&unknowns, t)
            type.spec = runic.Unknown(t)
        }
    case runic.Struct:
        for &member in t.members {
            u := check_for_unknown_types(&member.type, types)
            for x in u {
                append(&unknowns, x)
            }
            delete(u)
        }
    case runic.Union:
        for &member in t.members {
            u := check_for_unknown_types(&member.type, types)
            for x in u {
                append(&unknowns, x)
            }
            delete(u)
        }
    }

    return
}

validate_unknown_types :: proc(
    type: ^runic.Type,
    types: om.OrderedMap(string, runic.Type),
) {
    #partial switch &t in type.spec {
    case runic.Unknown:
        if om.contains(types, string(t)) {
            type.spec = string(t)
        }
    case runic.Struct:
        for &member in t.members {
            validate_unknown_types(&member.type, types)
        }
    case runic.Union:
        for &member in t.members {
            validate_unknown_types(&member.type, types)
        }
    }
}
