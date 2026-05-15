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
package golang_codegen

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

@(private)
purego_template :: #load("./go/purego_template.go", string)

purego_generate_bindings_from_runestone :: proc(
    rs: runic.PlatformRunestone,
    rc_idx: int,
    rn: runic.To,
    rc: runic.Runecross,
    wd: io.Writer,
) -> union {
        io.Error,
        errors.Error,
    } {

    build_constraints := purego_generate_build_constraints(rs.plats)
    package_name := purego_generate_package_name(rn)
    imports := purego_generate_imports(rs, rn, false)
    types := purego_generate_types(rs, rn)
    func_sym_decls := purego_generate_function_symbol_declarations(rs, rn)
    type_sym_getters := purego_generate_type_symbol_getters(rs, rn)
    type_sym_setters := purego_generate_type_symbol_setters(rs, rn)
    type_sym_pointers := purego_generate_type_symbol_pointers(rs, rn)
    symbol_registrations := purego_generate_symbol_registrations(rs, rn)
    symbol_reg_var_name := purego_generate_symbol_registration_variable_name(
        rs.plats,
    )

    defer if len(build_constraints) != 0 do delete(build_constraints)
    defer delete(package_name)
    defer delete(imports)
    defer delete(types)
    defer delete(func_sym_decls)
    defer delete(type_sym_getters)
    defer delete(type_sym_setters)
    defer delete(type_sym_pointers)
    defer delete(symbol_registrations)
    defer delete(symbol_reg_var_name)

    if len(build_constraints) != 0 {
        io.write_string(wd, build_constraints) or_return
        io.write_rune(wd, '\n') or_return
    }
    io.write_string(wd, package_name) or_return
    io.write_string(wd, "\n\n") or_return

    if len(imports) != 0 {
        io.write_string(wd, imports) or_return
        io.write_string(wd, "\n\n") or_return
    }

    if len(types) != 0 {
        io.write_string(wd, types) or_return
        io.write_string(wd, "\n\n") or_return
    }

    if len(func_sym_decls) != 0 {
        io.write_string(wd, "var (\n") or_return
        io.write_string(wd, func_sym_decls) or_return
        io.write_string(wd, "\n)\n\n") or_return
    }

    if len(type_sym_getters) != 0 {
        io.write_string(wd, type_sym_getters) or_return
        io.write_string(wd, "\n") or_return
    }
    if len(type_sym_setters) != 0 {
        io.write_string(wd, type_sym_setters) or_return
        io.write_string(wd, "\n") or_return
    }
    if len(type_sym_pointers) != 0 {
        io.write_string(wd, type_sym_pointers) or_return
        io.write_string(wd, "\n") or_return
    }

    io.write_string(wd, "var (\n") or_return
    io.write_rune(wd, '\t') or_return
    io.write_string(wd, symbol_reg_var_name) or_return
    io.write_string(wd, " = [][2]any{\n") or_return
    io.write_string(wd, symbol_registrations) or_return
    io.write_string(wd, "\n\t}\n") or_return


    if len(rc.cross) >= 2 {
        io.write_rune(wd, '\n') or_return
    }

    for rc_rs, idx in rc.cross {
        if idx == rc_idx || idx == 0 do continue

        reg_var_name := purego_generate_symbol_registration_variable_name(
            rc_rs.plats,
        )
        defer delete(reg_var_name)

        io.write_rune(wd, '\t') or_return
        io.write_string(wd, reg_var_name) or_return
        io.write_string(wd, " = [][2]any{}\n") or_return
    }

    io.write_string(wd, ")\n") or_return

    return nil
}

