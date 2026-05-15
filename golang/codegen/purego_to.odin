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
    rune_file_path: string,
    wd: io.Writer,
    is_main_file: bool = false,
) -> union {
        io.Error,
        errors.Error,
    } {

    build_constraints := generate_build_constraints(rs.plats)
    package_name := generate_package_name(rn)
    imports := purego_generate_imports(rs, rn, is_main_file)
    constants := generate_constants(rs, rn)
    types := generate_types(rs, rn)
    func_sym_decls := purego_generate_function_symbol_declarations(rs, rn)
    type_sym_getters := purego_generate_type_symbol_getters(rs, rn)
    type_sym_setters := purego_generate_type_symbol_setters(rs, rn)
    type_sym_pointers := purego_generate_type_symbol_pointers(rs, rn)
    symbol_registrations := purego_generate_symbol_registrations(rs, rn)
    symbol_reg_var_name := purego_generate_symbol_registration_variable_name(
        rs.plats,
    )
    symbol_variables := purego_generate_symbol_variables(rc)

    defer if len(build_constraints) != 0 do delete(build_constraints)
    defer delete(package_name)
    defer delete(imports)
    defer delete(constants)
    defer delete(types)
    defer delete(func_sym_decls)
    defer delete(type_sym_getters)
    defer delete(type_sym_setters)
    defer delete(type_sym_pointers)
    defer delete(symbol_registrations)
    defer delete(symbol_reg_var_name)
    defer delete(symbol_variables)

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

    if len(constants) != 0 {
        io.write_string(wd, constants) or_return
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

    if !is_main_file {
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
    }

    if is_main_file {
        platform_libraries := purego_generate_platforms_and_libraries(
            rc,
            rn,
            rune_file_path,
        )
        defer delete(platform_libraries)

        io.write_rune(wd, '\n') or_return

        io.write_string(wd, "\trunicAllSymbols = [][][2]any{\n") or_return
        io.write_string(wd, symbol_variables) or_return
        io.write_string(wd, "\n\t}\n\n") or_return

        io.write_string(wd, "\trunicLibraries = map[[2]string]string{\n") or_return
        io.write_string(wd, platform_libraries) or_return
        io.write_string(wd, "\n\t}\n") or_return
    }

    io.write_string(wd, ")\n") or_return

    if is_main_file {
        io.write_string(wd, "\n\n") or_return
        io.write_string(wd, purego_template) or_return
    }

    return nil
}

@(private)
purego_generate_imports :: proc(
    rs: runic.Runestone,
    rn: runic.To,
    is_main_file: bool,
) -> string {
    imports_unsafe: bool = is_main_file

    rs_externs := make([dynamic]string)
    defer delete(rs_externs)

    for entry in rs.externs.data {
        extern := entry.value

        if !slice.contains(rs_externs[:], extern.source) {
            append(&rs_externs, extern.source)
        }

        if !imports_unsafe {
            if uses_unsafe(extern) {
                imports_unsafe = true
            }
        }
    }

    if !imports_unsafe {
        for entry in rs.symbols.data {
            sym := entry.value
            if _, is_type := sym.value.(runic.Type); is_type {
                imports_unsafe = true
                break
            }

            if uses_unsafe(sym) {
                imports_unsafe = true
                break
            }
        }
    }

    if !imports_unsafe {
        for entry in rs.types.data {
            typ := entry.value

            if uses_unsafe(typ) {
                imports_unsafe = true
                break
            }
        }
    }

    if !imports_unsafe {
        for entry in rs.constants.data {
            const := entry.value

            if uses_unsafe(const.type) {
                imports_unsafe = true
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
    } else if imports_unsafe {
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
        name, package_import := extern_package(import_path)

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

        strings.write_rune(&buf, '\t')
        strings.write_string(&buf, sym_name)
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

        strings.write_string(&buf, "func ")
        strings.write_string(&buf, sym_name)
        strings.write_string(&buf, "() ")
        write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, " {\n\treturn *(*")
        write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ")(unsafe.Pointer(runicPtr")
        strings.write_string(&buf, sym_name)
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

        strings.write_string(&buf, "func Set")
        strings.write_string(&buf, sym_name)
        strings.write_string(&buf, "(value ")
        write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ") {\n\t*(*")
        write_type(&buf, sym.value.(runic.Type), rn, rs.externs, false)
        strings.write_string(&buf, ")(unsafe.Pointer(runicPtr")
        strings.write_string(&buf, sym_name)
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

        strings.write_string(&buf, "\trunicPtr")
        strings.write_string(&buf, sym_name)
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
        write_type(buf, val, rn, externs, true)
    case runic.Function:
        write_function(buf, val, rn, externs, true)
    }
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

        strings.write_string(&buf, "\t\t{&")
        if is_type {
            strings.write_string(&buf, "runicPtr")
        }
        strings.write_string(&buf, sym_name)
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
