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
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private)
ClangToRunicTypeContext :: struct {
    int_sizes:     Int_Sizes,
    anon_index:    ^int,
    types:         ^om.OrderedMap(string, runic.Type),
    forward_decls: ^[dynamic]string,
    allocator:     runtime.Allocator,
}

@(private = "file")
RecordData :: struct {
    members:        ^[dynamic]runic.Member,
    members_failed: bool,
    ctx:            ^ClangToRunicTypeContext,
    err:            errors.Error,
}

@(private = "file")
FuncParamsData :: struct {
    param_idx:  int,
    num_params: i32,
    func:       ^runic.Function,
    ctx:        ^ClangToRunicTypeContext,
    err:        errors.Error,
}

@(private)
clang_type_to_runic_type :: proc(
    type: clang.Type,
    cursor: clang.Cursor,
    ctx: ^ClangToRunicTypeContext,
    type_hint: Maybe(string) = nil,
    name_hint: string = "TYPE_NAME_UNKNOWN",
) -> (
    tp: runic.Type,
    err: errors.Error,
) {
    #partial switch type.kind {
    case .Void:
        tp.spec = runic.Builtin.Untyped
    case .Bool:
        tp.spec = bool_type(ctx.int_sizes._Bool)
    case .Char_U:
        tp.spec = int_type(ctx.int_sizes.char, false)
    case .UChar:
        tp.spec = int_type(ctx.int_sizes.char, false)
    case .Char16:
        tp.spec = runic.Builtin.SInt16
    case .Char32:
        tp.spec = runic.Builtin.SInt32
    case .UShort:
        tp.spec = int_type(ctx.int_sizes.short, false)
    case .UInt:
        tp.spec = int_type(ctx.int_sizes.Int, false)
    case .ULong:
        tp.spec = int_type(ctx.int_sizes.long, false)
    case .ULongLong:
        tp.spec = int_type(ctx.int_sizes.longlong, false)
    case .UInt128:
        tp.spec = runic.Builtin.SInt128
    case .Char_S:
        tp.spec = int_type(ctx.int_sizes.char, true)
    case .SChar:
        tp.spec = int_type(ctx.int_sizes.char, true)
    case .Short:
        tp.spec = int_type(ctx.int_sizes.short, true)
    case .Int:
        if th, ok := type_hint.?;
           ok && th != "int" && th != "signed" && th != "signed int" {
            tp.spec = handle_builtin_int(th, ctx.int_sizes, ctx.allocator)
        } else {
            tp.spec = int_type(ctx.int_sizes.Int, true)
        }
    case .Long:
        tp.spec = int_type(ctx.int_sizes.long, true)
    case .LongLong:
        tp.spec = int_type(ctx.int_sizes.longlong, true)
    case .Int128:
        tp.spec = runic.Builtin.SInt128
    case .Float:
        tp.spec = float_type(ctx.int_sizes.float)
    case .Double:
        tp.spec = float_type(ctx.int_sizes.double)
    case .LongDouble:
        tp.spec = float_type(ctx.int_sizes.long_double)
    case .Float128:
        tp.spec = runic.Builtin.Float128
    case .Elaborated:
        named_type := clang.Type_getNamedType(type)
        named_cursor := clang.getTypeDeclaration(named_type)

        named_name := clang.getCursorDisplayName(named_cursor)
        defer clang.disposeString(named_name)

        // If a struct is declared inline it is also elaborated
        // This checks if such an unnamed struct, union or enum is encountered
        if struct_is_unnamed(named_name) ||
           enum_is_unnamed(named_name) ||
           union_is_unnamed(named_name) {
            tp = clang_type_to_runic_type(
                named_type,
                named_cursor,
                ctx,
                name_hint = name_hint,
            ) or_return
        } else {
            tp.spec = handle_builtin_int(
                named_name,
                ctx.int_sizes,
                ctx.allocator,
            )
        }
    case .Pointer:
        pointee := clang.getPointeeType(type)

        pointee_hint: Maybe(string)
        if type_hint != nil {
            pointee_hint = type_hint
        } else if pointee.kind == .Int {
            pointee_hint = clang_var_decl_get_type_hint(cursor)
        }

        tp = clang_type_to_runic_type(
            pointee,
            cursor,
            ctx,
            pointee_hint,
            name_hint,
        ) or_return

        if _, ok := tp.spec.(runic.FunctionPointer); !ok {
            handle_anon_type(&tp, ctx, "pointer")
        }

        if pointee.kind == .Void {
            tp.spec = runic.Builtin.RawPtr
        } else if pointee.kind == .Char_S || pointee.kind == .Char_U {
            tp.spec = runic.Builtin.String
        } else {
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.count += 1
            } else if pointee.kind != .FunctionProto &&
               pointee.kind != .FunctionNoProto {
                tp.pointer_info.count += 1
            }
        }

        if clang.isConstQualifiedType(pointee) {
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.read_only =
                    true
            } else {
                tp.pointer_info.read_only = true
            }
        }
    case .ConstantArray:
        arr_type := clang.getArrayElementType(type)
        tp = clang_type_to_runic_type(
            arr_type,
            cursor,
            ctx,
            type_hint,
            name_hint,
        ) or_return

        handle_anon_type(&tp, ctx, "array")

        arr_size := clang.getArraySize(type)

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, ctx.allocator)
        }

        append(&tp.array_info, runic.Array{})
        for i := len(tp.array_info) - 1; i > 0; i -= 1 {
            tp.array_info[i] = tp.array_info[i - 1]
        }
        tp.array_info[0] = runic.Array {
            size = u64(arr_size),
        }
    case .IncompleteArray:
        arr_type := clang.getArrayElementType(type)
        tp = clang_type_to_runic_type(
            arr_type,
            cursor,
            ctx,
            type_hint,
            name_hint,
        ) or_return

        handle_anon_type(&tp, ctx, "array")

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, ctx.allocator)
        }

        append(&tp.array_info, runic.Array{})
        for i := len(tp.array_info) - 1; i > 0; i -= 1 {
            tp.array_info[i] = tp.array_info[i - 1]
        }
        tp.array_info[0] = runic.Array {
            size = nil,
        }
    case .Typedef:
        type_name_clang := clang.getTypeSpelling(type)
        type_name := clang_str(type_name_clang)
        defer clang.disposeString(type_name_clang)

        if space_idx := strings.last_index(type_name, " "); space_idx != -1 {
            type_name = type_name[space_idx + 1:]
        }

        tp.spec = handle_builtin_int(type_name, ctx.int_sizes, ctx.allocator)
    case .Record:
        cursor_kind := clang.getCursorKind(cursor)

        members := make([dynamic]runic.Member, ctx.allocator)

        data := RecordData {
            members = &members,
            ctx     = ctx,
        }

        clang.visitChildren(cursor, proc "c" (cursor, parent: clang.Cursor, client_data: clang.ClientData) -> clang.ChildVisitResult {
                data := cast(^RecordData)client_data
                context = runtime.default_context()

                cursor_type := clang.getCursorType(cursor)
                cursor_kind := clang.getCursorKind(cursor)
                display_name_clang := clang.getCursorDisplayName(cursor)
                display_name := clang_str(display_name_clang)

                defer clang.disposeString(display_name_clang)

                if (cursor_type.kind == .Record && (struct_is_unnamed(display_name) || union_is_unnamed(display_name))) || (cursor_type.kind == .Enum && enum_is_unnamed(display_name)) {
                    return .Continue
                }

                member_name: string = ---
                if len(display_name) == 0 {
                    member_name = fmt.aprintf("member{}", len(data.members), allocator = data.ctx.allocator)
                } else {
                    member_name = strings.clone(display_name, data.ctx.allocator)
                }

                type: runic.Type = ---

                if field_size := clang.getFieldDeclBitWidth(cursor); field_size != -1 {
                    parent_display_name := clang.getCursorDisplayName(parent)
                    defer clang.disposeString(parent_display_name)
                    parent_display_name_str := clang.getCString(parent_display_name)

                    if field_size % 8 != 0 {
                        fmt.eprintfln("field \"{}.{}\" has specific bit width of {}. This field can not be converted to a byte array, therefore the type will be set to \"#Untyped\"", parent_display_name_str, member_name, field_size)
                        data.members_failed = true
                        return .Break
                    }

                    fmt.eprintfln("field \"{}.{}\" has specific bit width of {}. This is not properly supported by runic. Therefore \"{}\" will be added as \"#UInt8 #Attr Arr {} #AttrEnd\"", parent_display_name_str, member_name, field_size, member_name, field_size / 8)

                    array_info := make([dynamic]runic.Array, len = 1, cap = 1, allocator = data.ctx.allocator)
                    array_info[0].size = u64(field_size / 8)
                    type = runic.Type {
                        spec       = runic.Builtin.UInt8,
                        array_info = array_info,
                    }
                } else {
                    type_hint: Maybe(string)
                    if cursor_type.kind == .Int {
                        type_hint = clang_var_decl_get_type_hint(cursor)
                    }

                    type, data.err = clang_type_to_runic_type(cursor_type, cursor, data.ctx, type_hint, member_name)
                    if data.err != nil do return .Break
                }

                #partial switch cursor_kind {
                case .FieldDecl:
                    handle_anon_type(&type, data.ctx, member_name)

                    append(data.members, runic.Member{name = member_name, type = type})
                case:
                    #partial switch spec in type.spec {
                    case runic.Struct:
                        if len(spec.members) == 0 {
                            append(data.ctx.forward_decls, member_name)
                            return .Continue
                        }
                    case runic.Union:
                        if len(spec.members) == 0 {
                            append(data.ctx.forward_decls, member_name)
                            return .Continue
                        }
                    }

                    if om.contains(data.ctx.types^, member_name) do break

                    om.insert(data.ctx.types, member_name, type)
                }

                return .Continue
            }, &data)

        err = data.err

        if data.members_failed {
            tp.spec = runic.Builtin.Untyped
        } else {
            #partial switch cursor_kind {
            case .StructDecl:
                tp.spec = runic.Struct{members}
            case .UnionDecl:
                tp.spec = runic.Union{members}
            }
        }

    /*
        if name_hint != "TYPE_NAME_UNKNOWN" && len(members) == 0 {
            append(ctx.forward_decls, strings.clone(name_hint, ctx.allocator))
        }
        */
    case .Enum:
        e: runic.Enum

        e.entries = make([dynamic]runic.EnumEntry, ctx.allocator)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.Cursor,
                client_data: clang.ClientData,
            ) -> clang.ChildVisitResult {
                e := cast(^runic.Enum)client_data
                context = runtime.default_context()
                rs_arena_alloc := e.entries.allocator

                display_name_clang := clang.getCursorDisplayName(cursor)
                display_name := clang_str(display_name_clang)

                defer clang.disposeString(display_name_clang)

                value := clang.getEnumConstantDeclValue(cursor)

                append(
                    &e.entries,
                    runic.EnumEntry {
                        name = strings.clone(display_name, rs_arena_alloc),
                        value = i64(value),
                    },
                )

                return .Continue
            },
            &e,
        )

        enum_int_type := clang.getEnumDeclIntegerType(cursor)

        enum_type := clang_type_to_runic_type(
            enum_int_type,
            clang.getTypeDeclaration(enum_int_type),
            ctx,
            name_hint = name_hint,
        ) or_return

        // TODO: handle elaborated enum types
        #partial switch et in enum_type.spec {
        case runic.Builtin:
            // Make sure that enums were the underlying type is not specified is the same across platforms
            // On windows it defaults to SInt32 while on other systems it defaults to UInt32
            uniform_enum_type: if et == .SInt32 {
                for entry in e.entries {
                    if v_i64, is_i64 := entry.value.(i64); is_i64 {
                        if v_i64 < 0 do break uniform_enum_type
                    }
                }

                e.type = .UInt32
                break
            }

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

        if len(e.entries) == 0 {
            tp.spec = e.type
        } else {
            tp.spec = e
        }
    case .FunctionNoProto, .FunctionProto:
        type_return_type := clang.getResultType(type)
        return_type_cursor := clang.getTypeDeclaration(type_return_type)
        num_params := clang.getNumArgTypes(type)

        func: runic.Function

        func.return_type = clang_type_to_runic_type(
            type_return_type,
            return_type_cursor,
            ctx,
            name_hint = name_hint,
        ) or_return

        handle_anon_type(&func.return_type, ctx, "func")

        func.parameters = make(
            [dynamic]runic.Member,
            allocator = ctx.allocator,
            len = 0,
            cap = num_params,
        )
        func.variadic = bool(
            num_params != 0 && clang.isFunctionTypeVariadic(type),
        )

        data := FuncParamsData {
            num_params = num_params,
            func       = &func,
            ctx        = ctx,
        }

        // NOTE: If the return type of the function pointer is unknown the children can not be visited
        clang.visitChildren(cursor, proc "c" (cursor, parent: clang.Cursor, client_data: clang.ClientData) -> clang.ChildVisitResult {
                if clang.getCursorKind(cursor) != .ParmDecl do return .Continue
                data := cast(^FuncParamsData)client_data
                context = runtime.default_context()

                if data.param_idx == int(data.num_params) do return .Break
                defer data.param_idx += 1

                param_type := clang.getCursorType(cursor)
                display_name_clang := clang.getCursorDisplayName(cursor)
                display_name := clang_str(display_name_clang)

                defer clang.disposeString(display_name_clang)

                param_name: string = ---
                if len(display_name) == 0 {
                    param_name = fmt.aprintf("param{}", data.param_idx, allocator = data.ctx.allocator)
                } else {
                    param_name = strings.clone(display_name, data.ctx.allocator)
                }

                param_hint: Maybe(string)
                if param_type.kind == .Int {
                    param_hint = clang_var_decl_get_type_hint(cursor)
                }

                type: runic.Type = ---
                type, data.err = clang_type_to_runic_type(param_type, cursor, data.ctx, param_hint, param_name)
                if data.err != nil do return .Break

                handle_anon_type(&type, data.ctx, param_name)

                append(&data.func.parameters, runic.Member{name = param_name, type = type})

                return .Continue
            }, &data)

        if data.err != nil {
            err = data.err
            return
        }

        if len(func.parameters) != int(num_params) {
            fmt.eprintln(
                clang_source_error(
                    cursor,
                    "{}: could not find parameters len(func.parameters)={} num_params={}. type will be added as RawPtr",
                    name_hint,
                    len(func.parameters),
                    num_params,
                ),
            )
            tp = runic.Type {
                spec = runic.Builtin.RawPtr,
            }
            return
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

        tp.spec = new_clone(func, ctx.allocator)
    case:
        err = clang_source_error(cursor, "unsupported type \"{}\"", type.kind)
        return
    }

    if clang.isConstQualifiedType(type) {
        if len(tp.array_info) != 0 {
            tp.array_info[len(tp.array_info) - 1].read_only = true
        }
        tp.read_only = true
    }

    return
}

