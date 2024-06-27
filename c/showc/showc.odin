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

package main

import "../parser"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import om "root:ordered_map"
import "root:runic"

main :: proc() {
    plat := runic.platform_from_host()

    in_file_name: string
    in_handle: os.Handle
    in_stream: Maybe(io.Reader)
    preprocess := true
    prepreprocess := true

    defer os.close(in_handle)

    if len(os.args) >= 2 {
        in_file_name = os.args[1]
    }
    if len(os.args) >= 3 {
        for arg in os.args[2:] {
            switch arg {
            case "-pp":
                preprocess = false
            case "-ppp":
                prepreprocess = false
            }
        }
    }

    if len(in_file_name) == 0 || in_file_name == "-" {
        in_file_name = "./stdin"
        in_stream = os.stream_from_handle(os.stdin)
    }

    ps, err := parser.parse_file(
        plat,
        in_file_name,
        in_stream,
        prepreprocess = prepreprocess,
        preprocess = preprocess,
    )
    defer parser.destroy_parser(&ps)
    if err != nil {
        fmt.eprintfln("failed to parse: {}", err)
        os.exit(1)
    }

    using ps


    if len(includes) != 0 {
        fmt.println("----------- INCLUDES ----------------")
        for i in includes {
            fmt.printfln("{}: {}", i.path, i.type)
        }
        fmt.println("-------------------------------------")
    }
    if om.length(macros) != 0 {
        fmt.println("----------- MACROS ----------------")
        for entry in macros.data {
            m := entry.value
            switch v in m {
            case parser.MacroVar:
                fmt.printf("{}: ", v.name)
                if v.value != nil {
                    fmt.printf("{}", v.value)
                }
                fmt.println()
            case parser.MacroFunc:
                fmt.printf("{}: (", v.name)
                for p in v.parameters {
                    fmt.printf("{}, ", p)
                }
                fmt.print(") { ")
                for b in v.body {
                    switch bd in b {
                    case string:
                        fmt.print(bd)
                    case parser.MacroInsertion:
                        fmt.printf(
                            "{}$PARAM({})",
                            strings.repeat(" ", bd.spaces),
                            v.parameters[bd.parameter],
                        )
                    }
                }
                fmt.println(" }")
            }
        }
        fmt.println("-----------------------------------")
    }
    if len(typedefs) != 0 {
        fmt.println("----------- TYPES -----------------")
        for td in typedefs {
            fmt.printf("{}: ", variable_name(td))
            fmt.println(variable_to_string(td, false))
        }
        fmt.println("-----------------------------------")
    }
    if len(functions) != 0 {
        fmt.println("----------- FUNCTIONS ----------------")
        for f in functions {
            fmt.printf("{}: ", f.name)
            fmt.println(func_to_string(f, false))
        }
        fmt.println("--------------------------------------")
    }
    if len(variables) != 0 {
        fmt.println("----------- VARIABLES ----------------")
        for v in variables {
            fmt.printf("{}: ", variable_name(v))
            fmt.println(variable_to_string(v, false))
        }
        fmt.println("--------------------------------------")
    }

}

variable_name :: proc(var: parser.Variable) -> string {
    switch v in var {
    case parser.Var:
        return v.name.? or_else ""
    case parser.Function:
        return v.name.? or_else ""
    }

    assert(false)
    return ""
}

variable_to_string :: proc(
    var: parser.Variable,
    print_name := true,
) -> string {
    switch v in var {
    case parser.Var:
        return var_to_string(v, print_name)
    case parser.Function:
        return func_ptr_to_string(v, print_name)
    }

    assert(false)
    return ""
}

var_to_string :: proc(var: parser.Var, print_name := true) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    for q in var.qualifiers {
        fmt.sbprintf(&out, "{} ", q)
    }

    strings.write_string(&out, type_to_string(var.type))

    for a in var.array_info {
        strings.write_rune(&out, '[')
        if a != nil {
            fmt.sbprintf(&out, "{}", a)
        }
        strings.write_rune(&out, ']')
    }

    for i: uint; i < var.pointer_info.count; i += 1 {
        strings.write_rune(&out, '*')
    }

    if var.pointer_info.const {
        strings.write_string(&out, "const")
    }
    if var.pointer_info.restrict {
        strings.write_string(&out, "restrict")
    }

    if print_name && var.name != nil {
        fmt.sbprintf(&out, " {}", var.name)
    }

    return strings.to_string(out)
}

