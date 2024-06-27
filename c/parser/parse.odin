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

package parser

import "base:runtime"
import "core:bytes"
import ctz "core:c/frontend/tokenizer"
import "core:fmt"
import "core:io"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

Header :: struct {
    typedefs:  [dynamic]Variable,
    variables: [dynamic]Variable,
    functions: [dynamic]Function,
    macros:    om.OrderedMap(string, Macro),
}

IncludedHeader :: struct {
    using header:  Header,
    using include: Include,
}

Parser :: struct {
    using global: Header,
    includes:     [dynamic]IncludedHeader,
    arena:        runtime.Arena,
}

parse_file :: proc(
    plat: runic.Platform,
    path: string,
    input: Maybe(io.Reader) = nil,
    defines := [][2]string{},
    includedirs := []string{},
    prepreprocess := true,
    preprocess := true,
    pp_program := PREPROCESS_PROGRAM,
    pp_flags := PREPROCESS_FLAGS,
) -> (
    parser: Parser,
    err: errors.Error,
) {
    def_alloc := runtime.default_allocator()

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)

    arena_err := runtime.arena_init(&arena, 0, def_alloc)
    errors.wrap(arena_err) or_return

    rs_arena_alloc := runtime.arena_allocator(&parser.arena)
    arena_alloc := runtime.arena_allocator(&arena)

    parser.typedefs = make([dynamic]Variable, rs_arena_alloc)
    parser.variables = make([dynamic]Variable, rs_arena_alloc)
    parser.functions = make([dynamic]Function, rs_arena_alloc)
    parser.macros = om.make(string, Macro, allocator = rs_arena_alloc)
    parser.includes = make([dynamic]IncludedHeader, rs_arena_alloc)

    src_buffer: bytes.Buffer
    bytes.buffer_init_allocator(&src_buffer, 0, 0, def_alloc)
    defer bytes.buffer_destroy(&src_buffer)
    {
        ppp_buffer: strings.Builder
        pp_buffer: strings.Builder
        pp_reader: strings.Reader

        strings.builder_init_none(&ppp_buffer, def_alloc)
        strings.builder_init_none(&pp_buffer, def_alloc)
        defer strings.builder_destroy(&ppp_buffer)
        defer strings.builder_destroy(&pp_buffer)

        if prepreprocess {
            errors.wrap(
                prepreprocess_file(
                    path,
                    strings.to_stream(&ppp_buffer),
                    input,
                ),
            ) or_return
        } else {
            if input != nil {
                _, io_err := io.copy(strings.to_stream(&ppp_buffer), input.?)
                errors.wrap(io_err) or_return
            } else {
                input_file, os_err := os.open(path)
                if os_err != 0 {
                    err = errors.message(
                        "\"{}\": {}",
                        path,
                        errors.wrap(os_err),
                    )
                    return
                }
                defer os.close(input_file)

                _, io_err := io.copy(
                    strings.to_stream(&ppp_buffer),
                    os.stream_from_handle(input_file),
                )
                errors.wrap(io_err) or_return
            }
        }

        if preprocess {
            preprocess_file(
                plat,
                strings.to_reader(&pp_reader, strings.to_string(ppp_buffer)),
                bytes.buffer_to_stream(&src_buffer),
                pp_program = pp_program,
                pp_flags = pp_flags,
                pp_defines = defines,
                pp_includes = includedirs,
            ) or_return
        } else {
            _, io_err := io.copy(
                bytes.buffer_to_stream(&src_buffer),
                strings.to_reader(&pp_reader, strings.to_string(ppp_buffer)),
            )
            errors.wrap(io_err) or_return
        }
    }

    src := bytes.buffer_to_bytes(&src_buffer)

    token: ^ctz.Token = ---
    {
        context.allocator = arena_alloc

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, path, src, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.assert(token != nil) or_return

    header := &parser.global

    last: ^ctz.Token = nil
    token_loop: for ; token != nil && token.kind != .EOF; token = token.next {
        defer last = token

        switch token.lit {
        case "typedef":
            vars: [dynamic]Variable = ---
            ignore_var: bool = ---
            vars, token, ignore_var = parse_typedef(
                token,
                rs_arena_alloc,
            ) or_return
            defer delete(vars)

            if token.lit != ";" do return parser, errors_expect(token, ";")

            if !ignore_var {
                append(&header.typedefs, ..vars[:])
            }
        case MACRO_VAR:
            mv: MacroVar = ---
            mv, token = parse_macro_var(token, rs_arena_alloc) or_return

            if token.lit != ";" do return parser, errors_expect(token, ";")

            om.insert(&header.macros, mv.name, mv)
        case MACRO_FUNC:
            mf: MacroFunc = ---
            mf, token = parse_macro_func(token, rs_arena_alloc) or_return

            if token.lit != ";" do return parser, errors_expect(token, ";")

            om.insert(&header.macros, mf.name, mf)
        case INCLUDE_REL:
            token = token.next
            if token.kind != .String do return parser, errors_expect(token, "string literal")

            include_path := strings.clone(
                strings.trim_suffix(strings.trim_prefix(token.lit, `"`), `"`),
                rs_arena_alloc,
            )

            hd := IncludedHeader {
                include = Include{type = .Relative, path = include_path},
            }

            append(&parser.includes, hd)
            header = &parser.includes[len(parser.includes) - 1]
            header.typedefs = make([dynamic]Variable, rs_arena_alloc)
            header.variables = make([dynamic]Variable, rs_arena_alloc)
            header.functions = make([dynamic]Function, rs_arena_alloc)
            header.macros = om.make(string, Macro, allocator = rs_arena_alloc)
        case INCLUDE_SYS:
            token = token.next
            if token.kind != .String do return parser, errors_expect(token, "string literal")

            include_path := strings.clone(
                strings.trim_suffix(strings.trim_prefix(token.lit, `"`), `"`),
                rs_arena_alloc,
            )

            hd := IncludedHeader {
                include = Include{type = .System, path = include_path},
            }

            append(&parser.includes, hd)
            header = &parser.includes[len(parser.includes) - 1]
            header.typedefs = make([dynamic]Variable, rs_arena_alloc)
            header.variables = make([dynamic]Variable, rs_arena_alloc)
            header.functions = make([dynamic]Function, rs_arena_alloc)
            header.macros = om.make(string, Macro, allocator = rs_arena_alloc)
        case INCLUDE_END:
            header = &parser.global
        case "__extension__":
        // Ignore
        case ";":
        // Ignore
        case:
            vars: [dynamic]Variable = ---
            ignore_var: bool = ---
            vars, token, ignore_var = parse_variable(
                token,
                true,
                allocator = rs_arena_alloc,
            ) or_return
            defer delete(vars)

            if !ignore_var && len(vars) != 1 {
                append(&header.variables, ..vars[:])
                continue token_loop
            }

            var := &vars[0]

            var_switch: switch token.lit {
            case ";":
                if ignore_var do continue token_loop

                typ: Type
                name: Maybe(string)

                switch p in var {
                case Var:
                    typ = p.type
                    name = p.name
                case Function:
                    name = p.name
                }

                if name != nil {
                    append(&header.variables, var^)
                } else {
                    if typ == nil do break

                    switch t in typ {
                    case Struct:
                        v := var.(Var)
                        v.name = t.name
                        var^ = v
                    case Enum:
                        v := var.(Var)
                        v.name = t.name
                        var^ = v
                    case Union:
                        v := var.(Var)
                        v.name = t.name
                        var^ = v
                    case BuiltinType, CustomType, FunctionPrototype:
                        // Ignore
                        break var_switch
                    }

                    append(&header.typedefs, var^)
                }
            case "(":
                f: Function = ---
                ignore_func: bool = ---
                f, token, ignore_func = parse_function_parameters(
                    token,
                    var^,
                    rs_arena_alloc,
                ) or_return

                if !ignore_var && !ignore_func {
                    append(&header.functions, f)
                }

                semicolon_expected := true

                token = token.next
                switch token.lit {
                case ";":
                    break var_switch
                case "{":
                    token = skip_between(token, "{", "}") or_return
                    semicolon_expected = false
                case "__asm__":
                    if token = token.next; token.lit != "(" do return parser, errors_expect(token, "(")
                    token = skip_between(token, "(", ")") or_return
                case:
                    err = errors_expect(token, ";, { or __asm__")
                    return
                }

                if token.next.kind != .EOF {
                    token = skip_gnu_attribute(
                        token,
                        skip_after = semicolon_expected,
                    ) or_return

                    if semicolon_expected {
                        if token.lit != ";" do return parser, errors_expect(token, ";")
                    }
                }
            case:
                err = errors_expect(token, "; or (")
                return
            }
        }
    }

    post_process(&parser)

    return
}

