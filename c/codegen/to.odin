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

package c_codegen

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

generate_bindings :: proc(
    plat: runic.Platform,
    rs: runic.Runestone,
    rn: runic.To,
    wd: io.Writer,
) -> union {
        io.Error,
        errors.Error,
    } {
    arena: runtime.Arena
    if err := runtime.arena_init(&arena, 0, runtime.default_allocator()); err != .None do return errors.Error(errors.empty())
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

    io.write_string(wd, "#pragma once\n#include <stdint.h>\n\n") or_return

    for entry in rs.constants.data {
        name, const := entry.key, entry.value

        if b, ok := const.type.spec.(runic.Builtin); ok && b == .Untyped {
            io.write_string(wd, "#define ") or_return
            io.write_string(wd, name) or_return
            if const.value != nil {
                io.write_rune(wd, ' ') or_return
                switch value in const.value {
                case i64:
                    io.write_i64(wd, value) or_return
                case f64:
                    io.write_f64(wd, value) or_return
                case string:
                    with_bs, _ := strings.replace_all(value, "\n", "\\\n")
                    io.write_string(wd, with_bs) or_return
                }
            }
            io.write_rune(wd, '\n') or_return

            continue
        }

        io.write_string(wd, "static ") or_return
        if !const.type.read_only {
            io.write_string(wd, "const ") or_return
        }
        errors.wrap(
            write_variable(wd, rn, name, const.type, rs.types),
        ) or_return
        if const.value != nil {
            io.write_string(wd, " = ") or_return
            switch value in const.value {
            case i64:
                io.write_i64(wd, value) or_return
            case f64:
                io.write_f64(wd, value) or_return
            case string:
                with_bs, _ := strings.replace_all(value, "\n", "\\\n")
                io.write_string(
                    wd,
                    strings.concatenate({"\"", with_bs, "\""}),
                ) or_return
            }
        }
        io.write_string(wd, ";\n") or_return
    }

    if om.length(rs.constants) != 0 {
        io.write_rune(wd, '\n') or_return
    }

    for entry in rs.types.data {
        name, type := entry.key, entry.value

        if e, ok := type.spec.(runic.Enum); ok {
            if e.type != .SInt32 {
                write_type_specifier(wd, rn, e, rs.types, name) or_return
                io.write_rune(wd, '\n') or_return
                io.write_string(wd, "typedef ") or_return
                write_type_specifier(wd, rn, e.type, rs.types) or_return
                io.write_rune(wd, ' ') or_return
                io.write_string(wd, name) or_return
                io.write_string(wd, ";\n") or_return
                continue
            }
        }

        needs_typedef: bool = true
        #partial switch _ in type.spec {
        case runic.Struct, runic.Union, runic.Enum:
            needs_typedef = false
        }
        if needs_typedef {
            io.write_string(wd, "typedef ") or_return
            errors.wrap(write_variable(wd, rn, name, type, rs.types)) or_return
        } else {
            errors.wrap(
                write_type_specifier(wd, rn, type.spec, rs.types, name),
            ) or_return
        }

        io.write_string(wd, ";\n") or_return
    }

    if om.length(rs.types) != 0 {
        io.write_rune(wd, '\n') or_return
    }

    aliases, functions: strings.Builder
    defer strings.builder_destroy(&aliases)
    defer strings.builder_destroy(&functions)
    als := strings.to_stream(&aliases)
    funcs := strings.to_stream(&functions)

    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        if sym.remap != nil {
            name = sym.remap.?
        }

        switch value in sym.value {
        case runic.Type:
            io.write_string(wd, "extern ") or_return
            errors.wrap(
                write_variable(wd, rn, name, value, rs.types),
            ) or_return
            io.write_string(wd, ";\n") or_return
        case runic.Function:
            io.write_string(funcs, "extern ") or_return
            errors.wrap(
                write_variable(funcs, rn, name, value.return_type, rs.types),
            ) or_return
            errors.wrap(
                write_function_parameters(
                    funcs,
                    rn,
                    value.parameters,
                    value.variadic,
                    rs.types,
                ),
            ) or_return
            io.write_string(funcs, ";\n") or_return
        }

        if sym.remap != nil {
            io.write_string(als, "#define ") or_return
            io.write_string(als, entry.key) or_return
            io.write_rune(als, ' ') or_return
            io.write_string(als, name) or_return
            io.write_rune(als, '\n') or_return
        }

        for alias in sym.aliases {
            io.write_string(als, "#define ") or_return
            io.write_string(als, alias) or_return
            io.write_rune(als, ' ') or_return
            io.write_string(als, name) or_return
            io.write_rune(als, '\n') or_return
        }
    }

    io.write_rune(wd, '\n') or_return

    if len(strings.to_string(functions)) != 0 {
        io.write_string(wd, strings.to_string(functions)) or_return
        io.write_rune(wd, '\n') or_return
    }

    if len(strings.to_string(aliases)) != 0 {
        io.write_string(wd, strings.to_string(aliases)) or_return
        io.write_rune(wd, '\n') or_return
    }

    return nil
}

