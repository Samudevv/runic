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

package odin_codegen

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

generate_bindings :: proc(
    plat: runic.Platform,
    rs: runic.Runestone,
    rn: runic.To,
    wd: io.Writer,
) -> io.Error {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    io.write_string(wd, "//+build ") or_return
    switch plat.os {
    case .Linux:
        io.write_string(wd, "linux ") or_return
    case .Windows:
        io.write_string(wd, "windows ") or_return
    }
    switch plat.arch {
    case .x86_64:
        io.write_string(wd, "amd64") or_return
    case .arm64:
        io.write_string(wd, "arm64") or_return
    }

    io.write_string(wd, "\npackage ") or_return

    // Make sure that package name is not invalid
    package_name := rn.package_name
    ODIN_PACKAGE_INVALID :: [?]string{" ", "-", "?", "&", "|", "/", "\\"} // NOTE: more are invalid, but let's stop here
    for str in ODIN_PACKAGE_INVALID {
        package_name, _ = strings.replace(
            package_name,
            str,
            "_",
            -1,
            arena_alloc,
        )
    }
    if slice.contains(ODIN_RESERVED, package_name) {
        package_name = strings.concatenate({package_name, "_"}, arena_alloc)
    }


    io.write_string(wd, package_name) or_return
    io.write_string(wd, "\n\n") or_return

    for entry in rs.constants.data {
        name, const := entry.key, entry.value
        name = runic.process_constant_name(
            name,
            rn,
            reserved = ODIN_RESERVED,
            allocator = arena_alloc,
        )

        io.write_string(wd, name) or_return
        io.write_string(wd, " :: ") or_return
        switch value in const.value {
        case i64:
            io.write_i64(wd, value) or_return
        case f64:
            io.write_f64(wd, value) or_return
        case string:
            if len(value) == 0 {
                io.write_string(wd, "\"\"")
            } else {
                io.write_rune(wd, '`') or_return
                io.write_string(wd, value) or_return
                io.write_rune(wd, '`') or_return
            }
        }
        io.write_rune(wd, '\n') or_return
    }

    if om.length(rs.constants) != 0 do io.write_rune(wd, '\n') or_return

    for ty, idx in rs.anon_types {
        anon: strings.Builder
        defer strings.builder_destroy(&anon)
        as := strings.to_stream(&anon)

        type_name := fmt.aprintf("Anon{}", idx, allocator = arena_alloc)
        type_name = runic.process_type_name(
            type_name,
            rn,
            allocator = arena_alloc,
        )
        io.write_string(as, type_name) or_return
        io.write_string(as, " :: ") or_return
        type_err := write_type(as, type_name, runic.Type{spec = ty}, rn)
        if type_err != nil {
            fmt.eprintfln("{}: {}", type_name, type_err)
            continue
        }
        io.write_string(as, "\n") or_return

        io.write_string(wd, strings.to_string(anon)) or_return
    }

    if len(rs.anon_types) != 0 do io.write_rune(wd, '\n') or_return

    for entry in rs.types.data {
        type_build: strings.Builder
        defer strings.builder_destroy(&type_build)
        ts := strings.to_stream(&type_build)

        name, ty := entry.key, entry.value
        name = runic.process_type_name(
            name,
            rn,
            reserved = ODIN_RESERVED,
            allocator = arena_alloc,
        )

        io.write_string(ts, name) or_return
        io.write_string(ts, " :: ") or_return
        type_err := write_type(ts, name, ty, rn)
        if type_err != nil {
            fmt.eprintfln("{}: {}", name, type_err)
            continue
        }
        io.write_string(wd, strings.to_string(type_build)) or_return
        io.write_string(wd, "\n") or_return
    }

    if om.length(rs.types) != 0 do io.write_rune(wd, '\n') or_return

    if rs.lib_shared != nil && rs.lib_static != nil {
        static_switch := rn.static_switch
        if len(static_switch) == 0 {
            static_switch = strings.concatenate(
                {strings.to_upper(package_name, arena_alloc), "_STATIC"},
                arena_alloc,
            )
        }

        io.write_string(wd, "when #config(") or_return
        io.write_string(wd, static_switch) or_return
        io.write_string(wd, ", false) {\n    ") or_return

        fmt.wprintf(
            wd,
            "foreign import {}_runic \"system:{}\"\n",
            package_name,
            rs.lib_static,
        )

        io.write_string(wd, "} else {\n    ") or_return

        lib_shared: string = ---
        switch plat.os {
        case .Linux:
            lib_shared = rs.lib_shared.?
            if strings.has_prefix(lib_shared, "lib") &&
               strings.has_suffix(lib_shared, ".so") {
                lib_shared = strings.trim_prefix(lib_shared, "lib")
                lib_shared = strings.trim_suffix(lib_shared, ".so")
            }
        case .Windows:
            lib_shared = rs.lib_shared.?
        }

        fmt.wprintf(
            wd,
            "foreign import {}_runic \"system:{}\"\n",
            package_name,
            lib_shared,
        )

        io.write_string(wd, "}\n\n") or_return
    } else {
        fmt.wprintf(wd, "foreign import {}_runic \"system:", package_name)

        switch plat.os {
        case .Linux:
            if shared, ok := rs.lib_shared.?; ok {
                if strings.has_prefix(shared, "lib") &&
                   strings.has_suffix(shared, ".so") {
                    io.write_string(
                        wd,
                        strings.trim_suffix(
                            strings.trim_prefix(shared, "lib"),
                            ".so",
                        ),
                    ) or_return
                } else {
                    io.write_string(wd, shared) or_return
                }
            } else {
                io.write_string(wd, rs.lib_static.?) or_return
            }
        case .Windows:
            if shared, ok := rs.lib_shared.?; ok {
                io.write_string(wd, shared) or_return
            } else {
                io.write_string(wd, rs.lib_static.?) or_return
            }
        }

        io.write_string(wd, "\"\n\n") or_return
    }

    io.write_string(wd, "@(default_calling_convention = \"c\")\n") or_return
    fmt.wprintf(wd, "foreign {}_runic {{\n", package_name)

    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        fmt.wprintf(
            wd,
            "    @(link_name = \"{}\")\n",
            sym.remap.? or_else name,
        )
        io.write_string(wd, "    ") or_return

        switch value in sym.value {
        case runic.Type:
            sym_build: strings.Builder
            defer strings.builder_destroy(&sym_build)
            ss := strings.to_stream(&sym_build)

            name = runic.process_variable_name(
                name,
                rn,
                reserved = ODIN_RESERVED,
                allocator = arena_alloc,
            )
            io.write_string(ss, name) or_return
            io.write_string(ss, ": ") or_return
            type_err := write_type(ss, name, value, rn)
            if type_err != nil {
                fmt.eprintfln("{}: {}", name, type_err)
                io.write_string(wd, name) or_return
                io.write_string(wd, " :: nil\n\n") or_return
                continue
            }
            io.write_string(wd, strings.to_string(sym_build))
        case runic.Function:
            name = runic.process_function_name(
                name,
                rn,
                reserved = ODIN_RESERVED,
                allocator = arena_alloc,
            )
            io.write_string(wd, name) or_return
            io.write_string(wd, " :: ") or_return
            proc_err := write_procedure(wd, value, rn, nil)
            if proc_err != nil {
                fmt.eprintfln("{}: {}", name, proc_err)
                io.write_string(wd, "nil\n\n") or_return
                continue
            }
            io.write_string(wd, " ---") or_return
        }
        io.write_string(wd, "\n\n") or_return
    }

    io.write_string(wd, "}\n\n") or_return

    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value

        switch _ in sym.value {
        case runic.Type:
            name = runic.process_variable_name(
                name,
                rn,
                reserved = ODIN_RESERVED,
                allocator = arena_alloc,
            )
        case runic.Function:
            name = runic.process_function_name(
                name,
                rn,
                reserved = ODIN_RESERVED,
                allocator = arena_alloc,
            )
        }

        for alias in sym.aliases {
            switch sym_value in sym.value {
            case runic.Type:
                alias_p := runic.process_variable_name(
                    alias,
                    rn,
                    reserved = ODIN_RESERVED,
                    allocator = arena_alloc,
                )

                io.write_string(wd, alias_p) or_return
                if func_ptr, ok := recursive_get_pure_func_ptr(
                    sym_value,
                    rs.types,
                ); ok {
                    io.write_string(wd, " :: #force_inline ")
                    proc_err := write_procedure(
                        wd,
                        func_ptr^,
                        rn,
                        "contextless",
                    )
                    if proc_err != nil {
                        fmt.eprintfln("{} ({}): {}", alias_p, name, proc_err)
                        io.write_string(wd, "proc \"contextless\" () {}\n\n")
                        continue
                    }
                    io.write_string(wd, " {\n") or_return

                    if b, b_ok := func_ptr.return_type.spec.(runic.Builtin);
                       b_ok && b == .Void {
                        io.write_string(wd, "    ") or_return
                    } else {
                        io.write_string(wd, "    return ") or_return
                    }

                    io.write_string(wd, name) or_return
                    io.write_rune(wd, '(') or_return
                    for p, p_idx in func_ptr.parameters {
                        p_name := p.name
                        if slice.contains(ODIN_RESERVED, p_name) {
                            p_name = strings.concatenate(
                                {p_name, "_"},
                                arena_alloc,
                            )
                        }
                        io.write_string(wd, p_name) or_return
                        if p_idx != len(func_ptr.parameters) - 1 {
                            io.write_string(wd, ", ") or_return
                        }
                    }
                    io.write_string(wd, ")\n}") or_return
                } else {
                    sym_build: strings.Builder
                    defer strings.builder_destroy(&sym_build)
                    ss := strings.to_stream(&sym_build)

                    io.write_string(
                        ss,
                        " :: #force_inline proc \"contextless\" () -> ",
                    ) or_return
                    type_err := write_type(ss, name, sym_value, rn)
                    if type_err != nil {
                        fmt.eprintfln("{}: {}", name, type_err)
                        io.write_string(wd, " :: nil\n\n") or_return
                        continue
                    }
                    io.write_string(ss, " {\n    return ") or_return
                    io.write_string(ss, name) or_return
                    io.write_string(ss, "\n}") or_return
                    io.write_string(wd, strings.to_string(sym_build)) or_return
                }
            case runic.Function:
                alias_p := runic.process_function_name(
                    alias,
                    rn,
                    reserved = ODIN_RESERVED,
                    allocator = arena_alloc,
                )

                io.write_string(wd, alias_p) or_return
                io.write_string(wd, " :: ") or_return
                io.write_string(wd, name) or_return
            }
            io.write_string(wd, "\n\n") or_return
        }
    }

    return .None
}