type_to_string :: proc(type: parser.Type) -> string {
    switch v in type {
    case parser.BuiltinType:
        return fmt.aprint(v)
    case parser.Struct:
        return struct_to_string(v, false)
    case parser.Enum:
        return enum_to_string(v, false)
    case parser.Union:
        return union_to_string(v, false)
    case parser.CustomType:
        return v.name
    case parser.FunctionPrototype:
        return func_proto_to_string(v, false)
    }

    return "invalid"
}

struct_to_string :: proc(s: parser.Struct, print_name := true) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    strings.write_string(&out, "struct ")
    if print_name && s.name != nil {
        strings.write_string(&out, s.name.?)
        strings.write_rune(&out, ' ')
    }

    strings.write_rune(&out, '{')
    for p in s.members {
        strings.write_string(&out, variable_to_string(p))
        strings.write_string(&out, ", ")
    }
    strings.write_rune(&out, '}')

    return strings.to_string(out)
}

union_to_string :: proc(u: parser.Union, print_name := true) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    strings.write_string(&out, "union ")
    if print_name && u.name != nil {
        strings.write_string(&out, u.name.?)
        strings.write_rune(&out, ' ')
    }

    strings.write_rune(&out, '{')
    for p in u.members {
        strings.write_string(&out, variable_to_string(p))
        strings.write_string(&out, ", ")
    }
    strings.write_rune(&out, '}')

    return strings.to_string(out)
}

enum_to_string :: proc(e: parser.Enum, print_name := true) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    strings.write_string(&out, "enum ")
    if print_name && e.name != nil {
        strings.write_string(&out, e.name.?)
        strings.write_rune(&out, ' ')
    }

    strings.write_rune(&out, '{')
    for val in e.values {
        strings.write_string(&out, val.name)
        if val.value != nil {
            strings.write_string(&out, " = ")
            strings.write_string(&out, const_int_expr_to_string(val.value.?))
        }
        strings.write_string(&out, ", ")
    }
    strings.write_rune(&out, '}')

    return strings.to_string(out)
}

const_int_expr_to_string :: proc(
    cie: parser.ConstantIntegerExpression,
) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    switch c in cie {
    case i64:
        strings.write_i64(&out, c)
    case string:
        strings.write_rune(&out, '"')
        strings.write_string(&out, c)
        strings.write_rune(&out, '"')
    }

    return strings.to_string(out)
}

func_to_string :: proc(f: parser.Function, print_name := true) -> string {
    using f

    out: strings.Builder
    strings.builder_init_none(&out)

    if print_name && name != nil {
        strings.write_rune(&out, ' ')
        strings.write_string(&out, name.?)
    }
    strings.write_rune(&out, '(')
    for p in parameters {
        strings.write_string(&out, variable_to_string(p))
        strings.write_string(&out, ", ")
    }
    if variadic {
        strings.write_string(&out, "variadic")
    }

    strings.write_rune(&out, ')')

    should_print_return: bool = true
    #partial switch v in return_type^ {
    case parser.Var:
        if len(v.qualifiers) != 0 {
            break
        }

        #partial switch t in v.type {
        case parser.BuiltinType:
            if v.pointer_info.count == 0 {
                should_print_return = false
            }
        }
    }

    if should_print_return {
        strings.write_string(&out, " -> ")
        strings.write_string(&out, variable_to_string(return_type^, false))
    }

    return strings.to_string(out)

}

func_ptr_to_string :: proc(fp: parser.Function, print_name := true) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    strings.write_string(&out, "func_ptr ")
    strings.write_string(&out, func_to_string(fp, print_name))

    return strings.to_string(out)
}

func_proto_to_string :: proc(
    fp: parser.FunctionPrototype,
    print_name := true,
) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    strings.write_string(&out, "func_proto ")
    strings.write_string(&out, func_to_string(parser.Function(fp), print_name))

    return strings.to_string(out)
}
