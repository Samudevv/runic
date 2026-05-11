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

import "root:runic"
import "root:errors"
import "core:io"
import "core:strings"

GO_RESERVED :: []string{
    "int",
    "uint",
}

generate_bindings :: proc {
    generate_bindings_from_runecross,
}

generate_bindings_from_runecross :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    wd: io.Writer,
) -> union {
    io.Error,
    errors.Error,
} {
    if !rn.purego do return errors.Error(errors.message("\"to.purego\" must be true. Only purego golang bindings are supported"))

    file_contents := strings.clone(purego_template)
    defer delete(file_contents)

    file_contents = purego_generate_package_name(file_contents, rn)
    file_contents = purego_generate_platforms_and_libraries(file_contents, rc, rn)

    for rs in rc.cross {
        file_contents = purego_generate_types(file_contents, rs, rn)
        file_contents = purego_generate_symbol_declarations(file_contents, rs, rn)
        file_contents = purego_generate_symbol_registrations(file_contents, rs, rn)
    }

	file_contents = purego_clean_template(file_contents)
    
    io.write_string(wd, file_contents) or_return

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
    case .x86: // TODO
        return "i684"
    case .arm32: // TODO
        return "arm"
    }

    panic("unreachable")
}