write_procedure :: proc(
    wd: io.Writer,
    fc: runic.Function,
    rn: runic.To,
    calling_convention: Maybe(string) = "c",
) -> union {
        io.Error,
        errors.Error,
    } {

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    proc_build: strings.Builder
    defer strings.builder_destroy(&proc_build)
    ps := strings.to_stream(&proc_build)

    io.write_string(ps, "proc") or_return
    if cc, ok := calling_convention.?; ok {
        io.write_string(ps, " \"") or_return
        io.write_string(ps, cc) or_return
        io.write_string(ps, "\" ") or_return
    }
    io.write_string(ps, "(") or_return

    for p, idx in fc.parameters {
        p_name := p.name
        if slice.contains(ODIN_RESERVED, p_name) {
            p_name = strings.concatenate({p_name, "_"}, arena_alloc)
        }
        io.write_string(ps, p_name) or_return
        io.write_string(ps, ": ") or_return
        write_type(ps, p_name, p.type, rn) or_return
        if idx != len(fc.parameters) - 1 {
            io.write_string(ps, ", ") or_return
        }
    }

    io.write_rune(ps, ')') or_return

    if b, ok := fc.return_type.spec.(runic.Builtin); ok && b == .Void {
        io.write_string(wd, strings.to_string(proc_build)) or_return
        return nil
    }

    io.write_string(ps, " -> ") or_return
    write_type(ps, "", fc.return_type, rn) or_return

    io.write_string(wd, strings.to_string(proc_build)) or_return

    return nil
}