destroy_parser :: proc(parser: ^Parser) {
    runtime.arena_destroy(&parser.arena)
}

parse_typedef :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    vars: [dynamic]Variable,
    token: ^ctz.Token,
    ignore: bool,
    err: errors.Error,
) {
    token = _token.next

    vars, token, ignore = parse_variable(
        token,
        true,
        true,
        allocator,
    ) or_return

    return
}

parse_variable :: proc(
    _token: ^ctz.Token,
    allow_multiple: bool,
    parse_function_prototype := false,
    allocator := context.allocator,
) -> (
    vars: [dynamic]Variable,
    token: ^ctz.Token,
    ignore: bool,
    err: errors.Error,
) {
    token = _token

    qs := make([dynamic]TypeQualifier, allocator)

    // parse type qualifiers
    qualifier_loop: for ; token != nil && token.kind != .EOF;
        token = token.next {

        token = skip_gnu_attribute(token, token, true) or_return

        switch token.lit {
        case "const":
            append(&qs, TypeQualifier.const)
        case "restrict":
            append(&qs, TypeQualifier.restrict)
        case "volatile":
            append(&qs, TypeQualifier.volatile)
        case "_Atomic":
            append(&qs, TypeQualifier._Atomic)
        case "static":
            append(&qs, TypeQualifier.static)
        case "inline", "__inline__", "__inline":
            append(&qs, TypeQualifier.Inline)
        case "extern":
            append(&qs, TypeQualifier.extern)
        case "_Noreturn":
            append(&qs, TypeQualifier._Noreturn)
        case "__extension__":
            token = token.next
            fallthrough
        case:
            // continue to parsing type specifiers
            break qualifier_loop
        }

        if token.next == nil || token.kind == .EOF do return vars, token, false, errors_eof(token if token != nil else _token)
    }

    ts: Type

    // parse type specifiers
    specifier_switch: switch token.lit {
    case "void":
        ts = BuiltinType.void
    case "char":
        ts = BuiltinType.char
    case "signed":
        p := token.next
        switch p.lit {
        case "char":
            token = p
            ts = BuiltinType.signedchar
            break specifier_switch
        case "short":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.short
                break specifier_switch
            }

            token = p
            ts = BuiltinType.short
            break specifier_switch
        case "int":
            token = p
            ts = BuiltinType.int
            break specifier_switch
        case "long":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.long
                break specifier_switch
            case "long":
                ppp := pp.next
                switch ppp.lit {
                case "int":
                    token = ppp
                    ts = BuiltinType.longlong
                    break specifier_switch
                }

                token = pp
                ts = BuiltinType.longlong
                break specifier_switch
            }

            token = p
            ts = BuiltinType.long
            break specifier_switch
        }

        ts = BuiltinType.int
    case "unsigned":
        p := token.next
        switch p.lit {
        case "char":
            token = p
            ts = BuiltinType.unsignedchar
            break specifier_switch
        case "short":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.unsignedshort
                break specifier_switch
            }

            token = p
            ts = BuiltinType.unsignedshort
            break specifier_switch
        case "int":
            token = p
            ts = BuiltinType.unsignedint
            break specifier_switch
        case "long":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.unsignedlong
                break specifier_switch
            case "long":
                ppp := pp.next
                switch ppp.lit {
                case "int":
                    token = ppp
                    ts = BuiltinType.unsignedlonglong
                    break specifier_switch
                }

                token = pp
                ts = BuiltinType.unsignedlonglong
                break specifier_switch
            }

            token = p
            ts = BuiltinType.unsignedlong
            break specifier_switch
        }
        ts = BuiltinType.unsignedint
    case "short":
        p := token.next
        if p.lit == "int" {
            token = p
        }

        ts = BuiltinType.short
    case "int":
        ts = BuiltinType.int
    case "long":
        p := token.next
        switch p.lit {
        case "int":
            token = p
            ts = BuiltinType.long
            break specifier_switch
        case "double":
            pp := p.next
            switch pp.lit {
            case "_Complex":
                token = pp
                ts = BuiltinType.longdouble_Complex
                break specifier_switch
            }

            token = p
            ts = BuiltinType.longdouble
            break specifier_switch
        case "long":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.longlong
                break specifier_switch
            case "unsigned":
                ppp := pp.next
                switch ppp.lit {
                case "int":
                    token = ppp
                    ts = BuiltinType.unsignedlonglong
                    break specifier_switch
                }

                token = pp
                ts = BuiltinType.unsignedlonglong
                break specifier_switch
            }

            token = p
            ts = BuiltinType.longlong
            break specifier_switch
        case "unsigned":
            pp := p.next
            switch pp.lit {
            case "int":
                token = pp
                ts = BuiltinType.unsignedlong
                break specifier_switch
            }

            token = p
            ts = BuiltinType.unsignedlong
            break specifier_switch
        }

        ts = BuiltinType.long
    case "float":
        p := token.next
        switch p.lit {
        case "_Complex":
            token = p
            ts = BuiltinType.float_Complex
            break specifier_switch
        }

        ts = BuiltinType.float
    case "double":
        p := token.next
        switch p.lit {
        case "_Complex":
            token = p
            ts = BuiltinType.double_Complex
            break specifier_switch
        }
        ts = BuiltinType.double
    case "_Bool":
        ts = BuiltinType._Bool
    case "struct":
        s: Struct = ---
        ignore_var: bool = ---
        s, token, ignore_var = parse_struct(token, allocator) or_return

        if len(s.members) == 0 {
            if s.name != nil {
                ts = CustomType{s.name.?}
            }
        } else {
            ts = s
        }
        ignore = ignore || ignore_var
    case "union":
        s: Struct = ---
        ignore_var: bool = ---
        s, token, ignore_var = parse_struct(token, allocator) or_return

        u := Union {
            name    = s.name,
            members = s.members,
        }

        if len(u.members) == 0 {
            if u.name != nil {
                ts = CustomType{u.name.?}
            }
        } else {
            ts = u
        }
        ignore = ignore || ignore_var
    case "enum":
        e: Enum = ---
        e, token = parse_enum(token, allocator) or_return

        if len(e.values) == 0 {
            if (e.name != nil) {
                ts = CustomType{e.name.?}
            }
        } else {
            ts = e
        }
    case:
        if token.kind != .Ident do return vars, token, false, errors_ident(token)

        ts = CustomType{strings.clone(token.lit, allocator)}
    }

    token = token.next


    first_pi: PointerInfo
    first_ai: ArrayInfo
    first_name: Maybe(string)

    if token.lit == "*" {
        first_pi, token = parse_pointer_info(token, allocator) or_return

        token = token.next
    }

    if token.lit == "(" {
        p := skip_gnu_attribute(token) or_return
        p = p.next
        if p.lit == "*" {
            // function pointer
            token = p.next

            func_ptr_pi: PointerInfo
            if token.kind != .Ident && token.lit == "*" {
                func_ptr_pi, token = parse_pointer_info(
                    token,
                    allocator,
                ) or_return
                token = token.next
            }

            if token.kind == .Ident {
                first_name = strings.clone(token.lit, allocator)
                token = token.next
            }

            if token.lit == "[" {
                first_ai, token = parse_array_info(token, allocator) or_return
            }

            if token.lit == ")" {
                token = token.next
                if token.lit != "(" do return vars, token, false, errors_expect(token, "(")

                var := Var {
                    type         = ts,
                    name         = first_name,
                    qualifiers   = qs,
                    pointer_info = first_pi,
                    array_info   = first_ai,
                }

                f: Function = ---
                ignore_func: bool = ---
                f, token, ignore_func = parse_function_parameters(
                    token,
                    var,
                    allocator,
                ) or_return

                ignore = ignore || ignore_func

                token = token.next

                f.pointer_info = func_ptr_pi

                append(&vars, f)
                return
            } else {
                err = errors_expect(token, ")")
                return
            }
        } else {
            err = errors_expect(token, "*")
            return
        }
    }

    token = skip_gnu_attribute(token, token, true) or_return

    if token.kind == .Ident {
        first_name = strings.clone(token.lit, allocator)
        token = token.next
    }

    if parse_function_prototype && token.lit == "(" {
        // Function prototype
        func: Function = ---
        func, token, ignore = parse_function_parameters(
            token,
            Var {
                type = ts,
                name = first_name,
                qualifiers = qs,
                pointer_info = first_pi,
            },
            allocator = allocator,
        ) or_return

        token = token.next

        append(&vars, Var{type = FunctionPrototype(func), name = first_name})
        return
    }

    if token.lit == "[" {
        first_ai, token = parse_array_info(token, allocator) or_return
    }

    token = skip_gnu_attribute(token, token, true) or_return

    if token.kind == .Punct && token.lit == "=" {
        token = skip_variable_definition(token) or_return
    }

    append(
        &vars,
        Var {
            type = ts,
            name = first_name,
            qualifiers = qs,
            pointer_info = first_pi,
            array_info = first_ai,
        },
    )

    for allow_multiple && token.kind == .Punct && token.lit == "," {
        token = token.next

        pi: PointerInfo
        ai: ArrayInfo
        name: string

        if token.lit == "*" {
            pi, token = parse_pointer_info(token) or_return
            token = token.next
        }

        if token.kind != .Ident do return vars, token, false, errors_ident(token)

        name = strings.clone(token.lit, allocator)
        token = token.next

        if token.lit == "[" {
            ai, token = parse_array_info(token, allocator) or_return
        }

        token = skip_gnu_attribute(token, token, true) or_return

        if token.kind == .Punct && token.lit == "=" {
            token = skip_variable_definition(token) or_return
        }

        append(
            &vars,
            Var {
                type = ts,
                name = name,
                qualifiers = qs,
                pointer_info = pi,
                array_info = ai,
            },
        )
    }

    return
}