C_RESERVED :: []string{
    "int",
    "switch",
    "static",
    "volatile",
    "extern",
    // TODO: Add more C reserved keywords
}

write_variable :: proc(
    wd: io.Writer,
    rn: runic.To,
    name: string,
    type: runic.Type,
    types: om.OrderedMap(string, runic.Type),
) -> union {
        io.Error,
        errors.Error,
    } {

    if fptr, ok := type.spec.(runic.FunctionPointer); ok {
        if fptr.return_type.read_only {
            io.write_string(wd, "const ") or_return
        }

        errors.wrap(
            write_type_specifier(wd, rn, fptr.return_type.spec, types),
        ) or_return

        if fptr.return_type.pointer_info.count != 0 {
            io.write_string(
                wd,
                strings.repeat("*", int(fptr.return_type.pointer_info.count)),
            ) or_return
            if fptr.return_type.pointer_info.read_only {
                io.write_string(wd, "const") or_return
            }
        }

        io.write_string(wd, " (*") or_return
        if type.pointer_info.count != 0 {
            io.write_string(
                wd,
                strings.repeat("*", int(type.pointer_info.count)),
            ) or_return
            if type.pointer_info.read_only {
                io.write_string(wd, "const") or_return
            }
        }

        io.write_rune(wd, ' ') or_return
        io.write_string(wd, name) or_return
        io.write_rune(wd, ')') or_return

        errors.wrap(
            write_function_parameters(
                wd,
                rn,
                fptr.parameters,
                fptr.variadic,
                types,
            ),
        ) or_return
        return nil
    }

    type_spec_slot: [dynamic]string
    var_point_slot: [dynamic]string
    array_prefix_slot: [dynamic]string
    type_name_slot: string
    array_slot: [dynamic]string

    type_name_slot = name
    if type.read_only {
        append(&type_spec_slot, "const ")
    }
    {
        type_spec: strings.Builder
        write_type_specifier(
            strings.to_stream(&type_spec),
            rn,
            type.spec,
            types,
            name,
        ) or_return
        append(&type_spec_slot, strings.to_string(type_spec))
    }

    if type.pointer_info.count != 0 {
        append(
            &var_point_slot,
            strings.repeat("*", int(type.pointer_info.count)),
        )
        if type.pointer_info.read_only {
            append(&var_point_slot, "const")
        }
    }

    for arr in type.array_info {
        append(&array_slot, fmt.aprintf("[{}]", arr.size))
        if arr.pointer_info.count != 0 {
            append(&array_slot, ")")
            append(&array_prefix_slot, "(")
            append(
                &array_prefix_slot,
                strings.repeat("*", int(arr.pointer_info.count)),
            )
            if arr.pointer_info.read_only {
                append(&array_prefix_slot, "const ")
            }
        }
    }

    for tp in type_spec_slot {
        io.write_string(wd, tp) or_return
    }

    for vp in var_point_slot {
        io.write_string(wd, vp) or_return
    }
    io.write_rune(wd, ' ') or_return

    for ap in array_prefix_slot {
        io.write_string(wd, ap) or_return
    }

    io.write_string(wd, type_name_slot) or_return

    #reverse for a in array_slot {
        io.write_string(wd, a) or_return
    }

    return nil
}

