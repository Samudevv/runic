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
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

generate_bindings_from_runestone :: proc(
    rs: runic.Runestone,
    rn: runic.To,
    wd: io.Writer,
) -> union {
        io.Error,
        errors.Error,
    } {

    // TODO: externs
    generate_bindings_for_constants(wd, rs, rn) or_return
    generate_bindings_for_types(wd, rs, rn) or_return
    generate_bindings_for_symbols(wd, rs, rn) or_return

    return nil
}

generate_bindings_from_runecross :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    wd: io.Writer,
) -> (
    err: union {
        io.Error,
        errors.Error,
    },
) {
    io.write_string(wd, "#pragma once\n\n") or_return
    io.write_string(wd, "#include <stddef.h>\n") or_return
    io.write_string(wd, "#include <stdint.h>\n") or_return
    io.write_rune(wd, '\n') or_return

    // Generate macros for platforms
    oses: [dynamic]runic.OS
    arches: [dynamic]runic.Architecture

    for entry in rc.cross {
        for plat in entry.plats {
            if plat.os != .Any && !slice.contains(oses[:], plat.os) {
                append(&oses, plat.os)
            }
            if plat.arch != .Any && !slice.contains(arches[:], plat.arch) {
                append(&arches, plat.arch)
            }
        }
    }

    for os in oses {
        io.write_string(wd, "#define ") or_return
        io.write_string(wd, os_macro(os)) or_return
        io.write_rune(wd, ' ') or_return
        switch os {
        case .Linux:
            io.write_string(
                wd,
                "(defined(__linux__) || defined(__linux) || defined(linux))\n",
            ) or_return
        case .Windows:
            io.write_string(
                wd,
                "(defined(_WIN32) || defined(_WIN16) || defined(_WIN64))\n",
            ) or_return
        case .Macos:
            io.write_string(
                wd,
                "(defined(__APPLE__) && (defined(macintosh) || defined(Macintosh) || defined(__MACH__)))\n",
            ) or_return
        case .BSD:
            io.write_string(
                wd,
                "(defined(__FreeBSD__) || defined(__FreeBSD_kernel__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__bsdi__) || defined(__DragonFly__) || defined(_SYSTYPE_BSD) || defined(BSD))\n",
            ) or_return
        case .Any:
            panic("unreachable")
        }
    }

    for arch in arches {
        io.write_string(wd, "#define ") or_return
        io.write_string(wd, arch_macro(arch)) or_return
        io.write_rune(wd, ' ') or_return

        switch arch {
        case .x86_64:
            io.write_string(
                wd,
                "(defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64))\n",
            ) or_return
        case .arm64:
            io.write_string(
                wd,
                "(defined(__arm__) && defined(__aarch64__))\n",
            ) or_return
        case .x86:
            io.write_string(
                wd,
                "(defined(i386) || defined(__i386__) || defined(__i386) || defined(__i486__) || defined(__i586) || defined(__i686__))\n",
            ) or_return
        case .arm32:
            io.write_string(
                wd,
                "defined(__arm__) && !defined(__aarch64)\n",
            ) or_return
        case .Any:
            panic("unreachable")
        }
    }

    if len(oses) != 0 || len(arches) != 0 {
        io.write_rune(wd, '\n') or_return
    }

    delete(oses)
    delete(arches)

    // Constants
    #reverse for entry in rc.cross {
        if om.length(entry.constants) == 0 do continue

        plats_defined(wd, entry.plats) or_return

        generate_bindings_for_constants(wd, entry, rn) or_return

        endif(wd, entry.plats) or_return
    }

    // TODO: externs

    // Types
    #reverse for entry in rc.cross {
        if om.length(entry.types) == 0 do continue

        plats_defined(wd, entry.plats) or_return

        generate_bindings_for_types(wd, entry, rn) or_return

        endif(wd, entry.plats) or_return
    }

    // Symbols
    #reverse for entry in rc.cross {
        if om.length(entry.symbols) == 0 do continue

        plats_defined(wd, entry.plats) or_return

        generate_bindings_for_symbols(wd, entry, rn) or_return

        endif(wd, entry.plats) or_return
    }

    return
}