parse_struct :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    s: Struct,
    token: ^ctz.Token,
    ignore: bool,
    err: errors.Error,
) {
    token = _token

    token = skip_gnu_attribute(token) or_return

    name: Maybe(string)
    p := token.next
    if p.kind == .Ident {
        name = strings.clone(p.lit, allocator)
        token = p
    }

    ms := make([dynamic]Variable, allocator)

    p = token.next
    if p.lit == "{" {
        token = p.next
        // Parse struct members
        member_loop: for ; token != nil &&
            token.kind != .EOF &&
            token.lit != "}";
            token = token.next {

            vars: [dynamic]Variable = ---
            ignore_var: bool = ---
            vars, token, ignore_var = parse_variable(
                token,
                true,
                allocator = allocator,
            ) or_return
            defer delete(vars)

            ignore = ignore || ignore_var

            token = skip_gnu_attribute(token, token, true) or_return

            append(&ms, ..vars[:])

            switch token.lit {
            case ";":
                continue
            case "}":
                break member_loop
            case ":":
                // All structs that use bit field sizes are ignored and all functions types containing such structs are also ignored
                token = token.next
                token = skip_between(token, token.lit, ";") or_return
                ignore = true
                continue
            case:
                err = errors_expect(token, "; or }")
                return
            }
        }
    }

    if token.kind == .EOF do return s, token, false, errors_eof(token)

    token = skip_gnu_attribute(token) or_return

    s = Struct {
        members = ms,
        name    = name,
    }

    return
}

