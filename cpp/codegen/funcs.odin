package cpp_codegen

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import ccdg "root:c/codegen"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
RecordData :: struct {
    members:   ^[dynamic]runic.Member,
    allocator: runtime.Allocator,
    err:       errors.Error,
    isz:       ccdg.Int_Sizes,
    types:     ^om.OrderedMap(string, runic.Type),
    anon_idx:  ^int,
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
    anon_idx: ^int,
    allocator := context.allocator,
    type_hint: Maybe(string) = nil,
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
    case .CXType_Short:
        tp.spec = ccdg.int_type(isz.short, true)
    case .CXType_Int:
        if th, ok := type_hint.?; ok && th != "int" {
            tp.spec = handle_builtin_int(th, isz, allocator)
        } else {
            tp.spec = ccdg.int_type(isz.Int, true)
        }
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

        tp.spec = handle_builtin_int(named_name, isz, allocator)
    case .CXType_Pointer:
        pointee := clang.getPointeeType(type)

        pointee_hint: Maybe(string)
        if type_hint != nil {
            pointee_hint = type_hint
        } else if pointee.kind == .CXType_Int {
            pointee_hint = clang_var_decl_get_type_hint(cursor)
        }

        tp, types = clang_type_to_runic_type(
            pointee,
            cursor,
            isz,
            anon_idx,
            allocator,
            pointee_hint,
        ) or_return

        if _, ok := tp.spec.(runic.FunctionPointer); !ok {
            handle_anon_type(&tp, &types, anon_idx, "pointer", allocator)
        }

        if pointee.kind == .CXType_Void {
            tp.spec = runic.Builtin.RawPtr
        } else if pointee.kind == .CXType_Char_S ||
           pointee.kind == .CXType_SChar {
            tp.spec = runic.Builtin.String
        } else {
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.count += 1
            } else if pointee.kind != .CXType_FunctionProto &&
               pointee.kind != .CXType_FunctionNoProto {
                tp.pointer_info.count += 1
            }
        }

        if clang.isConstQualifiedType(pointee) != 0 {
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
            anon_idx,
            allocator,
            type_hint,
        ) or_return

        handle_anon_type(&tp, &types, anon_idx, "array", allocator)

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
            anon_idx,
            allocator,
            type_hint,
        ) or_return

        handle_anon_type(&tp, &types, anon_idx, "array", allocator)

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
        type_name := clang.getTypeSpelling(type)
        defer clang.disposeString(type_name)

        type_name_cstr := clang.getCString(type_name)
        type_name_str := strings.string_from_ptr(
            cast(^byte)type_name_cstr,
            len(type_name_cstr),
        )

        if space_idx := strings.last_index(type_name_str, " ");
           space_idx != -1 {
            type_name_str = type_name_str[space_idx + 1:]
        }

        tp.spec = handle_builtin_int(type_name_str, isz, allocator)
    case .CXType_Record:
        cursor_kind := clang.getCursorKind(cursor)

        members := make([dynamic]runic.Member, allocator)
        types = om.make(string, runic.Type)

        data := RecordData {
            members   = &members,
            allocator = allocator,
            isz       = isz,
            types     = &types,
            anon_idx  = anon_idx,
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

                field_size := clang.getFieldDeclBitWidth(cursor)

                if field_size != -1 {
                    parent_display_name := clang.getCursorDisplayName(parent)
                    defer clang.disposeString(parent_display_name)

                    data.err = errors.message(
                        "field \"{}.{}\" has specific bit width of {}",
                        clang.getCString(parent_display_name),
                        clang.getCString(display_name),
                        field_size,
                    )
                    return .CXChildVisit_Break
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
                            data.anon_idx,
                            data.allocator,
                        )

                        om.extend(data.types, elab_types)
                        om.delete(elab_types)

                        if data.err != nil {
                            return .CXChildVisit_Break
                        }

                        member_name := strings.clone_from_cstring(
                            clang.getCString(display_name),
                            data.allocator,
                        )

                        if len(member_name) == 0 {
                            member_name = fmt.aprintf(
                                "member{}",
                                len(data.members),
                            )
                        }

                        handle_anon_type(
                            &type,
                            data.types,
                            data.anon_idx,
                            member_name,
                            data.allocator,
                        )

                        append(
                            data.members,
                            runic.Member{name = member_name, type = type},
                        )

                        return .CXChildVisit_Continue
                    }
                }

                type_hint: Maybe(string)
                if cursor_type.kind == .CXType_Int {
                    type_hint = clang_var_decl_get_type_hint(cursor)
                }

                type: runic.Type = ---
                elab_types: om.OrderedMap(string, runic.Type) = ---
                type, elab_types, data.err = clang_type_to_runic_type(
                    cursor_type,
                    cursor,
                    data.isz,
                    data.anon_idx,
                    data.allocator,
                    type_hint,
                )

                om.extend(data.types, elab_types)
                om.delete(elab_types)

                if data.err != nil {
                    return .CXChildVisit_Break
                }

                member_name := strings.clone_from_cstring(
                    clang.getCString(display_name),
                    data.allocator,
                )

                if len(member_name) == 0 {
                    member_name = fmt.aprintf(
                        "member{}",
                        len(data.members),
                        allocator = data.allocator,
                    )
                }

                #partial switch cursor_kind {
                case .CXCursor_FieldDecl:
                    handle_anon_type(
                        &type,
                        data.types,
                        data.anon_idx,
                        member_name,
                        data.allocator,
                    )

                    append(
                        data.members,
                        runic.Member{name = member_name, type = type},
                    )
                case:
                    om.insert(data.types, member_name, type)
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

        if len(members) == 0 {
            display_name := clang.getCursorDisplayName(cursor)
            defer clang.disposeString(display_name)

            err = errors.message(
                "{} has no members",
                clang.getCString(display_name),
            )
        }
    case .CXType_Enum:
        e: runic.Enum

        enum_int_type := clang.getEnumDeclIntegerType(cursor)
        enum_type, _ := clang_type_to_runic_type(
            enum_int_type,
            clang.getTypeDeclaration(enum_int_type),
            isz,
            anon_idx,
            allocator,
        ) or_return

        // TODO: handle elaborated enum types
        #partial switch et in enum_type.spec {
        case runic.Builtin:
            e.type = et
        case:
            spel := clang.getTypeSpelling(enum_int_type)
            defer clang.disposeString(spel)

            err = errors.message(
                "invalid enum type: {}",
                clang.getCString(spel),
            )
            return
        }

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
    case .CXType_FunctionNoProto, .CXType_FunctionProto:
        types = om.make(string, runic.Type, allocator = allocator)
        elab_types: om.OrderedMap(string, runic.Type) = ---

        type_return_type := clang.getResultType(type)
        return_type_cursor := clang.getTypeDeclaration(type_return_type)
        num_params := clang.getNumArgTypes(type)

        func: runic.Function

        if type_return_type.kind == .CXType_Elaborated {
            named_type := clang.Type_getNamedType(type_return_type)
            named_cursor := clang.getTypeDeclaration(named_type)

            named_name := clang.getCursorDisplayName(named_cursor)
            defer clang.disposeString(named_name)

            if struct_is_unnamed(named_name) ||
               enum_is_unnamed(named_name) ||
               union_is_unnamed(named_name) {

                type: runic.Type = ---
                type, elab_types = clang_type_to_runic_type(
                    named_type,
                    named_cursor,
                    isz,
                    anon_idx,
                    allocator,
                ) or_return

                om.extend(&types, elab_types)
                om.delete(elab_types)

                func.return_type = type
            }
        }

        if func.return_type.spec == nil {
            func.return_type, elab_types = clang_type_to_runic_type(
                type_return_type,
                return_type_cursor,
                isz,
                anon_idx,
                allocator,
            ) or_return


            om.extend(&types, elab_types)
            om.delete(elab_types)
        }

        handle_anon_type(
            &func.return_type,
            &types,
            anon_idx,
            "func",
            allocator,
        )

        func.parameters = make([dynamic]runic.Member, allocator)
        func.variadic =
            num_params != 0 && clang.isFunctionTypeVariadic(type) != 0

        Func_Data :: struct {
            param_idx:  int,
            num_params: i32,
            func:       ^runic.Function,
            allocator:  runtime.Allocator,
            isz:        ccdg.Int_Sizes,
            anon_idx:   ^int,
            err:        errors.Error,
            types:      ^om.OrderedMap(string, runic.Type),
        }

        data := Func_Data {
            num_params = num_params,
            func       = &func,
            allocator  = allocator,
            isz        = isz,
            anon_idx   = anon_idx,
            types      = &types,
        }

        // NOTE: If the return type of the function pointer is unknown the children can not be visited
        clang.visitChildren(cursor, proc "c" (cursor, parent: clang.CXCursor, client_data: clang.CXClientData) -> clang.CXChildVisitResult {
                if clang.getCursorKind(cursor) != .CXCursor_ParmDecl do return .CXChildVisit_Continue

                data := cast(^Func_Data)client_data
                if data.param_idx == int(data.num_params) do return .CXChildVisit_Break
                defer data.param_idx += 1

                context = runtime.default_context()

                param_type := clang.getCursorType(cursor)
                display_name := clang.getCursorDisplayName(cursor)

                defer clang.disposeString(display_name)

                param_name_str := strings.clone_from_cstring(clang.getCString(display_name), data.allocator)
                if param_name_str == "" {
                    param_name_str = fmt.aprintf("param{}", data.param_idx, allocator = data.allocator)
                }

                elab_types: om.OrderedMap(string, runic.Type) = ---

                if param_type.kind == .CXType_Elaborated {
                    named_type := clang.Type_getNamedType(param_type)
                    named_cursor := clang.getTypeDeclaration(named_type)

                    named_name := clang.getCursorDisplayName(named_cursor)
                    defer clang.disposeString(named_name)

                    if struct_is_unnamed(named_name) || enum_is_unnamed(named_name) || union_is_unnamed(named_name) {

                        type: runic.Type = ---
                        type, elab_types, data.err = clang_type_to_runic_type(named_type, named_cursor, data.isz, data.anon_idx, data.allocator)

                        om.extend(data.types, elab_types)
                        om.delete(elab_types)

                        if data.err != nil {
                            return .CXChildVisit_Break
                        }

                        handle_anon_type(&type, data.types, data.anon_idx, param_name_str, data.allocator)

                        append(&data.func.parameters, runic.Member{name = param_name_str, type = type})
                        return .CXChildVisit_Continue
                    }
                }

                param_hint: Maybe(string)
                if param_type.kind == .CXType_Int {
                    param_hint = clang_var_decl_get_type_hint(cursor)
                }

                type: runic.Type = ---
                type, elab_types, data.err = clang_type_to_runic_type(param_type, cursor, data.isz, data.anon_idx, data.allocator, param_hint)

                handle_anon_type(&type, data.types, data.anon_idx, param_name_str, data.allocator)

                om.extend(data.types, elab_types)
                om.delete(elab_types)

                if data.err != nil {
                    return .CXChildVisit_Break
                }

                append(&data.func.parameters, runic.Member{name = param_name_str, type = type})

                return .CXChildVisit_Continue
            }, &data)

        if data.err != nil {
            err = data.err
            return
        }

        if len(func.parameters) != int(num_params) {
            err = clang_source_error(
                cursor,
                "could not find parameters num_params={}",
                num_params,
            )
            return
        }


        tp.spec = new_clone(func, allocator)
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
            extend_unknown_types(&unknowns, u)
        }
    case runic.Union:
        for &member in t.members {
            u := check_for_unknown_types(&member.type, types)
            extend_unknown_types(&unknowns, u)
        }
    case runic.FunctionPointer:
        u := check_for_unknown_types(&t.return_type, types)
        extend_unknown_types(&unknowns, u)
        for &param in t.parameters {
            u = check_for_unknown_types(&param.type, types)
            extend_unknown_types(&unknowns, u)
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

        os_err: os.Errno = ---
        file, os_err = os.open(
            strings.to_string(file_name),
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o777,
        )
        if os_err == 0 {
            file_path = strings.to_string(file_name)
            return
        }
    }

    err = errors.message("MAX_TRIES reached")
    return
}

