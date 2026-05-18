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
import "core:path/slashpath"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
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
        file := runic.create_file_for_runestone(rc_rs, rn) or_return
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

@(private)
generate_build_constraints :: proc(plats: []runic.Platform) -> string {
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
generate_package_name :: proc(rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "package ")
    strings.write_string(&buf, rn.package_name)

    return strings.to_string(buf)
}

@(private)
generate_constants :: proc(rs: runic.Runestone, rn: runic.To) -> string {
    if om.length(rs.constants) == 0 do return ""

    buf: strings.Builder
    strings.builder_init(&buf)

    strings.write_string(&buf, "const (\n")

    for entry in rs.constants.data {
        const_name, const := entry.key, entry.value

        if const.value == nil do continue

        strings.write_rune(&buf, '\t')
        strings.write_string(&buf, const_name)
        strings.write_rune(&buf, ' ')

        if builtin, is_builtin := const.type.spec.(runic.Builtin);
           !is_builtin || builtin != .Untyped {
            write_type(&buf, const.type, rn, rs.externs, true)
            strings.write_rune(&buf, ' ')
        }

        strings.write_string(&buf, "= ")

        switch v in const.value {
        case i64:
            strings.write_i64(&buf, v)
        case f64:
            strings.write_float(&buf, v, 'f', 2, 64)
        case string:
            strings.write_rune(&buf, '`')
            strings.write_string(&buf, v)
            strings.write_rune(&buf, '`')
        }

        strings.write_rune(&buf, '\n')
    }

    for entry in rs.types.data {
        type_name, typ := entry.key, entry.value

        emum, emum_ok := typ.spec.(runic.Enum)
        if !emum_ok do continue

        strings.write_rune(&buf, '\n')

        for enum_entry in emum.entries {
            strings.write_rune(&buf, '\t')

            // TODO: properly handle casing
            strings.write_string(&buf, type_name)
            strings.write_string(&buf, enum_entry.name)

            strings.write_rune(&buf, ' ')
            strings.write_string(&buf, type_name)

            strings.write_string(&buf, " = ")

            switch v in enum_entry.value {
            case i64:
                strings.write_i64(&buf, v)
            case string:
                strings.write_string(&buf, v)
            }

            strings.write_rune(&buf, '\n')
        }
    }

    strings.write_string(&buf, ")")

    return strings.to_string(buf)
}

@(private)
generate_types :: proc(rs: runic.Runestone, rn: runic.To) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)

    for entry, idx in rs.types.data {
        typ_name, typ := entry.key, entry.value

        strings.write_string(&buf, "type ")
        strings.write_string(&buf, typ_name)
        strings.write_rune(&buf, ' ')
        write_type(&buf, typ, rn, rs.externs, true)

        if idx != om.length(rs.types) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    return strings.to_string(buf)
}

@(private)
write_type :: proc(
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

    write_typespecifier(buf, typ.spec, rn, externs, string_able)
}

@(private)
write_function :: proc(
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
        write_type(buf, param.type, rn, externs, string_able)

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
    write_type(buf, func.return_type, rn, externs, string_able)
}

@(private)
write_typespecifier :: proc(
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

            strings.write_string(buf, member.name)
            strings.write_rune(buf, ' ')
            write_type(buf, member.type, rn, externs, false)

            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case runic.Enum:
        write_typespecifier(buf, s.type, rn, externs, false)
    case runic.Union:
        strings.write_string(buf, "struct /* union */ {\n")
        for member in s.members {
            strings.write_rune(buf, '\t')

            strings.write_string(buf, member.name)
            strings.write_rune(buf, ' ')
            write_type(buf, member.type, rn, externs, false)

            strings.write_rune(buf, '\n')
        }
        strings.write_string(buf, "}")
    case string:
        strings.write_string(buf, string(s))
    case runic.Unknown:
        strings.write_string(buf, "unsafe.Pointer /* unknown \"")
        strings.write_string(buf, string(s))
        strings.write_string(buf, "\" */")
    case runic.FunctionPointer:
        write_function(buf, s^, rn, externs, false)
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
            name, package_import := extern_package(extern_source)
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
            write_type(buf, extern, rn, externs, string_able)
        }
    }
}

@(private)
uses_unsafe :: proc {
    type_uses_unsafe,
    function_uses_unsafe,
    symbol_uses_unsafe,
}

@(private)
type_uses_unsafe :: proc(typ: runic.Type) -> bool {
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
            if type_uses_unsafe(member.type) {
                return true
            }
        }
    case runic.Union:
        for member in s.members {
            if type_uses_unsafe(member.type) {
                return true
            }
        }
    case runic.Enum:
        return type_uses_unsafe(runic.Type{spec = s.type})
    case string:
        return false
    case runic.Unknown:
        return true
    case runic.FunctionPointer:
        return function_uses_unsafe(s^)
    case runic.ExternType:
        return true
    }

    return false
}

@(private)
function_uses_unsafe :: proc(func: runic.Function) -> bool {
    if type_uses_unsafe(func.return_type) {
        return true
    }

    for param in func.parameters {
        if type_uses_unsafe(param.type) {
            return true
        }
    }

    return false
}

@(private)
symbol_uses_unsafe :: proc(sym: runic.Symbol) -> bool {
    switch s in sym.value {
    case runic.Type:
        return type_uses_unsafe(s)
    case runic.Function:
        return function_uses_unsafe(s)
    }

    return false
}

@(private)
extern_package :: proc(extern_source: string) -> (string, string) {
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