@(private)
purego_generate_build_constraints :: proc(plats: []runic.Platform) -> string {
    if len(plats) == 0 do return ""

    expressions := make([dynamic]string)
    defer delete(expressions)
    defer for e in expressions do delete(e)

    for plat in plats {
        if plat.os == .Any && plat.arch == .Any do continue

        buf: strings.Builder
        strings.builder_init(&buf)

        if plat.os != .Any && plat.arch != .Any {
            strings.write_rune(&buf, '(')
        }

        if plat.os != .Any {
            strings.write_string(&buf, runic_os_to_goos(plat.os))
        }

        if plat.arch != .Any {
            if plat.os != .Any {
                strings.write_string(&buf, " && ")
            }
            strings.write_string(&buf, runic_arch_to_goarch(plat.arch))
        }

        if plat.os != .Any && plat.arch != .Any {
            strings.write_rune(&buf, ')')
        }

        append(&expressions, strings.to_string(buf))
    }

    if len(expressions) == 0 do return ""

    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "//go:build ")

    for exp, idx in expressions {
        strings.write_string(&buf, exp)
        if idx != len(expressions) - 1 {
            strings.write_string(&buf, " || ")
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_package_name :: proc(rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "package ")
    strings.write_string(&buf, rn.package_name)

    return strings.to_string(buf)
}

@(private)
purego_generate_imports :: proc(
    rs: runic.Runestone,
    rn: runic.To,
    is_main_file: bool,
) -> string {
    uses_unsafe: bool = is_main_file

    rs_externs := make([dynamic]string)
    defer delete(rs_externs)

    for entry in rs.externs.data {
        extern := entry.value

        if !slice.contains(rs_externs[:], extern.source) {
            append(&rs_externs, extern.source)
        }

        if !uses_unsafe {
            if purego_uses_unsafe(extern) {
                uses_unsafe = true
            }
        }
    }

    if !uses_unsafe {
        for entry in rs.symbols.data {
            sym := entry.value
            if _, is_type := sym.value.(runic.Type); is_type {
                uses_unsafe = true
                break
            }

            if purego_uses_unsafe(sym) {
                uses_unsafe = true
                break
            }
        }
    }

    if !uses_unsafe {
        for entry in rs.types.data {
            typ := entry.value

            if purego_uses_unsafe(typ) {
                uses_unsafe = true
                break
            }
        }
    }

    if !uses_unsafe {
        for entry in rs.constants.data {
            const := entry.value

            if purego_uses_unsafe(const.type) {
                uses_unsafe = true
                break
            }
        }
    }

    imports := make([dynamic]string)
    defer delete(imports)

    if is_main_file {
        append(&imports, "errors")
        append(&imports, "runtime")
        append(&imports, "unsafe")
        append(&imports, "github.com/ebitengine/purego")
    } else if uses_unsafe {
        append(&imports, "unsafe")
    }

    if len(rs_externs) != 0 {
        for extern in rs_externs {
            if source, source_ok := rn.extern.sources[extern]; source_ok {
                if !slice.contains(imports[:], source) {
                    append(&imports, source)
                }
            }
        }
    }

    slice.sort(imports[:])

    if len(imports) == 0 do return ""

    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "import (\n")

    for import_path in imports {
        name, package_import := purego_extern_package(import_path)

        strings.write_rune(&buf, '\t')

        if len(name) != 0 {
            strings.write_string(&buf, name)
            strings.write_rune(&buf, ' ')
        }

        strings.write_rune(&buf, '"')
        strings.write_string(&buf, package_import)
        strings.write_rune(&buf, '"')

        strings.write_rune(&buf, '\n')
    }

    strings.write_string(&buf, ")")

    return strings.to_string(buf)
}

