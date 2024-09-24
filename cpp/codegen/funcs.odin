package cpp_codegen

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
RecordData :: struct {
    members:   ^[dynamic]runic.Member,
    allocator: runtime.Allocator,
    err:       errors.Error,
    isz:       Int_Sizes,
    types:     ^om.OrderedMap(string, runic.Type),
    anon_idx:  ^int,
}

@(private = "file")
FuncParamsData :: struct {
    param_idx:  int,
    num_params: i32,
    func:       ^runic.Function,
    allocator:  runtime.Allocator,
    isz:        Int_Sizes,
    anon_idx:   ^int,
    err:        errors.Error,
    types:      ^om.OrderedMap(string, runic.Type),
}

@(private = "file")
struct_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "struct (unnamed") \
    )
}

@(private = "file")
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

@(private = "file")
enum_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "enum (unnamed") \
    )
}

@(private = "file")
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

@(private = "file")
union_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "union (unnamed") \
    )
}

@(private = "file")
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
clang_type_to_runic_type :: proc(
    type: clang.Type,
    cursor: clang.Cursor,
    isz: Int_Sizes,
    anon_idx: ^int,
    types: ^om.OrderedMap(string, runic.Type),
    allocator := context.allocator,
    type_hint: Maybe(string) = nil,
) -> (
    tp: runic.Type,
    err: errors.Error,
) {
    #partial switch type.kind {
    case .Void:
        tp.spec = runic.Builtin.Void
    case .Bool:
        tp.spec = bool_type(isz._Bool)
    case .Char_U:
        tp.spec = int_type(isz.char, false)
    case .UChar:
        tp.spec = int_type(isz.char, false)
    case .Char16:
        tp.spec = runic.Builtin.SInt16
    case .Char32:
        tp.spec = runic.Builtin.SInt32
    case .UShort:
        tp.spec = int_type(isz.short, false)
    case .UInt:
        tp.spec = int_type(isz.Int, false)
    case .ULong:
        tp.spec = int_type(isz.long, false)
    case .ULongLong:
        tp.spec = int_type(isz.longlong, false)
    case .UInt128:
        tp.spec = runic.Builtin.SInt128
    case .Char_S:
        tp.spec = int_type(isz.char, true)
    case .SChar:
        tp.spec = int_type(isz.char, true)
    case .Short:
        tp.spec = int_type(isz.short, true)
    case .Int:
        if th, ok := type_hint.?; ok && th != "int" {
            tp.spec = handle_builtin_int(th, isz, allocator)
        } else {
            tp.spec = int_type(isz.Int, true)
        }
    case .Long:
        tp.spec = int_type(isz.long, true)
    case .LongLong:
        tp.spec = int_type(isz.longlong, true)
    case .Int128:
        tp.spec = runic.Builtin.SInt128
    case .Float:
        tp.spec = float_type(isz.float)
    case .Double:
        tp.spec = float_type(isz.double)
    case .LongDouble:
        tp.spec = float_type(isz.long_double)
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
                isz,
                anon_idx,
                types,
                allocator,
            ) or_return
        } else {
            tp.spec = handle_builtin_int(named_name, isz, allocator)
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
            isz,
            anon_idx,
            types,
            allocator,
            pointee_hint,
        ) or_return

        if _, ok := tp.spec.(runic.FunctionPointer); !ok {
            handle_anon_type(&tp, types, anon_idx, "pointer", allocator)
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
            isz,
            anon_idx,
            types,
            allocator,
            type_hint,
        ) or_return

        handle_anon_type(&tp, types, anon_idx, "array", allocator)

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
    case .IncompleteArray:
        arr_type := clang.getArrayElementType(type)
        tp = clang_type_to_runic_type(
            arr_type,
            cursor,
            isz,
            anon_idx,
            types,
            allocator,
            type_hint,
        ) or_return

        handle_anon_type(&tp, types, anon_idx, "array", allocator)

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
    case .Typedef:
        type_name_clang := clang.getTypeSpelling(type)
        type_name := clang_str(type_name_clang)
        defer clang.disposeString(type_name_clang)

        if space_idx := strings.last_index(type_name, " "); space_idx != -1 {
            type_name = type_name[space_idx + 1:]
        }

        tp.spec = handle_builtin_int(type_name, isz, allocator)
    case .Record:
        cursor_kind := clang.getCursorKind(cursor)

        members := make([dynamic]runic.Member, allocator)

        data := RecordData {
            members   = &members,
            allocator = allocator,
            isz       = isz,
            types     = types,
            anon_idx  = anon_idx,
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

                field_size := clang.getFieldDeclBitWidth(cursor)

                if field_size != -1 {
                    parent_display_name := clang.getCursorDisplayName(parent)
                    defer clang.disposeString(parent_display_name)

                    data.err = errors.message("field \"{}.{}\" has specific bit width of {}", clang.getCString(parent_display_name), display_name, field_size)
                    return .Break
                }

                type_hint: Maybe(string)
                if cursor_type.kind == .Int {
                    type_hint = clang_var_decl_get_type_hint(cursor)
                }

                type: runic.Type = ---
                type, data.err = clang_type_to_runic_type(cursor_type, cursor, data.isz, data.anon_idx, data.types, data.allocator, type_hint)
                if data.err != nil do return .Break

                member_name: string = ---
                if len(display_name) == 0 {
                    member_name = fmt.aprintf("member{}", len(data.members), allocator = data.allocator)
                } else {
                    member_name = strings.clone(display_name, data.allocator)
                }

                #partial switch cursor_kind {
                case .FieldDecl:
                    handle_anon_type(&type, data.types, data.anon_idx, member_name, data.allocator)

                    append(data.members, runic.Member{name = member_name, type = type})
                case:
                    om.insert(data.types, member_name, type)
                }

                return .Continue
            }, &data)

        err = data.err

        #partial switch cursor_kind {
        case .StructDecl:
            tp.spec = runic.Struct{members}
        case .UnionDecl:
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
    case .Enum:
        e: runic.Enum

        enum_int_type := clang.getEnumDeclIntegerType(cursor)
        enum_type := clang_type_to_runic_type(
            enum_int_type,
            clang.getTypeDeclaration(enum_int_type),
            isz,
            anon_idx,
            types,
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

        tp.spec = e
    case .FunctionNoProto, .FunctionProto:
        type_return_type := clang.getResultType(type)
        return_type_cursor := clang.getTypeDeclaration(type_return_type)
        num_params := clang.getNumArgTypes(type)

        func: runic.Function

        func.return_type = clang_type_to_runic_type(
            type_return_type,
            return_type_cursor,
            isz,
            anon_idx,
            types,
            allocator,
        ) or_return

        handle_anon_type(&func.return_type, types, anon_idx, "func", allocator)

        func.parameters = make([dynamic]runic.Member, allocator)
        func.variadic = bool(
            num_params != 0 && clang.isFunctionTypeVariadic(type),
        )

        data := FuncParamsData {
            num_params = num_params,
            func       = &func,
            allocator  = allocator,
            isz        = isz,
            anon_idx   = anon_idx,
            types      = types,
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
                    param_name = fmt.aprintf("param{}", data.param_idx, allocator = data.allocator)
                } else {
                    param_name = strings.clone(display_name, data.allocator)
                }

                param_hint: Maybe(string)
                if param_type.kind == .Int {
                    param_hint = clang_var_decl_get_type_hint(cursor)
                }

                type: runic.Type = ---
                type, data.err = clang_type_to_runic_type(param_type, cursor, data.isz, data.anon_idx, data.types, data.allocator, param_hint)
                if data.err != nil do return .Break

                handle_anon_type(&type, data.types, data.anon_idx, param_name, data.allocator)

                append(&data.func.parameters, runic.Member{name = param_name, type = type})

                return .Continue
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

@(private)
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

@(private)
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
    case "uint8_t":
        return runic.Builtin.UInt8
    case "uint16_t":
        return runic.Builtin.UInt16
    case "uint32_t":
        return runic.Builtin.UInt32
    case "uint64_t":
        return runic.Builtin.UInt64
    case "size_t":
        return int_type(isz.size_t, false)
    case "intptr_t":
        return int_type(isz.intptr_t, true)
    case "uintptr_t":
        return int_type(isz.intptr_t, false)
    case "ptrdiff_t":
        return int_type(isz.intptr_t, true)
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

@(private)
clang_str :: #force_inline proc(clang_str: clang.String) -> string {
    cstr := clang.getCString(clang_str)
    return strings.string_from_ptr(cast(^byte)cstr, len(cstr))
}