write_type :: proc(
    wd: io.Writer,
    var_name: string,
    ty: runic.Type,
    rn: runic.To,
) -> union {
        io.Error,
        errors.Error,
    } {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    pointer_count := int(ty.pointer_info.count)

    if u, ok := ty.spec.(runic.Unknown); ok {
        if pointer_count >= 1 {
            pointer_count -= 1
        } else {
            return errors.Error(errors.message("type \"{}\" is unknown", u))
        }
    }

    is_multi_pointer: bool

    switch rn.detect.multi_pointer {
    case "auto":
        if pointer_count >= 1 &&
           len(var_name) > 1 &&
           strings.has_suffix(var_name, "s") {
            is_multi_pointer = true
            pointer_count -= 1
        }
    }

    #reverse for a in ty.array_info {
        pointer, err := strings.repeat("^", int(ty.pointer_info.count))
        if err != .None {
            return errors.Error(
                errors.message("failed to create pointer string for array"),
            )
        }
        if len(pointer) != 0 {
            io.write_string(wd, pointer) or_return
            delete(pointer)
        }

        io.write_rune(wd, '[') or_return
        if a.size == nil {
            io.write_rune(wd, '^') or_return
        } else {
            fmt.wprint(wd, a.size)
        }
        io.write_rune(wd, ']') or_return
    }

    pointer, err := strings.repeat("^", pointer_count)
    if err != .None do return errors.Error(errors.message("failed to create pointer string"))

    if len(pointer) != 0 {
        io.write_string(wd, pointer) or_return
        delete(pointer)
    }

    if is_multi_pointer {
        io.write_string(wd, "[^]") or_return
    }

    switch spec in ty.spec {
    case runic.Builtin:
        write_builtin_type(wd, spec) or_return
    case runic.Struct:
        io.write_string(wd, "struct {\n") or_return
        for m in spec.members {
            m_name := m.name
            if slice.contains(ODIN_RESERVED, m_name) {
                m_name = strings.concatenate({m_name, "_"}, arena_alloc)
            }

            io.write_string(wd, "    ") or_return
            io.write_string(wd, m_name) or_return
            io.write_string(wd, ": ") or_return
            write_type(wd, m_name, m.type, rn) or_return
            io.write_string(wd, ",\n") or_return
        }
        io.write_rune(wd, '}') or_return
    case runic.Enum:
        io.write_string(wd, "enum ") or_return
        write_builtin_type(wd, spec.type) or_return
        io.write_string(wd, " {") or_return
        for e in spec.entries {
            e_name := runic.process_constant_name(
                e.name,
                rn,
                reserved = ODIN_RESERVED,
                allocator = arena_alloc,
            )

            io.write_string(wd, e_name) or_return
            io.write_string(wd, " = ") or_return
            fmt.wprintf(wd, "{}, ", e.value)
        }
        io.write_rune(wd, '}') or_return
    case runic.Union:
        io.write_string(wd, "struct #raw_union {") or_return
        for m in spec.members {
            m_name := m.name
            if slice.contains(ODIN_RESERVED, m_name) {
                m_name = strings.concatenate({m_name, "_"}, arena_alloc)
            }

            io.write_string(wd, m_name) or_return
            io.write_string(wd, ": ") or_return
            write_type(wd, m_name, m.type, rn) or_return
            io.write_string(wd, ", ") or_return
        }
        io.write_rune(wd, '}') or_return
    case string:
        processed := runic.process_type_name(
            spec,
            rn,
            reserved = ODIN_RESERVED,
            allocator = arena_alloc,
        )

        io.write_string(wd, processed) or_return
    case runic.Anon:
        anon_name := fmt.aprintf("Anon{}", spec, allocator = arena_alloc)
        anon_name = runic.process_type_name(
            anon_name,
            rn,
            allocator = arena_alloc,
        )
        io.write_string(wd, anon_name) or_return
    case runic.Unknown:
        io.write_string(wd, "rawptr") or_return
    case runic.FunctionPointer:
        io.write_string(wd, "#type ") or_return
        write_procedure(wd, spec^, rn) or_return
    }

    return nil
}