write_type_specifier :: proc(
    wd: io.Writer,
    rn: runic.To,
    spec: runic.TypeSpecifier,
    types: om.OrderedMap(string, runic.Type),
    name: string = "",
) -> union {
        io.Error,
        errors.Error,
    } {
    switch s in spec {
    case runic.Builtin:
        switch s {
        case .Untyped:
            // TODO: Add Untyped as type
            return errors.Error(errors.message("Untyped"))
        case .Void:
            io.write_string(wd, "void") or_return
        case .RawPtr:
            io.write_string(wd, "void*") or_return
        case .SInt8:
            io.write_string(wd, "int8_t") or_return
        case .SInt16:
            io.write_string(wd, "int16_t") or_return
        case .SInt32:
            io.write_string(wd, "int32_t") or_return
        case .SInt64:
            io.write_string(wd, "int64_t") or_return
        case .SInt128:
            io.write_string(wd, "int128_t") or_return
        case .UInt8:
            io.write_string(wd, "uint8_t") or_return
        case .UInt16:
            io.write_string(wd, "uint16_t") or_return
        case .UInt32:
            io.write_string(wd, "uint32_t") or_return
        case .UInt64:
            io.write_string(wd, "uint64_t") or_return
        case .UInt128:
            io.write_string(wd, "uint128_t") or_return
        case .Float32:
            io.write_string(wd, "float") or_return
        case .Float64:
            io.write_string(wd, "double") or_return
        case .Float128:
            io.write_string(wd, "long double") or_return
        case .String:
            io.write_string(wd, "char*") or_return
        case .Bool8:
            io.write_string(wd, "_Bool") or_return
        case .Bool16:
            io.write_string(wd, "uint16_t") or_return
        case .Bool32:
            io.write_string(wd, "uint32_t") or_return
        case .Bool64:
            io.write_string(wd, "uint64_t") or_return
        }
    case runic.Struct:
        io.write_string(wd, "struct ") or_return
        if len(name) != 0 do io.write_string(wd, name) or_return
        io.write_string(wd, " {\n") or_return
        for m in s.members {
            errors.wrap(
                write_variable(wd, rn, m.name, m.type, types),
            ) or_return
            io.write_string(wd, ";\n") or_return
        }
        io.write_rune(wd, '}') or_return
    case runic.Enum:
        if s.type == .SInt32 {
            io.write_string(wd, "enum ") or_return
            if len(name) != 0 do io.write_string(wd, name) or_return
            io.write_string(wd, " {\n") or_return
            for e in s.entries {
                io.write_string(wd, e.name) or_return
                if e.value != nil {
                    io.write_string(wd, " = ") or_return
                    switch ev in e.value {
                    case i64:
                        io.write_i64(wd, ev) or_return
                    case string:
                        io.write_string(wd, ev) or_return
                    }
                }
                io.write_string(wd, ",\n") or_return
            }
            io.write_rune(wd, '}') or_return
        } else {
            for e, idx in s.entries {
                io.write_string(wd, "#define ") or_return
                io.write_string(wd, e.name) or_return
                io.write_string(wd, " ((") or_return
                if len(name) != 0 {
                    io.write_string(wd, name) or_return
                } else {
                    write_type_specifier(wd, rn, s.type, types) or_return
                }
                io.write_rune(wd, ')') or_return
                switch ev in e.value {
                case i64:
                    io.write_i64(wd, ev) or_return
                case string:
                    io.write_rune(wd, '(') or_return
                    io.write_string(wd, ev) or_return
                    io.write_rune(wd, ')') or_return
                }
                io.write_rune(wd, ')') or_return
                if idx != len(s.entries) - 1 {
                    io.write_rune(wd, '\n') or_return
                }
            }
        }
    case runic.Union:
        io.write_string(wd, "union ") or_return
        if len(name) != 0 do io.write_string(wd, name) or_return
        io.write_string(wd, " {\n") or_return
        for m in s.members {
            errors.wrap(
                write_variable(wd, rn, m.name, m.type, types),
            ) or_return
            io.write_string(wd, ";\n") or_return
        }
        io.write_rune(wd, '}') or_return
    case string:
        if type, ok := om.get(types, s); ok {
            #partial switch e in type.spec {
            case runic.Struct:
                io.write_string(wd, "struct ") or_return
            case runic.Union:
                io.write_string(wd, "union ") or_return
            case runic.Enum:
                if e.type == .SInt32 do io.write_string(wd, "enum ") or_return
            }
        }

        io.write_string(wd, s) or_return
    case runic.Unknown:
        io.write_string(wd, "void") or_return
    case runic.FunctionPointer:
        return errors.Error(errors.message("unreachable"))
    case runic.ExternType:
        return errors.Error(
            errors.message("TODO: extern types in to c codegen"),
        )
    }
    return nil
}

write_function_parameters :: proc(
    wd: io.Writer,
    rn: runic.To,
    params: [dynamic]runic.Member,
    variadic: bool,
    types: om.OrderedMap(string, runic.Type),
) -> union {
        io.Error,
        errors.Error,
    } {
    io.write_rune(wd, '(') or_return

    for param, idx in params {
        errors.wrap(
            write_variable(wd, rn, param.name, param.type, types),
        ) or_return

        if idx != len(params) - 1 || variadic {
            io.write_string(wd, ", ") or_return
        }
    }

    if variadic {
        io.write_string(wd, "...") or_return
    }

    io.write_rune(wd, ')')

    return nil
}