@(private)
purego_generate_platforms_and_libraries :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    rune_file_path: string,
) -> string {
    platform_libraries := om.make(runic.Platform, string)
    defer om.delete(platform_libraries)

    allocated_strings := make([dynamic]string)
    defer delete(allocated_strings)
    defer for s in allocated_strings do delete(s)

    for entry in rc.cross {
        for plat in entry.plats {
            if !om.contains(platform_libraries, plat) {
                if shared, ok := entry.lib.shared.?; ok {
                    lib_file_path := shared

                    // If a relative path is specified for the library
                    // consider it to be relative to the rune file path
                    // (relative paths will be turned into absolute file paths in runic.parse_rune)
                    if runic.slashpath_is_abs(lib_file_path) {
                        rune_file_dir := os.dir(rune_file_path)
                        rel_lib_file_path, rel_ok :=
                            runic.slashpath_rel_to_filepath(
                                rune_file_dir,
                                lib_file_path,
                            )
                        if rel_ok {
                            lib_file_path = rel_lib_file_path
                            append(&allocated_strings, rel_lib_file_path)
                        }
                    }

                    om.insert(&platform_libraries, plat, lib_file_path)
                }
            }
        }
    }

    buf: strings.Builder
    strings.builder_init(&buf)

    for entry, idx in platform_libraries.data {
        plat, lib := entry.key, entry.value

        strings.write_string(&buf, "\t\t{\"")
        strings.write_string(&buf, runic_os_to_goos(plat.os))
        strings.write_string(&buf, "\", \"")
        strings.write_string(&buf, runic_arch_to_goarch(plat.arch))
        strings.write_string(&buf, "\"}: \"")
        strings.write_string(&buf, lib)
        strings.write_string(&buf, "\",")

        if idx != om.length(platform_libraries) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_function_symbol_declarations :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    has_funcs: bool
    last_func_idx: int

    for entry, idx in rs.symbols.data {
        sym := entry.value

        if _, is_func := sym.value.(runic.Function); is_func {
            has_funcs = true
            last_func_idx = idx
        }
    }

    if !has_funcs do return strings.to_string(buf)

    for entry, idx in rs.symbols.data {
        sym_name, sym := entry.key, entry.value

        if _, is_type := sym.value.(runic.Type); is_type do continue

        upper_sym_name, upper_sym_name_err := strings.to_pascal_case(sym_name)
        if upper_sym_name_err != .None do continue
        defer delete(upper_sym_name)

        strings.write_rune(&buf, '\t')
        strings.write_string(&buf, upper_sym_name)
        strings.write_rune(&buf, ' ')
        purego_write_symbol(&buf, sym, rs.externs, rn)

        if idx != last_func_idx {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_type_symbol_getters :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    has_types: bool

    for entry in rs.symbols.data {
        sym := entry.value
        if _, is_type := sym.value.(runic.Type); is_type {
            has_types = true
            break
        }
    }

    if !has_types do return strings.to_string(buf)

    for entry in rs.symbols.data {
        sym_name, sym := entry.key, entry.value

        if _, is_type := sym.value.(runic.Type); !is_type do continue

        upper_sym_name, upper_sym_name_err := strings.to_pascal_case(sym_name)
        if upper_sym_name_err != .None do continue
        defer delete(upper_sym_name)

        strings.write_string(&buf, "func ")
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, "() ")
        purego_write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, " {\n\treturn *(*")
        purego_write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ")(unsafe.Pointer(runicPtr")
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, "))\n}\n")
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_type_symbol_setters :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    has_types: bool

    for entry in rs.symbols.data {
        sym := entry.value
        if _, is_type := sym.value.(runic.Type); is_type {
            has_types = true
            break
        }
    }

    if !has_types do return strings.to_string(buf)

    for entry in rs.symbols.data {
        sym_name, sym := entry.key, entry.value

        if _, is_type := sym.value.(runic.Type); !is_type do continue

        upper_sym_name, upper_sym_name_err := strings.to_pascal_case(sym_name)
        if upper_sym_name_err != .None do continue
        defer delete(upper_sym_name)

        strings.write_string(&buf, "func Set")
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, "(value ")
        purego_write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ") {\n\t*(*")
        purego_write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ")(unsafe.Pointer(runicPtr")
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, ")) = value\n}\n")
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_type_symbol_pointers :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    has_types: bool

    for entry in rs.symbols.data {
        sym := entry.value
        if _, is_type := sym.value.(runic.Type); is_type {
            has_types = true
            break
        }
    }

    if !has_types do return strings.to_string(buf)

    strings.write_string(&buf, "var (\n")

    for entry in rs.symbols.data {
        sym_name, sym := entry.key, entry.value

        if _, is_type := sym.value.(runic.Type); !is_type do continue

        upper_sym_name, upper_sym_name_err := strings.to_pascal_case(sym_name)
        if upper_sym_name_err != .None do continue
        defer delete(upper_sym_name)

        strings.write_string(&buf, "\trunicPtr")
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, " uintptr\n")
    }

    strings.write_string(&buf, ")\n")

    return strings.to_string(buf)
}