parse_enum :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    e: Enum,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    token = skip_gnu_attribute(token) or_return

    name: Maybe(string)

    p := token.next
    if p.kind == .Ident {
        name = strings.clone(p.lit, allocator)
        token = p
    }

    ev := make([dynamic]EnumConstant, allocator)

    p = token.next
    if p.lit == "{" {
        token = p.next

        // Parse enum values
        value_loop: for ; token != nil &&
            token.kind != .EOF &&
            token.lit != "}";
            token = token.next {
            if token.kind != .Ident do return e, token, errors_ident(token)

            ec: EnumConstant
            ec.name = strings.clone(token.lit, allocator)
            defer append(&ev, ec)

            p = skip_gnu_attribute(token) or_return

            p = p.next
            switch p.lit {
            case ",":
                token = p
                continue
            case "}":
                token = p
                break value_loop
            case "=":
                cie: ConstantIntegerExpression = ---
                cie, token = parse_constant_integer_expression(
                    p.next,
                    {",", "}"},
                    allocator,
                ) or_return

                ec.value = cie

                if token.lit == "}" {
                    break value_loop
                }
            }
        }
    }

    if token.kind == .EOF do return e, token, errors_eof(token)

    token = skip_gnu_attribute(token) or_return

    e = Enum {
        name   = name,
        values = ev,
    }

    return
}