extend_unknown_types :: #force_inline proc(
    unknown_types: ^[dynamic]string,
    unknowns: [dynamic]string,
) {
    for u in unknowns {
        if !slice.contains(unknown_types[:], u) {
            append(unknown_types, u)
        }
    }
    delete(unknowns)
}

handle_anon_type :: #force_inline proc(
    tp: ^runic.Type,
    types: ^om.OrderedMap(string, runic.Type),
    anon_idx: ^int,
    prefix: string = "",
    allocator := context.allocator,
) {
    type_name: string = ---

    #partial switch _ in tp.spec {
    case runic.Struct:
        type_name = fmt.aprintf(
            "{}_struct_anon_{}",
            prefix,
            anon_idx^,
            allocator = allocator,
        )
    case runic.Enum:
        type_name = fmt.aprintf(
            "{}_enum_anon_{}",
            prefix,
            anon_idx^,
            allocator = allocator,
        )
    case runic.Union:
        type_name = fmt.aprintf(
            "{}_union_anon_{}",
            prefix,
            anon_idx^,
            allocator = allocator,
        )
    case runic.FunctionPointer:
        type_name = fmt.aprintf(
            "{}_func_ptr_anon_{}",
            prefix,
            anon_idx^,
            allocator = allocator,
        )
    case:
        return
    }

    anon_idx^ += 1
    om.insert(types, type_name, runic.Type{spec = tp.spec})
    tp.spec = type_name
}