@(private)
purego_write_symbol :: proc(
    buf: ^strings.Builder,
    sym: runic.Symbol,
    externs: om.OrderedMap(string, runic.Extern),
    rn: runic.To,
) {
    switch val in sym.value {
    case runic.Type:
        purego_write_type(buf, val, rn, externs, true)
    case runic.Function:
        purego_write_function(buf, val, rn, externs, true)
    }
}

@(private)
purego_write_type :: proc(
    buf: ^strings.Builder,
    typ: runic.Type,
    rn: runic.To,
    externs: om.OrderedMap(string, runic.Extern),
    string_able: bool,
) {
    for i := uint(0); i < typ.pointer_info.count; i += 1 {
        strings.write_rune(buf, '*')
    }

    for arr in typ.array_info {
        strings.write_rune(buf, '[')

        switch size in arr.size {
        case u64:
            strings.write_u64(buf, size, 10)
        case string:
            strings.write_string(buf, size)
        case:
        // nil
        }

        strings.write_rune(buf, ']')

        for i := uint(0); i < arr.pointer_info.count; i += 1 {
            strings.write_rune(buf, '*')
        }
    }

    purego_write_typespecifier(buf, typ.spec, rn, externs, string_able)
}

@(private)
purego_write_function :: proc(
    buf: ^strings.Builder,
    func: runic.Function,
    rn: runic.To,
    externs: om.OrderedMap(string, runic.Extern),
    string_able: bool,
) {
    strings.write_string(buf, "func(")

    for param, idx in func.parameters {
        strings.write_string(buf, param.name)
        strings.write_rune(buf, ' ')
        purego_write_type(buf, param.type, rn, externs, string_able)

        if idx != len(func.parameters) - 1 {
            strings.write_string(buf, ", ")
        }
    }

    strings.write_rune(buf, ')')

    if builtin, ok := func.return_type.spec.(runic.Builtin); ok {
        if builtin == .Untyped {
            return
        }
    }

    strings.write_rune(buf, ' ')
    purego_write_type(buf, func.return_type, rn, externs, string_able)
}

