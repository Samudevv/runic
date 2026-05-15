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

    purego_generate_bindings_from_runestone(
        rc.cross[0],
        0,
        rn,
        rc,
        rune_file_path,
        wd,
        true,
    ) or_return

    for rc_rs, idx in rc.cross[1:] {
        file := purego_new_file_for_runestone(rc_rs, rn) or_return
        defer os.close(file)

        purego_generate_bindings_from_runestone(
            rc_rs,
            idx + 1,
            rn,
            rc,
            rune_file_path,
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
