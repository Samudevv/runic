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
import "root:runic"
import "root:errors"
import "core:strings"
import om "root:ordered_map"

@(private)
purego_template :: #load("./go/purego_template.go", string)

purego_generate_bindings_from_runestone :: proc(
    rs: runic.Runestone,
    rn: runic.To,
    wd: io.Writer,
) -> union {
    io.Error,
    errors.Error,
} {
    return errors.Error(errors.not_implemented())
}

@(private)
purego_generate_package_name :: proc(
    buffer: string,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    strings.write_string(&buf, "package ")
    strings.write_string(&buf, rn.package_name)

    new_buffer, _ := strings.replace(buffer, "package main", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_generate_platforms_and_libraries :: proc(
    buffer: string,
    rc: runic.Runecross,
    rn: runic.To,
) -> string {
    platform_libraries := om.make(runic.Platform, string)
    defer om.delete(platform_libraries)

    for entry in rc.cross {
        for plat in entry.plats {
            if !om.contains(platform_libraries, plat) {
                if shared, ok := entry.lib.shared.?; ok {
                    om.insert(&platform_libraries, plat, shared)
                }
            }
        }
    }

    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

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

    new_buffer, _ := strings.replace(buffer, "\t\t{\"linux\", \"amd64\"}: \"libc.so.6\",", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_generate_symbol_declarations :: proc(buffer: string, rs: runic.Runestone, rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    for entry, idx in rs.symbols.data {
        sym_name, sym := entry.key, entry.value

        strings.write_rune(&buf, '\t')
        strings.write_string(&buf, sym_name)
        strings.write_rune(&buf, ' ')
        purego_write_symbol(&buf, sym, rn)

        if idx != om.length(rs.symbols) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    new_buffer, _ := strings.replace(buffer, "\tPuts func(string)", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_write_symbol :: proc(buf: ^strings.Builder, sym: runic.Symbol, rn: runic.To) {
    switch val in sym.value {
    case runic.Type:
        purego_write_type(buf, val, rn)
    case runic.Function:
        purego_write_function(buf, val, rn)
    }
}

@(private)
purego_write_type :: proc(buf: ^strings.Builder, typ: runic.Type, rn: runic.To) {
    // TODO: handle pointer and array

    purego_write_typespecifier(buf, typ.spec, rn)
}

@(private)
purego_write_function :: proc(buf: ^strings.Builder, func: runic.Function, rn: runic.To) {
    strings.write_string(buf, "func(")

    for param, idx in func.parameters {
        strings.write_string(buf, param.name)
        strings.write_rune(buf, ' ')
        purego_write_type(buf, param.type, rn)

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
    purego_write_type(buf, func.return_type, rn)
}

@(private)
purego_write_typespecifier :: proc(buf: ^strings.Builder, spec: runic.TypeSpecifier, rn: runic.To) {
    switch s in spec {
    case runic.Builtin:
        switch s {
        case .Untyped:
            strings.write_string(buf, "untyped")
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
            strings.write_string(buf, "int128")
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
            strings.write_string(buf, "uint128")
        case .UIntX:
            strings.write_string(buf, "uint")
        case .Float32:
            strings.write_string(buf, "float32")
        case .Float64:
            strings.write_string(buf, "float64")
        case .Float128:
            strings.write_string(buf, "float128")
        case .String:
            strings.write_string(buf, "string")
        case .Bool8:
            strings.write_string(buf, "bool8")
        case .Bool16:
            strings.write_string(buf, "bool16")
        case .Bool32:
            strings.write_string(buf, "bool32")
        case .Bool64:
            strings.write_string(buf, "bool64")
        case .Opaque:
            strings.write_string(buf, "opaque")
        }
    case runic.Struct:
        strings.write_string(buf, "struct {\n")
        for member in s.members {
            strings.write_rune(buf, '\t')
            strings.write_string(buf, member.name)
            strings.write_rune(buf, ' ')
            purego_write_type(buf, member.type, rn)
            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case runic.Enum:
        purego_write_typespecifier(buf, s.type, rn)
    case runic.Union:
        strings.write_string(buf, "union {\n")
        for member in s.members {
            strings.write_rune(buf, '\t')
            strings.write_string(buf, member.name)
            strings.write_rune(buf, ' ')
            purego_write_type(buf, member.type, rn)
            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case string:
        strings.write_string(buf, s)
    case runic.Unknown:
        strings.write_string(buf, "unknown")
    case runic.FunctionPointer:
        purego_write_function(buf, s^, rn)
    case runic.ExternType:
        strings.write_string(buf, "extern.")
        strings.write_string(buf, string(s))
    }
}

@(private)
purego_generate_types :: proc(buffer: string, rs: runic.Runestone, rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    for entry, idx in rs.types.data {
        typ_name, typ := entry.key, entry.value

        strings.write_string(&buf, "type ")
        strings.write_string(&buf, typ_name)
        strings.write_rune(&buf, ' ')
        purego_write_type(&buf, typ, rn)

        if idx != om.length(rs.types) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    new_buffer, _ := strings.replace(buffer, "type LibCType int", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_generate_symbol_registrations :: proc(buffer: string, rs: runic.Runestone, rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    for entry, idx in rs.symbols.data {
        sym_name := entry.key

        strings.write_string(&buf, "\t\t{&")
        strings.write_string(&buf, sym_name)
        strings.write_string(&buf, ", \"")
        strings.write_string(&buf, sym_name)
        strings.write_string(&buf, "\"},")

        if idx != om.length(rs.symbols) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    new_buffer, _ := strings.replace(buffer, "\t\t{&Puts, \"puts\"},", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_clean_template :: proc(buffer: string) -> string {
MAIN_FUNC :: `func main() {
	if err := LoadForeignLibrary(); err != nil {
		panic(err)
	}

	Puts("Calling C from Go without Cgo!")
}`

    new_buffer, _ := strings.replace(buffer, MAIN_FUNC, "", 1)
    delete(buffer)

    return new_buffer
}