@(private)
purego_write_typespecifier :: proc(
    buf: ^strings.Builder,
    spec: runic.TypeSpecifier,
    rn: runic.To,
    externs: om.OrderedMap(string, runic.Extern),
    string_able: bool,
) {
    switch s in spec {
    case runic.Builtin:
        switch s {
        case .Untyped:
            strings.write_string(buf, "unsafe.Pointer /* untyped */")
        case .RawPtr:
            strings.write_string(buf, "unsafe.Pointer")
        case .SInt8:
            strings.write_string(buf, "int8")
        case .SInt16:
            strings.write_string(buf, "int16")
        case .SInt32:
            strings.write_string(buf, "int32")
        case .SInt64:
            strings.write_string(buf, "int64")
        case .SInt128:
            strings.write_string(buf, "[2]int64 /* int128 */")
        case .SIntX:
            strings.write_string(buf, "int")
        case .UInt8:
            strings.write_string(buf, "uint8")
        case .UInt16:
            strings.write_string(buf, "uint16")
        case .UInt32:
            strings.write_string(buf, "uint32")
        case .UInt64:
            strings.write_string(buf, "uint64")
        case .UInt128:
            strings.write_string(buf, "[2]uint64 /* uint128 */")
        case .UIntX:
            strings.write_string(buf, "uint")
        case .Float32:
            strings.write_string(buf, "float32")
        case .Float64:
            strings.write_string(buf, "float64")
        case .Float128:
            strings.write_string(buf, "[2]float64 /* float128 */")
        case .String:
            if string_able {
                strings.write_string(buf, "string")
            } else {
                strings.write_string(buf, "RunicString")
            }
        case .Bool8:
            strings.write_string(buf, "int8 /* bool8 */")
        case .Bool16:
            strings.write_string(buf, "int16 /* bool16 */")
        case .Bool32:
            strings.write_string(buf, "int32 /* bool32 */")
        case .Bool64:
            strings.write_string(buf, "int64 /* bool64 */")
        case .Opaque:
            strings.write_string(buf, "unsafe.Pointer /* opaque */")
        }
    case runic.Struct:
        strings.write_string(buf, "struct {\n")
        for member in s.members {
            strings.write_rune(buf, '\t')

            upper_member_name, upper_member_name_err := strings.to_pascal_case(
                member.name,
            )
            if upper_member_name_err != .None {
                upper_member_name = strings.clone(member.name)
            }
            defer delete(upper_member_name)

            strings.write_string(buf, upper_member_name)
            strings.write_rune(buf, ' ')
            purego_write_type(buf, member.type, rn, externs, false)
            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case runic.Enum:
        purego_write_typespecifier(buf, s.type, rn, externs, false)
    case runic.Union:
        strings.write_string(buf, "struct /* union */ {\n")
        for member in s.members {
            strings.write_rune(buf, '\t')
            strings.write_string(buf, member.name)
            strings.write_rune(buf, ' ')
            purego_write_type(buf, member.type, rn, externs, false)
            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case string:
        upper_case_name, err := strings.to_pascal_case(s)
        if err != .None {
            upper_case_name = strings.clone(s)
        }
        defer delete(upper_case_name)

        strings.write_string(buf, upper_case_name)
    case runic.Unknown:
        strings.write_string(buf, "unsafe.Pointer /* unknown \"")
        strings.write_string(buf, string(s))
        strings.write_string(buf, "\" */")
    case runic.FunctionPointer:
        purego_write_function(buf, s^, rn, externs, false)
    case runic.ExternType:
        extern, extern_ok := om.get(externs, string(s))
        if !extern_ok {
            strings.write_string(buf, "unsafe.Pointer /* \"unknown_extern.")
            strings.write_string(buf, string(s))
            strings.write_string(buf, "\" */")
            break
        }

        extern_source, extern_source_ok := rn.extern.sources[extern.source]
        if extern_source_ok {
            name, package_import := purego_extern_package(extern_source)
            prefix: string = ---
            if len(name) != 0 {
                prefix = name
            } else {
                prefix = slashpath.base(package_import)
            }

            strings.write_string(buf, prefix)
            strings.write_rune(buf, '.')

            type_name: string = ---
            remap, remap_ok := rn.extern.remaps[string(s)]
            if remap_ok {
                type_name = remap
            } else {
                type_name = string(s)
            }

            strings.write_string(buf, type_name)
        } else {
            purego_write_type(buf, extern, rn, externs, string_able)
        }
    }
}

@(private)
purego_generate_types :: proc(rs: runic.Runestone, rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    for entry, idx in rs.types.data {
        typ_name, typ := entry.key, entry.value

        upper_case_type_name, pascal_err := strings.to_pascal_case(typ_name)
        if pascal_err != .None do continue
        defer delete(upper_case_type_name)

        strings.write_string(&buf, "type ")
        strings.write_string(&buf, upper_case_type_name)
        strings.write_rune(&buf, ' ')
        purego_write_type(&buf, typ, rn, rs.externs, true)

        if idx != om.length(rs.types) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_symbol_registrations :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    for entry, idx in rs.symbols.data {
        sym_name, sym := entry.key, entry.value
        _, is_type := sym.value.(runic.Type)

        upper_sym_name, upper_sym_name_err := strings.to_pascal_case(sym_name)
        if upper_sym_name_err != .None do continue
        defer delete(upper_sym_name)

        strings.write_string(&buf, "\t\t{&")
        if is_type {
            strings.write_string(&buf, "runicPtr")
        }
        strings.write_string(&buf, upper_sym_name)
        strings.write_string(&buf, ", \"")
        strings.write_string(&buf, sym.remap.? or_else sym_name)
        strings.write_string(&buf, "\"},")

        if idx != om.length(rs.symbols) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_new_file_for_runestone :: proc(
    rs: runic.Runestone,
    rn: runic.To,
) -> (
    ^os.File,
    errors.Error,
) {
    platform_file_name := runic.platform_file_name(rn.out, rs.platform)
    defer delete(platform_file_name)

    file, err := os.open(
        platform_file_name,
        {.Write, .Create, .Trunc},
        {.Read_User, .Write_User, .Read_Group, .Read_Other},
    )
    if err != nil do return file, errors.wrap(err)

    return file, nil
}

@(private)
purego_generate_symbol_registration_variable_name :: proc(
    plats: []runic.Platform,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "runicSymbols")

    for plat in plats {
        if plat.os != .Any {
            fmt.sbprintf(&buf, "{}", plat.os)
        }
        if plat.arch != .Any {
            fmt.sbprintf(&buf, "{}", plat.arch)
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_generate_symbol_variables :: proc(rc: runic.Runecross) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    for rc_rs, idx in rc.cross {
        reg_var_name := purego_generate_symbol_registration_variable_name(
            rc_rs.plats,
        )
        defer delete(reg_var_name)

        strings.write_string(&buf, "\t\t")
        strings.write_string(&buf, reg_var_name)
        strings.write_rune(&buf, ',')

        if idx != len(rc.cross) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
purego_uses_unsafe :: proc {
    purego_type_uses_unsafe,
    purego_function_uses_unsafe,
    purego_symbol_uses_unsafe,
}

@(private)
purego_type_uses_unsafe :: proc(typ: runic.Type) -> bool {
    switch s in typ.spec {
    case runic.Builtin:
        switch s {
        case .Untyped, .RawPtr, .Opaque:
            return true
        case .SInt8,
             .SInt16,
             .SInt32,
             .SInt64,
             .SInt128,
             .SIntX,
             .UInt8,
             .UInt16,
             .UInt32,
             .UInt64,
             .UInt128,
             .UIntX,
             .Float32,
             .Float64,
             .Float128,
             .String,
             .Bool8,
             .Bool16,
             .Bool32,
             .Bool64:
            return false
        }
    case runic.Struct:
        for member in s.members {
            if purego_type_uses_unsafe(member.type) {
                return true
            }
        }
    case runic.Union:
        for member in s.members {
            if purego_type_uses_unsafe(member.type) {
                return true
            }
        }
    case runic.Enum:
        return purego_type_uses_unsafe(runic.Type{spec = s.type})
    case string:
        return false
    case runic.Unknown:
        return true
    case runic.FunctionPointer:
        return purego_function_uses_unsafe(s^)
    case runic.ExternType:
        return true
    }

    return false
}

@(private)
purego_function_uses_unsafe :: proc(func: runic.Function) -> bool {
    if purego_type_uses_unsafe(func.return_type) {
        return true
    }

    for param in func.parameters {
        if purego_type_uses_unsafe(param.type) {
            return true
        }
    }

    return false
}

@(private)
purego_symbol_uses_unsafe :: proc(sym: runic.Symbol) -> bool {
    switch s in sym.value {
    case runic.Type:
        return purego_type_uses_unsafe(s)
    case runic.Function:
        return purego_function_uses_unsafe(s)
    }

    return false
}

@(private)
purego_extern_package :: proc(extern_source: string) -> (string, string) {
    name_and_package, alloc_err := strings.split(extern_source, " ")
    if alloc_err != .None do return "", ""
    defer delete(name_and_package)

    name, package_import: string = ---, ---

    if len(name_and_package) == 2 {
        name = name_and_package[0]
        package_import = name_and_package[1]
    } else if len(name_and_package) == 1 {
        name = ""
        package_import = name_and_package[0]
    } else {
        return "", ""
    }

    return name, package_import
}