generate_bindings :: proc {
    generate_bindings_from_runestone,
    generate_bindings_from_runecross,
}

generate_bindings_for_constants :: proc(
    wd: io.Writer,
    rs: runic.Runestone,
    rn: runic.To,
) -> union {
        io.Error,
        errors.Error,
    } {
    arena: runtime.Arena
    errors.wrap(runtime.arena_init(&arena, 0, context.allocator)) or_return
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

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

    return nil
}

generate_bindings_for_types :: proc(
    wd: io.Writer,
    rs: runic.Runestone,
    rn: runic.To,
) -> union {
        io.Error,
        errors.Error,
    } {
    arena: runtime.Arena
    errors.wrap(runtime.arena_init(&arena, 0, context.allocator)) or_return
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

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

        io.write_string(wd, "typedef ") or_return
        errors.wrap(write_variable(wd, rn, name, type, rs.types)) or_return

        io.write_string(wd, ";\n") or_return
    }

    if om.length(rs.types) != 0 {
        io.write_rune(wd, '\n') or_return
    }

    return nil
}

generate_bindings_for_symbols :: proc(
    wd: io.Writer,
    rs: runic.Runestone,
    rn: runic.To,
) -> union {
        io.Error,
        errors.Error,
    } {
    arena: runtime.Arena
    errors.wrap(runtime.arena_init(&arena, 0, context.allocator)) or_return
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

    aliases, functions: strings.Builder
    strings.builder_init(&aliases)
    strings.builder_init(&functions)
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

os_macro :: #force_inline proc(os: runic.OS) -> string {
    switch os {
    case .Linux:
        return "OS_LINUX"
    case .Windows:
        return "OS_WINDOWS"
    case .Macos:
        return "OS_MACOS"
    case .BSD:
        return "OS_BSD"
    case .Any:
        return "OS_ANY"
    }

    panic("unreachable")
}

arch_macro :: #force_inline proc(arch: runic.Architecture) -> string {
    switch arch {
    case .x86_64:
        return "ARCH_X86_64"
    case .arm64:
        return "ARCH_ARM64"
    case .x86:
        return "ARCH_X86"
    case .arm32:
        return "ARCH_ARM32"
    case .Any:
        return "ARCH_ANY"
    }

    panic("unreachable")
}

plats_defined :: proc(wd: io.Writer, plats: []runic.Platform) -> io.Error {
    if len(plats) == 1 && plats[0].os == .Any && plats[0].arch == .Any do return .None

    io.write_string(wd, "#if ") or_return

    for plat, idx in plats {
        if plat.os == .Any && plat.arch == .Any {
            io.write_rune(wd, '1') or_return
            continue
        }

        if plat.os != .Any && plat.arch != .Any do io.write_rune(wd, '(') or_return

        if plat.os != .Any {
            io.write_string(wd, os_macro(plat.os)) or_return
        }

        if plat.os != .Any && plat.arch != .Any do io.write_string(wd, " && ") or_return

        if plat.arch != .Any {
            io.write_string(wd, arch_macro(plat.arch)) or_return
        }

        if plat.os != .Any && plat.arch != .Any do io.write_rune(wd, ')') or_return
        if idx != len(plats) - 1 {
            io.write_string(wd, " || ") or_return
        }
    }

    io.write_rune(wd, '\n') or_return

    return .None
}

endif :: #force_inline proc(
    wd: io.Writer,
    plats: []runic.Platform,
) -> io.Error {
    if len(plats) == 1 && plats[0].os == .Any && plats[0].arch == .Any do return .None

    _, err := io.write_string(wd, "#endif\n")
    return err
}

C_RESERVED :: []string {
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