@(private)
handle_anon_type :: #force_inline proc(
    tp: ^runic.Type,
    ctx: ^ClangToRunicTypeContext,
    prefix: string = "",
) {
    type_name: string = ---

    #partial switch _ in tp.spec {
    case runic.Struct:
        type_name = fmt.aprintf(
            "{}_struct_anon_{}",
            prefix,
            ctx.anon_index^,
            allocator = ctx.allocator,
        )
    case runic.Enum:
        type_name = fmt.aprintf(
            "{}_enum_anon_{}",
            prefix,
            ctx.anon_index^,
            allocator = ctx.allocator,
        )
    case runic.Union:
        type_name = fmt.aprintf(
            "{}_union_anon_{}",
            prefix,
            ctx.anon_index^,
            allocator = ctx.allocator,
        )
    case runic.FunctionPointer:
        type_name = fmt.aprintf(
            "{}_func_ptr_anon_{}",
            prefix,
            ctx.anon_index^,
            allocator = ctx.allocator,
        )
    case:
        return
    }

    ctx.anon_index^ += 1
    om.insert(ctx.types, type_name, runic.Type{spec = tp.spec})
    tp.spec = type_name
}

@(private)
handle_builtin_int_cxstring :: proc(
    type_name: clang.String,
    isz: Int_Sizes,
    allocator: runtime.Allocator,
) -> runic.TypeSpecifier {
    return handle_builtin_int_string(clang_str(type_name), isz, allocator)
}

@(private)
handle_builtin_int_string :: proc(
    type_name: string,
    isz: Int_Sizes,
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
    case "__int128":
        return runic.Builtin.SInt128
    case "ssize_t":
        return runic.Builtin.SIntX
    case "uint8_t":
        return runic.Builtin.UInt8
    case "uint16_t":
        return runic.Builtin.UInt16
    case "uint32_t":
        return runic.Builtin.UInt32
    case "uint64_t":
        return runic.Builtin.UInt64
    case "size_t":
        return runic.Builtin.UIntX
    case "intptr_t":
        return runic.Builtin.SIntX
    case "uintptr_t":
        return runic.Builtin.UIntX
    case "ptrdiff_t":
        return runic.Builtin.SIntX
    case "bool":
        return bool_type(isz._Bool)
    case:
        return strings.clone(type_name, allocator)
    }

    return runic.Builtin.Untyped
}

@(private)
handle_builtin_int :: proc {
    handle_builtin_int_cxstring,
    handle_builtin_int_string,
}