handle_builtin_int_cxstring :: proc(
    type_name: clang.CXString,
    isz: ccdg.Int_Sizes,
    allocator: runtime.Allocator,
) -> runic.TypeSpecifier {
    type_name_cstr := clang.getCString(type_name)
    type_name_str := strings.string_from_ptr(
        cast(^byte)type_name_cstr,
        len(type_name_cstr),
    )
    return handle_builtin_int_string(type_name_str, isz, allocator)
}

handle_builtin_int_string :: proc(
    type_name: string,
    isz: ccdg.Int_Sizes,
    allocator: runtime.Allocator,
) -> runic.TypeSpecifier {
    switch type_name {
    case "int8_t":
        return runic.Builtin.SInt8
    case "int16_t":
        return runic.Builtin.SInt16
    case "int32_t":
        return runic.Builtin.SInt32
    case "int64_t":
        return runic.Builtin.SInt64
    case "uint8_t":
        return runic.Builtin.UInt8
    case "uint16_t":
        return runic.Builtin.UInt16
    case "uint32_t":
        return runic.Builtin.UInt32
    case "uint64_t":
        return runic.Builtin.UInt64
    case "size_t":
        return ccdg.int_type(isz.size_t, false)
    case "intptr_t":
        return ccdg.int_type(isz.intptr_t, true)
    case "uintptr_t":
        return ccdg.int_type(isz.intptr_t, false)
    case "ptrdiff_t":
        return ccdg.int_type(isz.intptr_t, true)
    case:
        return strings.clone(type_name, allocator)
    }

    return runic.Builtin.Untyped
}