write_builtin_type :: proc(wd: io.Writer, ty: runic.Builtin) -> io.Error {
    switch ty {
    case .Untyped, .Void:
        io.write_string(wd, "^^^rawptr") or_return
    case .RawPtr:
        io.write_string(wd, "rawptr") or_return
    case .SInt8:
        io.write_string(wd, "i8") or_return
    case .SInt16:
        io.write_string(wd, "i16") or_return
    case .SInt32:
        io.write_string(wd, "i32") or_return
    case .SInt64:
        io.write_string(wd, "i64") or_return
    case .SInt128:
        io.write_string(wd, "i128") or_return
    case .UInt8:
        io.write_string(wd, "u8") or_return
    case .UInt16:
        io.write_string(wd, "u16") or_return
    case .UInt32:
        io.write_string(wd, "u32") or_return
    case .UInt64:
        io.write_string(wd, "u64") or_return
    case .UInt128:
        io.write_string(wd, "u128") or_return
    case .Float32:
        io.write_string(wd, "f32") or_return
    case .Float64:
        io.write_string(wd, "f64") or_return
    case .Float128:
        io.write_string(wd, "[16]byte") or_return
    case .String:
        io.write_string(wd, "cstring") or_return
    case .Bool8:
        io.write_string(wd, "b8") or_return
    case .Bool16:
        io.write_string(wd, "b16") or_return
    case .Bool32:
        io.write_string(wd, "b32") or_return
    case .Bool64:
        io.write_string(wd, "b64") or_return
    }

    return .None
}

