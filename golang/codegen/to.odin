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

import "core:io"
import "core:os"
import "core:strings"
import "root:errors"
import "root:runic"

GO_RESERVED :: []string {
    "break",
    "case",
    "chan",
    "const",
    "continue",
    "default",
    "defer",
    "else",
    "fallthrough",
    "for",
    "func",
    "go",
    "goto",
    "if",
    "import",
    "interface",
    "map",
    "package",
    "range",
    "return",
    "select",
    "struct",
    "switch",
    "type",
    "var",
    "bool",
    "string",
    "int",
    "int8",
    "int16",
    "int32",
    "int64",
    "uint",
    "uint8",
    "uint16",
    "uint32",
    "uint64",
    "uintptr",
    "float32",
    "float64",
    "complex64",
    "complex128",
    "byte",
    "rune",
}

generate_bindings :: proc {
    generate_bindings_from_runecross,
}

generate_bindings_from_runecross :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    rune_file_path: string,
    wd: io.Writer,
) -> union {
        io.Error,
        errors.Error,
    } {
    if !rn.purego do return errors.Error(errors.message("\"to.purego\" must be true. Only purego golang bindings are supported"))

    file_contents := strings.clone(purego_template)
    defer delete(file_contents)

    file_contents_replace := make(map[string]string)
    defer delete(file_contents_replace)

    rs := rc.cross[0]
    build_constraints := purego_generate_build_constraints(rs.plats)
    package_name := purego_generate_package_name(rn)
    imports := purego_generate_imports(rs, rn, true)
    platforms_and_libraries := purego_generate_platforms_and_libraries(
        rc,
        rn,
        rune_file_path,
    )
    types := purego_generate_types(rs, rn)
    func_sym_decls := purego_generate_function_symbol_declarations(rs, rn)
    type_sym_getters := purego_generate_type_symbol_getters(rs, rn)
    type_sym_setters := purego_generate_type_symbol_setters(rs, rn)
    type_sym_pointers := purego_generate_type_symbol_pointers(rs, rn)
    symbol_registrations := purego_generate_symbol_registrations(rs, rn)
    symbol_variables := purego_generate_symbol_variables(rc)

    defer if len(build_constraints) != 0 do delete(build_constraints)

    file_contents_replace["package main"] = package_name
    file_contents_replace["import (\n\t\"errors\"\n\t\"runtime\"\n\t\"unsafe\"\n\n\t\"github.com/ebitengine/purego\"\n)"] =
        imports
    file_contents_replace["\t\t{\"linux\", \"amd64\"}: \"libc.so.6\","] =
        platforms_and_libraries
    file_contents_replace["type LibCType int"] = types
    file_contents_replace["\tPuts func(string)"] = func_sym_decls
    file_contents_replace["func Errno() int {\n\treturn *(*int)(unsafe.Pointer(runicPtrErrno))\n}"] =
        type_sym_getters
    file_contents_replace["func SetErrno(value int) {\n\t*(*int)(unsafe.Pointer(runicPtrErrno)) = value\n}\n"] =
        type_sym_setters
    file_contents_replace["var (\n\trunicPtrErrno uintptr\n)"] =
        type_sym_pointers
    file_contents_replace["\t\t{&Puts, \"puts\"},"] = symbol_registrations
    file_contents_replace["\t\trunicSymbols,"] = symbol_variables

    for old_str, new_str in file_contents_replace {
        new_file_contents, was_alloc := strings.replace(
            file_contents,
            old_str,
            new_str,
            1,
        )
        if was_alloc {
            delete(file_contents)
        }

        file_contents = new_file_contents

        delete(new_str)
    }

    if len(build_constraints) != 0 {
        io.write_string(wd, build_constraints) or_return
        io.write_rune(wd, '\n') or_return
    }
    io.write_string(wd, file_contents) or_return

    for rc_rs, idx in rc.cross[1:] {
        file := purego_new_file_for_runestone(rc_rs, rn) or_return
        defer os.close(file)

        purego_generate_bindings_from_runestone(
            rc_rs,
            idx + 1,
            rn,
            rc,
            os.to_stream(file),
        ) or_return
    }

    return nil
}

@(private)
runic_os_to_goos :: proc(os: runic.OS) -> string {
    switch os {
    case .Any:
        return "any"
    case .Linux:
        return "linux"
    case .Windows:
        return "windows"
    case .Macos:
        return "darwin"
    case .BSD:
        return "freebsd"
    }

    panic("unreachable")
}

@(private)
runic_arch_to_goarch :: proc(arch: runic.Architecture) -> string {
    switch arch {
    case .Any:
        return "any"
    case .x86_64:
        return "amd64"
    case .arm64:
        return "arm64"
    case .x86:
        // TODO
        return "i684"
    case .arm32:
        // TODO
        return "arm"
    }

    panic("unreachable")
}