parse_constant_integer_expression :: proc(
    _token: ^ctz.Token,
    end_tokens: []string,
    allocator := context.allocator,
) -> (
    cie: ConstantIntegerExpression,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    str_expr: strings.Builder
    defer strings.builder_destroy(&str_expr)

    token_count: uint
    token_loop: for ; token != nil && token.kind != .EOF; token = token.next {
        #partial switch token.kind {
        case .Number:
            strings.write_string(&str_expr, token.lit)
        case .Punct:
            switch token.lit {
            case "+", "-", "*", "/", "%", "(", ")", "<", ">", "<<", ">>", "<=", ">=", "==", "!=", "!", "~", "^", ":", "?", "|", "&", "&&", "||":
                strings.write_string(&str_expr, token.lit)
            case:
                if slice.contains(end_tokens, token.lit) do break token_loop

                err = errors_expect(token, "operator or paranthesis")
                return
            }
        case .Ident, .Char:
            strings.write_string(&str_expr, token.lit)
        case:
            err = errors_expect(token, "integer, operator or identifier")
            return
        }

        token_count += 1
    }

    expr := strings.to_string(str_expr)
    if token_count == 1 {
        if ival, ok := strconv.parse_int(expr); ok {
            cie = cast(i64)ival
        } else {
            cie = strings.clone(expr, allocator)
        }
        return
    }

    if len(expr) != 0 {
        arena: runtime.Arena
        defer runtime.arena_destroy(&arena)

        parsed_expr, ok := parse_expression(
            expr,
            runtime.arena_allocator(&arena),
        )

        if !ok {
            cie = strings.clone(expr, allocator)
        } else {
            cie = evaluate_expression(parsed_expr)
        }
    }
    return
}

