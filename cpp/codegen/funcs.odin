package cpp_codegen

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode"
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

@(private = "file")
struct_is_unnamed_string :: #force_inline proc(display_name: string) -> bool {
    return(
        display_name == "" ||
        strings.has_prefix(display_name, "struct (unnamed") ||
        strings.has_prefix(display_name, "struct (anonymous") \
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
        strings.has_prefix(display_name, "enum (unnamed") ||
        strings.has_prefix(display_name, "enum (anonymous") \
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
        strings.has_prefix(display_name, "union (unnamed") ||
        strings.has_prefix(display_name, "union (anonymous") \
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
    case .Enum:
        e: runic.Enum

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

        tp.spec = e
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
parse_macro_definition :: proc(
    cursor: clang.Cursor,
    allocator: runtime.Allocator,
) -> (
    macro_name, macro_value: string,
) {
    cursor_extent := clang.getCursorExtent(cursor)
    cursor_start := clang.getRangeStart(cursor_extent)
    cursor_end := clang.getRangeEnd(cursor_extent)

    start_offset, end_offset: u32 = ---, ---
    file: clang.File = ---
    clang.getSpellingLocation(cursor_start, &file, nil, nil, &start_offset)
    clang.getSpellingLocation(cursor_end, nil, nil, nil, &end_offset)

    unit := clang.Cursor_getTranslationUnit(cursor)

    buffer_size: u64 = ---
    buf := clang.getFileContents(unit, file, &buffer_size)
    buffer := strings.string_from_ptr(cast(^byte)buf, int(buffer_size))

    macro_def := buffer[start_offset:end_offset]
    macro_name_end: int = len(macro_def)
    open_parens: int
    macro_def_loop: for r, idx in macro_def {
        switch r {
        case '(':
            open_parens += 1
        case ')':
            open_parens -= 1
            if open_parens == 0 {
                macro_name_end = idx
                break macro_def_loop
            }
        case:
            if open_parens == 0 && unicode.is_space(r) {
                macro_name_end = idx
                break macro_def_loop
            }
        }
    }

    macro_name = strings.clone(macro_def[:macro_name_end], allocator)

    if macro_name_end == len(macro_def) {
        macro_value = ""
    } else {
        macro_value = strings.clone(
            strings.trim_space(macro_def[macro_name_end:]),
            allocator,
        )
    }

    return
}