handle_builtin_int :: proc {
    handle_builtin_int_cxstring,
    handle_builtin_int_string,
}

clang_get_cursor_extent :: proc(cursor: clang.CXCursor) -> string {
    range := clang.getCursorExtent(cursor)

    start := clang.getRangeStart(range)
    end := clang.getRangeEnd(range)

    start_offset, end_offset: u32 = ---, ---
    file: clang.CXFile = ---
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

clang_typedef_get_type_hint :: proc(cursor: clang.CXCursor) -> Maybe(string) {
    extent := clang_get_cursor_extent(cursor)
    split := strings.split_multi(extent, {" ", "\n", "\r", "\t"})
    defer delete(split)

    if len(split) != 3 do return nil

    type_hint := strings.trim_right(split[1], "*")
    if strings.contains(type_hint, "*") do return nil

    return type_hint
}

clang_var_decl_get_type_hint :: proc(cursor: clang.CXCursor) -> Maybe(string) {
    extent := clang_get_cursor_extent(cursor)
    split := strings.split_multi(extent, {" ", "\n", "\r", "\t"})
    defer delete(split)

    if len(split) != 2 do return nil

    type_hint := strings.trim_right(split[0], "*")
    if strings.contains(type_hint, "*") do return nil

    return type_hint
}

clang_func_return_type_get_type_hint :: proc(
    cursor: clang.CXCursor,
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