parse_function_parameters :: proc(
    _token: ^ctz.Token,
    return_type: Variable,
    allocator := context.allocator,
) -> (
    f: Function,
    token: ^ctz.Token,
    ignore: bool,
    err: errors.Error,
) {
    token = _token
    if token.kind == .EOF do return f, token, false, errors_eof(token)

    f.return_type = new_clone(return_type, allocator)
    switch v in return_type {
    case Var:
        f.name = v.name
    case Function:
        f.name = v.name
    }

    token = token.next

    // Parse function paramter values
    ps := make([dynamic]Variable, allocator)

    param_loop: for ; token != nil && token.kind != .EOF && token.lit != ")";
        token = token.next {
        if token.kind == .Punct && token.lit == "..." {
            token = token.next
            if token.kind != .Punct || token.lit != ")" do return f, token, false, errors_expect(token, ")")

            f.variadic = true

            break
        }

        vars: [dynamic]Variable = ---
        ignore_var: bool = ---
        vars, token, ignore_var = parse_variable(
            token,
            false,
            allocator = allocator,
        ) or_return
        defer delete(vars)

        ignore = ignore || ignore_var

        append(&ps, vars[0])

        switch token.lit {
        case ",":
            continue
        case ")":
            break param_loop
        }
    }

    token = skip_gnu_attribute(token) or_return

    if len(ps) == 1 {
        if var, ok := ps[0].(Var); ok {
            if var.pointer_info.count == 0 && len(var.array_info) == 0 {
                if b, b_ok := var.type.(BuiltinType); b_ok {
                    if b == .void {
                        delete(ps)
                        ps = {}
                    }
                }
            }
        }
    }

    f.parameters = ps

    return
}