// A "pure" function pointer is a variable that is not a pointer to or an array of a function pointer
recursive_get_pure_func_ptr :: proc(
    _type: runic.Type,
    types: om.OrderedMap(string, runic.Type),
) -> (
    func_ptr: runic.FunctionPointer,
    ok: bool,
) {
    type := _type
    for {
        if type.pointer_info.count != 0 || len(type.array_info) != 0 {
            return
        }

        #partial switch s in type.spec {
        case runic.FunctionPointer:
            func_ptr = s
            ok = true
            return
        case string:
            t_ok: bool = ---
            type, t_ok = om.get(types, s)
            if !t_ok do return
        case:
            return
        }
    }

    return
}

ODIN_RESERVED :: []string {
    "int",
    "uint",
    "i8",
    "i16",
    "i32",
    "i64",
    "byte",
    "u8",
    "u16",
    "u32",
    "u64",
    "uintptr",
    "f16",
    "f32",
    "f64",
    "rune",
    "cstring",
    "rawptr",
    "bool",
    "b8",
    "b16",
    "b32",
    "b64",
    "i128",
    "u128",
    "i16le",
    "i32le",
    "i64le",
    "i128le",
    "u16le",
    "u32le",
    "u64le",
    "u128le",
    "i16be",
    "i32be",
    "i64be",
    "i128be",
    "u16be",
    "u32be",
    "u64be",
    "u128be",
    "f16le",
    "f32le",
    "f64le",
    "f16be",
    "f32be",
    "f64be",
    "complex32",
    "complex64",
    "complex128",
    "quaternion64",
    "quaternion128",
    "quaternion256",
    "string",
    "typeid",
    "any",
    "context",
    "struct",
    "enum",
    "union",
    "map",
    "dynamic",
    "bit_set",
    "bit_field",
    "matrix",
    "using",
    "or_else",
    "or_return",
    "package",
    "proc",
    "foreign",
    "nil",
    "for",
    "in",
    "if",
    "switch",
    "defer",
    "when",
    "else",
    "continnue",
    "fallthrough",
    "return",
    "break",
    "import",
}