parse_pointer_info :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    pi: PointerInfo,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token
    p := _token.next

    pi.count = 1

    for ; p != nil && p.kind != .EOF; p = p.next {
        switch p.lit {
        case "*":
            pi.count += 1
        case "const":
            pi.const = true
            token = p
            p = p.next
            if p.kind == .Punct && p.lit == "*" {
                child: PointerInfo = ---
                child, token = parse_pointer_info(p, allocator) or_return
                pi.child = new_clone(child, allocator)
            }
            return
        case "__restrict", "__restrict__", "restrict":
            pi.restrict = true
            token = p
            p = p.next
            if p.kind == .Punct && p.lit == "*" {
                child: PointerInfo = ---
                child, token = parse_pointer_info(p, allocator) or_return
                pi.child = new_clone(child, allocator)
            }
            return
        case:
            return
        }

        token = token.next
    }

    err = errors_eof(token)
    return
}

parse_array_info :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    ai: ArrayInfo,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    ai = make([dynamic]ConstantIntegerExpression, allocator)

    for ; token != nil && token.kind != .EOF; token = token.next {
        switch token.lit {
        case "[":
            token = token.next
            cie: ConstantIntegerExpression = ---
            cie, token = parse_constant_integer_expression(
                token,
                {"]"},
                allocator,
            ) or_return

            append(&ai, cie)
        case:
            slice.reverse(ai[:])
            return
        }
    }

    err = errors_eof(token)
    return
}

parse_macro_var :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    mv: MacroVar,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token.next

    if token.kind != .Ident do return mv, token, errors_ident(token)

    if !strings.has_prefix(token.lit, PREPREPROCESS_PREFIX) do return mv, token, errors_expect(token, fmt.aprint(PREPREPROCESS_PREFIX, token.lit))

    mv.name = strings.clone(
        strings.trim_prefix(token.lit, PREPREPROCESS_PREFIX),
        allocator,
    )

    token = token.next

    if token.lit == "=" {
        if token = token.next; token.lit != "(" do return mv, token, errors_expect(token, "(")
        if token = token.next; token.lit != "(" do return mv, token, errors_expect(token, "(")

        value: strings.Builder
        strings.builder_init(&value, allocator)

        paran_count: uint = 0
        token = token.next
        last_offset := token.pos.offset

        para_loop: for ; token != nil && token.kind != .EOF;
            token = token.next {
            defer last_offset = token.pos.offset + len(token.lit)

            if token.has_space {
                for _ in 0 ..< (token.pos.offset - last_offset) {
                    strings.write_rune(&value, ' ')
                }
            }

            if token.kind == .Punct {
                switch token.lit {
                case "(":
                    paran_count += 1
                case ")":
                    if paran_count == 0 {
                        break para_loop
                    }
                    paran_count -= 1
                }
            }

            strings.write_string(&value, token.lit)
        }

        mv.value = strings.to_string(value)

        if token = token.next; token.lit != ")" do return mv, token, errors_expect(token, ")")

        token = token.next
    }

    return
}

parse_macro_func :: proc(
    _token: ^ctz.Token,
    allocator := context.allocator,
) -> (
    mf: MacroFunc,
    token: ^ctz.Token,
    err: Maybe(string),
) {
    token = _token.next

    if token.kind != .Ident do return mf, token, errors_ident(token)

    if !strings.has_prefix(token.lit, PREPREPROCESS_PREFIX) do return mf, token, errors_expect(token, fmt.aprint(PREPREPROCESS_PREFIX, token.lit))

    mf.name = strings.clone(
        strings.trim_prefix(token.lit, PREPREPROCESS_PREFIX),
        allocator,
    )

    if token = token.next; token.lit != "(" do return mf, token, errors_expect(token, "(")

    mf.parameters = make([dynamic]string, allocator)

    param_loop: for token = token.next;
        token != nil && token.kind != .EOF;
        token = token.next {
        if token.kind != .Ident do return mf, token, errors_ident(token)

        append(&mf.parameters, strings.clone(token.lit, allocator))

        token = token.next
        switch token.lit {
        case ",":
            continue
        case ")":
            break param_loop
        case:
            err = errors_expect(token, ", or )")
            return
        }
    }

    if token = token.next; token.lit != "=" do return mf, token, errors_expect(token, "=")
    if token = token.next; token.lit != "(" do return mf, token, errors_expect(token, "(")
    if token = token.next; token.lit != "(" do return mf, token, errors_expect(token, "(")

    paran_count: uint
    last_offset := token.next.pos.offset

    mf.body = make([dynamic]MacroFuncToken, allocator)

    body_loop: for token = token.next;
        token != nil && token.kind != .EOF;
        token = token.next {
        defer last_offset = token.pos.offset + len(token.lit)

        if token.kind == .Ident {
            if idx, ok := slice.linear_search(mf.parameters[:], token.lit);
               ok {
                spaces :=
                    token.pos.offset - last_offset if token.has_space else 0
                append(
                    &mf.body,
                    MacroInsertion{parameter = idx, spaces = spaces},
                )
                continue
            }
        }

        bd: strings.Builder
        strings.builder_init(&bd, allocator)

        if token.has_space {
            for _ in 0 ..< (token.pos.offset - last_offset) {
                strings.write_rune(&bd, ' ')
            }
        }

        switch token.lit {
        case "(":
            paran_count += 1
        case ")":
            if paran_count == 0 {
                break body_loop
            }
            paran_count -= 1
        }

        strings.write_string(&bd, token.lit)
        append(&mf.body, strings.to_string(bd))
    }

    if token = token.next; token.lit != ")" do return mf, token, errors_expect(token, ")")
    token = token.next

    return
}

skip_gnu_attribute :: proc(
    _token: ^ctz.Token,
    _next: ^ctz.Token = nil,
    skip_after: bool = false,
    loc := #caller_location,
) -> (
    token: ^ctz.Token,
    err: errors.Error,
) {
    errors.assert(_token != nil || _next != nil) or_return

    if _next != nil {
        token = _next
    } else {
        token = _token.next
    }

    last := _token

    for ; token != nil && token.kind != .EOF; token = token.next {
        switch token.lit {
        case "__attribute__":
            token = token.next
            token = skip_between(token, "(", ")", loc) or_return
            last = token
        case:
            if !skip_after {
                token = last
            }
            return
        }
    }

    err = errors_eof(token)
    return
}

skip_between :: proc(
    _token: ^ctz.Token,
    begin: string,
    end: string,
    loc := #caller_location,
) -> (
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    open_count: uint = 1
    token = token.next

    for ; token != nil && token.kind != .EOF; token = token.next {
        if token.lit == begin {
            open_count += 1
        } else if token.lit == end {
            open_count -= 1
        }

        if open_count == 0 {
            return
        }
    }

    err = errors_eof(token, loc = loc)
    return
}

skip_variable_definition :: proc(
    _token: ^ctz.Token,
) -> (
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token.next
    if token.kind == .EOF do return token, errors_eof(token)

    if token.kind == .Punct && token.lit == "{" {
        token = skip_between(token, "{", "}") or_return

        if token = token.next; token.kind != .Punct || (token.lit != ";" && token.lit != ",") do return token, errors_expect(token, "; or ,")
        return
    }

    if token.kind == .Punct && token.lit == ";" {
        err = errors_expect(token, "not ;")
        return
    }

    for token = token.next;
        token != nil &&
        token.kind != .EOF &&
        (token.kind != .Punct || (token.lit != ";" && token.lit != ","));
        token = token.next {}

    if token.kind == .EOF do return token, errors_eof(token)
    return
}
