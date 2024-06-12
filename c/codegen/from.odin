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

import "../parser"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "root:errors"
import "root:exec"
import om "root:ordered_map"
import "root:runic"

generate_runestone :: proc(
    plat: runic.Platform,
    rune_file_name: string,
    rf: runic.From,
) -> (
    rs: runic.Runestone,
    err: errors.Error,
) {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)

    isz := int_sizes_from_platform(plat)

    runic.set_library(plat, &rs, rf)

    rune_defines := runic.platform_value(
        map[string]json.Value,
        plat,
        all = rf.defines,
        linux = rf.defines_linux,
        linux_x86_64 = rf.defines_linux_x86_64,
        linux_arm64 = rf.defines_linux_arm64,
        windows = rf.defines_windows,
        windows_x86_64 = rf.defines_windows_x86_64,
        windows_arm64 = rf.defines_windows_arm64,
        macos = rf.defines_macos,
        macos_x86_64 = rf.defines_macos_x86_64,
        macos_arm64 = rf.defines_macos_arm64,
        bsd = rf.defines_bsd,
        bsd_x86_64 = rf.defines_bsd_x86_64,
        bsd_arm64 = rf.defines_bsd_arm64,
    )

    defines := make([dynamic][2]string, arena_alloc)

    for name, value in rune_defines {
        str_value := json_value_to_string(value, arena_alloc) or_return
        append(&defines, [2]string{name, str_value})
    }

    headers := runic.platform_value(
        [dynamic]string,
        plat,
        all = rf.headers,
        linux = rf.headers_linux,
        linux_x86_64 = rf.headers_linux_x86_64,
        linux_arm64 = rf.headers_linux_arm64,
        windows = rf.headers_windows,
        windows_x86_64 = rf.headers_windows_x86_64,
        windows_arm64 = rf.headers_windows_arm64,
        macos = rf.headers_macos,
        macos_x86_64 = rf.headers_macos_x86_64,
        macos_arm64 = rf.headers_macos_x86_64,
        bsd = rf.headers_bsd,
        bsd_x86_64 = rf.headers_bsd_x86_64,
        bsd_arm64 = rf.headers_bsd_arm64,
    )

    pp_program := parser.PREPROCESS_PROGRAM
    pp_flags := parser.PREPROCESS_FLAGS
    if rf.preprocessor != nil {
        switch pp in rf.preprocessor {
        case string:
            pp_program = pp
            pp_flags = []string{}
        case [dynamic]string:
            errors.assert(len(pp) != 0) or_return

            pp_program = pp[0]
            if len(pp) > 1 {
                pp_flags = pp[1:]
            } else {
                pp_flags = []string{}
            }
        }
    }

    for hd in headers {
        p: parser.Parser
        defer parser.destroy_parser(&p)

        includedirs := runic.platform_value(
            [dynamic]string,
            plat,
            all = rf.includedirs,
            linux = rf.includedirs_linux,
            linux_x86_64 = rf.includedirs_linux_x86_64,
            linux_arm64 = rf.includedirs_linux_arm64,
            windows = rf.includedirs_windows,
            windows_x86_64 = rf.includedirs_windows_x86_64,
            windows_arm64 = rf.includedirs_windows_arm64,
            macos = rf.includedirs_macos,
            macos_x86_64 = rf.includedirs_macos_x86_64,
            macos_arm64 = rf.includedirs_macos_arm64,
            bsd = rf.includedirs_bsd,
            bsd_x86_64 = rf.includedirs_bsd_x86_64,
            bsd_arm64 = rf.includedirs_bsd_arm64,
        )

        p = parser.parse_file(
            plat,
            runic.relative_to_file(rune_file_name, hd, arena_alloc),
            includedirs = includedirs[:],
            defines = defines[:],
            pp_program = pp_program,
            pp_flags = pp_flags,
        ) or_return
        context.allocator = rs_arena_alloc

        custom_types: [dynamic]string

        typedef_loop: for td in p.typedefs {
            tp, name := parser_variable_to_runic_type(td, &rs.anon_types, isz)
            if name != nil {
                if runic.single_list_glob(rf.ignore.types, name.?) {
                    continue
                }

                tp.spec = check_unknown_types(tp.spec, rs.types, &custom_types)

                if om.contains(rs.types, name.?) {
                    fmt.eprintf("Type {} is defined as \"", name)
                    runic.write_type(
                        os.stream_from_handle(os.stderr),
                        om.get(rs.types, name.?),
                    )
                    fmt.eprint("\" and \"")
                    runic.write_type(os.stream_from_handle(os.stderr), tp)
                    fmt.eprintln('"')
                }

                om.insert(&rs.types, name.?, tp)
            }
        }

        for vr in p.variables {
            sym: runic.Symbol

            v_type, v_name := parser_variable_to_runic_type(
                vr,
                &rs.anon_types,
                isz,
            )

            if v_name == nil || runic.single_list_glob(rf.ignore.variables, v_name.?) do continue

            sym.value = v_type

            v_type.spec = check_unknown_types(
                v_type.spec,
                rs.types,
                &custom_types,
            )

            if om.contains(rs.symbols, v_name.?) {
                fmt.eprintf("Variable {} is defined as \"", v_name.?)
                def_var := om.get(rs.symbols, v_name.?)
                switch v in def_var.value {
                case runic.Function:
                    runic.write_function(os.stream_from_handle(os.stderr), v)
                case runic.Type:
                    runic.write_type(os.stream_from_handle(os.stderr), v)
                }
                fmt.eprint("\" and \"")
                runic.write_type(os.stream_from_handle(os.stderr), v_type)
                fmt.eprintln('"')
            }

            om.insert(&rs.symbols, v_name.?, sym)
        }

        for fc in p.functions {
            rnfn := parser_function_to_runic_function(fc, &rs.anon_types, isz)
            if fc.name == nil || runic.single_list_glob(rf.ignore.functions, fc.name.?) do continue

            if b, ok := rnfn.return_type.spec.(runic.Builtin);
               ok && b == .Untyped {
                continue
            }

            rnfn = function_check_unknown_types(&rnfn, rs.types, &custom_types)

            if om.contains(rs.symbols, fc.name.?) {
                fmt.eprintf("Function {} is defined as \"", fc.name.?)
                def_var := om.get(rs.symbols, fc.name.?)
                switch v in def_var.value {
                case runic.Function:
                    runic.write_function(os.stream_from_handle(os.stderr), v)
                case runic.Type:
                    runic.write_type(os.stream_from_handle(os.stderr), v)
                }
                fmt.eprint("\" and \"")
                runic.write_function(os.stream_from_handle(os.stderr), rnfn)
                fmt.eprintln('"')
            }

            om.insert(
                &rs.symbols,
                strings.clone(fc.name.?),
                runic.Symbol{value = rnfn},
            )
        }


        custom_types_loop: for ct in custom_types {
            if _, ok := om.get(rs.types, ct); ok do continue

            if runic.single_list_glob(rf.ignore.types, ct) {
                continue custom_types_loop
            }

            for inc in p.includes {
                for td in inc.typedefs {
                    found: bool
                    switch var in td {
                    case parser.Function:
                        if var_name, ok := var.name.?; ok && var_name == ct {
                            found = true
                        }
                    case parser.Var:
                        if var_name, ok := var.name.?; ok && var_name == ct {
                            found = true
                        }
                    }

                    if found {
                        tp, name := parser_variable_to_runic_type(
                            td,
                            &rs.anon_types,
                            isz,
                        )
                        if name != nil {

                            tp.spec = check_unknown_types(
                                tp.spec,
                                rs.types,
                                &custom_types,
                            )

                            om.insert(&rs.types, name.?, tp)
                        }
                        continue custom_types_loop
                    }
                }
            }
        }

        // Check if unknown types are still unknown
        for &entry in rs.types.data {
            type := &entry.value
            type.spec = validate_unknown_types(type.spec, rs.types)
        }
        for &type_spec in rs.anon_types {
            type_spec = validate_unknown_types(type_spec, rs.types)
        }
        for &entry in rs.symbols.data {
            switch &v in entry.value.value {
            case runic.Type:
                v.spec = validate_unknown_types(v.spec, rs.types)
            case runic.Function:
                for &param in v.parameters {
                    param.type.spec = validate_unknown_types(
                        param.type.spec,
                        rs.types,
                    )
                }
                v.return_type.spec = validate_unknown_types(
                    v.return_type.spec,
                    rs.types,
                )
            }
        }
        for &entry in rs.constants.data {
            type := &entry.value.type
            type.spec = validate_unknown_types(type.spec, rs.types)
        }


        macro_loop: for entry in p.macros.data {
            name, macro := entry.key, entry.value
            if runic.single_list_glob(rf.ignore.macros, name) {
                continue
            }

            switch m in macro {
            case parser.MacroVar:
                if m.value == nil {
                    continue macro_loop
                }

                val := m.value.?
                macro_value: union {
                    i64,
                    f64,
                    string,
                }

                ival: i64 = ---
                fval: f64 = ---
                ok: bool = ---

                if ival, ok = strconv.parse_i64(val); ok {
                    macro_value = ival
                } else if fval, ok = strconv.parse_f64(val); ok {
                    macro_value = fval
                } else {
                    for &sym_entry in rs.symbols.data {
                        sym_name, sym := sym_entry.key, &sym_entry.value
                        if val == sym_name {
                            append(&sym.aliases, strings.clone(m.name))
                            continue macro_loop
                        }
                    }

                    for type_entry in rs.types.data {
                        type_name := type_entry.key

                        if val == type_name {
                            om.insert(
                                &rs.types,
                                strings.clone(m.name),
                                runic.Type{spec = type_name},
                            )
                            continue macro_loop
                        }
                    }

                    macro_value = strings.clone(val)
                }

                om.insert(
                    &rs.constants,
                    strings.clone(name),
                    runic.Constant {
                        value = macro_value,
                        type = runic.Type{spec = runic.Builtin.Untyped},
                    },
                )

            case parser.MacroFunc:
            // Ignore
            }
        }
    }


    return
}

validate_unknown_types :: proc(
    tp_spec: runic.TypeSpecifier,
    types: om.OrderedMap(string, runic.Type),
) -> runic.TypeSpecifier {
    #partial switch &spec in tp_spec {
    case runic.Unknown:
        if om.contains(types, string(spec)) {
            return string(spec)
        }
    case runic.FunctionPointer:
        spec^ = function_validate_unknown_types(spec, types)
        return spec
    case runic.Struct:
        return struct_validate_unknown_types(&spec, types)
    case runic.Union:
        strct := runic.Struct {
            members = spec.members,
        }
        return struct_validate_unknown_types(&strct, types)
    }

    return tp_spec
}

function_validate_unknown_types :: proc(
    func: ^runic.Function,
    types: om.OrderedMap(string, runic.Type),
) -> runic.Function {
    func.return_type.spec = validate_unknown_types(
        func.return_type.spec,
        types,
    )

    for &param in func.parameters {
        param.type.spec = validate_unknown_types(param.type.spec, types)
    }

    return func^
}

struct_validate_unknown_types :: proc(
    strct: ^runic.Struct,
    types: om.OrderedMap(string, runic.Type),
) -> runic.Struct {
    for &m in strct.members {
        m.type.spec = validate_unknown_types(m.type.spec, types)
    }

    return strct^
}

check_unknown_types :: proc(
    tp_spec: runic.TypeSpecifier,
    types: om.OrderedMap(string, runic.Type),
    custom_types: ^[dynamic]string,
) -> runic.TypeSpecifier {
    #partial switch &spec in tp_spec {
    case string:
        if !om.contains(types, spec) {
            if !slice.contains(custom_types^[:], spec) {
                append(custom_types, spec)
            }

            return runic.Unknown(spec)
        }
    case runic.FunctionPointer:
        spec^ = function_check_unknown_types(spec, types, custom_types)
        return spec
    case runic.Struct:
        return struct_check_unknown_types(&spec, types, custom_types)
    case runic.Union:
        strct := runic.Struct {
            members = spec.members,
        }
        return struct_check_unknown_types(&strct, types, custom_types)
    }

    return tp_spec
}

function_check_unknown_types :: proc(
    func: ^runic.Function,
    types: om.OrderedMap(string, runic.Type),
    custom_types: ^[dynamic]string,
) -> runic.Function {
    func.return_type.spec = check_unknown_types(
        func.return_type.spec,
        types,
        custom_types,
    )

    for &param in func.parameters {
        param.type.spec = check_unknown_types(
            param.type.spec,
            types,
            custom_types,
        )
    }

    return func^
}

struct_check_unknown_types :: proc(
    strct: ^runic.Struct,
    types: om.OrderedMap(string, runic.Type),
    custom_types: ^[dynamic]string,
) -> runic.Struct {
    for &m in strct.members {
        m.type.spec = check_unknown_types(m.type.spec, types, custom_types)
    }

    return strct^
}

parser_variable_to_runic_type :: proc(
    var: parser.Variable,
    anon_types: ^[dynamic]runic.TypeSpecifier,
    isz: Int_Sizes,
) -> (
    tp: runic.Type,
    name: Maybe(string),
) {
    switch t in var {
    case parser.Var:
        if t.name != nil do name = strings.clone(t.name.?)

        for q in t.qualifiers {
            switch q {
            case .const:
                tp.read_only = true
            case .Inline, .static:
                // these functions are not contained in the libraries
                tp.spec = runic.Builtin.Untyped
                name = nil
                return
            case .restrict, .volatile, ._Atomic, .extern, ._Noreturn:
            // Ignore
            }
        }

        pi := t.pointer_info
        for {
            tp.pointer_info.count += pi.count
            tp.pointer_info.read_only = pi.const

            if pi.child == nil {
                break
            }
            pi = pi.child^
        }

        for ai in t.array_info {
            as: runic.ArraySize
            if ai != nil {
                switch c in ai {
                case i64:
                    as = u64(c)
                case string:
                    as = strings.clone(c)
                }
            }

            append(&tp.array_info, runic.Array{size = as})
        }

        switch ty in t.type {
        case parser.BuiltinType:
            switch ty {
            case .void:
                if tp.pointer_info.count >= 1 {
                    tp.spec = runic.Builtin.RawPtr
                    tp.pointer_info.count -= 1
                } else {
                    tp.spec = runic.Builtin.Void
                }
            case .char, .signedchar:
                tp.spec = int_type(isz.char, true)
            case .unsignedchar:
                tp.spec = int_type(isz.char, false)
            case .short:
                tp.spec = int_type(isz.short, true)
            case .unsignedshort:
                tp.spec = int_type(isz.short, false)
            case .int:
                tp.spec = int_type(isz.Int, true)
            case .unsignedint:
                tp.spec = int_type(isz.Int, false)
            case .long:
                tp.spec = int_type(isz.long, true)
            case .unsignedlong:
                tp.spec = int_type(isz.long, false)
            case .longlong:
                tp.spec = int_type(isz.longlong, true)
            case .unsignedlonglong:
                tp.spec = int_type(isz.longlong, false)
            case .float:
                tp.spec = float_type(isz.float)
            case .double:
                tp.spec = float_type(isz.double)
            case .longdouble:
                tp.spec = float_type(isz.long_double)
            case ._Bool:
                tp.spec = bool_type(isz._Bool)
            case .float_Complex:
                fallthrough
            case .double_Complex:
                fallthrough
            case .longdouble_Complex:
                fmt.eprintln("Complex is not supported")
                name = nil
                return
            }
        case parser.Struct:
            s: runic.Struct
            count: uint
            for m in ty.members {
                m_type, m_name := parser_variable_to_runic_type(
                    m,
                    anon_types,
                    isz,
                )
                if m_name == nil do m_name = fmt.aprintf("memb{}", count)

                #partial switch s in m_type.spec {
                case runic.Struct, runic.Union, runic.Enum, runic.FunctionPointer:
                    append(anon_types, s)
                    m_type.spec = runic.Anon(len(anon_types^) - 1)
                }

                append(
                    &s.members,
                    runic.Member{name = m_name.?, type = m_type},
                )

                count += 1
            }

            tp.spec = s
        case parser.Enum:
            e: runic.Enum
            e.type = .SInt32

            count: i64
            for v in ty.values {
                value_name := strings.clone(v.name)
                value: runic.EnumConstant
                if c, ok := v.value.?; ok {
                    switch cc in c {
                    case i64:
                        value = cc
                        count = cc
                    case string:
                        value = strings.clone(cc)
                    }
                } else {
                    value = count
                }
                count += 1

                append(
                    &e.entries,
                    runic.EnumEntry{name = value_name, value = value},
                )
            }

            tp.spec = e
        case parser.Union:
            u: runic.Union
            count: uint
            for m in ty.members {
                m_type, m_name := parser_variable_to_runic_type(
                    m,
                    anon_types,
                    isz,
                )
                if m_name == nil do m_name = fmt.aprintf("unio{}", count)

                #partial switch s in m_type.spec {
                case runic.Struct, runic.Union, runic.Enum, runic.FunctionPointer:
                    append(anon_types, s)
                    m_type.spec = runic.Anon(len(anon_types^) - 1)
                }


                append(
                    &u.members,
                    runic.Member{name = m_name.?, type = m_type},
                )

                count += 1
            }

            tp.spec = u
        case parser.CustomType:
            switch ty.name {
            case "int8_t":
                tp.spec = runic.Builtin.SInt8
            case "int16_t":
                tp.spec = runic.Builtin.SInt16
            case "int32_t":
                tp.spec = runic.Builtin.SInt32
            case "int64_t":
                tp.spec = runic.Builtin.SInt64
            case "uint8_t":
                tp.spec = runic.Builtin.UInt8
            case "uint16_t":
                tp.spec = runic.Builtin.UInt16
            case "uint32_t":
                tp.spec = runic.Builtin.UInt32
            case "uint64_t":
                tp.spec = runic.Builtin.UInt64
            case:
                tp.spec = strings.clone(ty.name)
            }
        }

        if b, ok := tp.spec.(runic.Builtin); ok && b == .SInt8 {
            if tp.pointer_info.count >= 1 {
                tp.spec = runic.Builtin.String
                tp.pointer_info.count -= 1
            } else if len(tp.array_info) != 0 && tp.array_info[0].size == nil {
                tp.spec = runic.Builtin.String
                ordered_remove(&tp.array_info, 0)
            }
        }
    case parser.Function:
        rf := parser_function_to_runic_function(t, anon_types, isz)

        if b, ok := rf.return_type.spec.(runic.Builtin); ok && b == .Untyped {
            return
        }

        tp.spec = cast(runic.FunctionPointer)new_clone(rf)
        if t.name != nil do name = strings.clone(t.name.?)

        pi := t.pointer_info
        for {
            tp.pointer_info.count += pi.count
            tp.pointer_info.read_only = pi.const

            if pi.child == nil do break
            pi = pi.child^
        }

        for ai in t.array_info {
            as: runic.ArraySize
            if ai != nil {
                switch c in ai {
                case i64:
                    as = u64(c)
                case string:
                    as = strings.clone(c)
                }
            }

            append(&tp.array_info, runic.Array{size = as})
        }
    }

    return
}

parser_function_to_runic_function :: proc(
    fc: parser.Function,
    anon_types: ^[dynamic]runic.TypeSpecifier,
    isz: Int_Sizes,
) -> (
    rf: runic.Function,
) {
    if fc.name == nil do return

    f_type, _ := parser_variable_to_runic_type(
        fc.return_type^,
        anon_types,
        isz,
    )

    if b, ok := f_type.spec.(runic.Builtin); ok && b == .Untyped {
        rf.return_type = f_type
        return
    }

    params: [dynamic]runic.Member

    count: uint
    for p in fc.parameters {
        m_type, m_name := parser_variable_to_runic_type(p, anon_types, isz)
        if m_name == nil do m_name = fmt.aprintf("param{}", count)

        #partial switch s in m_type.spec {
        case runic.Struct, runic.Enum, runic.Union, runic.FunctionPointer:
            append(anon_types, s)
            m_type.spec = runic.Anon(len(anon_types^) - 1)
        }

        append(&params, runic.Member{name = m_name.?, type = m_type})

        count += 1
    }

    rf.return_type = f_type
    rf.parameters = params
    rf.variadic = fc.variadic
    return
}

json_value_to_string :: proc(
    value: json.Value,
    allocator := context.allocator,
) -> (
    s: string,
    err: errors.Error,
) {
    switch v in value {
    case json.Null:
        err = errors.message("can not convert Null to string")
        return
    case i64, f64, bool, string:
        s = fmt.aprint(v, allocator = allocator)
        return
    case json.Array:
        err = errors.message("can not convert an Array to string")
        return
    case json.Object:
        err = errors.message("can not convert an Object to string")
        return
    }

    return
}

INT_SIZES_C :: `
#include <stdio.h>
#define p(type) printf("%zu\n", sizeof(type))

int main() {
  p(char);
  p(short);
  p(int);
  p(long);
  p(long long);
  p(float);
  p(double);
  p(long double);
  p(_Bool);
  p(float _Complex);
  p(double _Complex);
  p(long double _Complex);
  return 0;
}
`

Int_Sizes :: struct {
    char:                uint,
    short:               uint,
    Int:                 uint,
    long:                uint,
    longlong:            uint,
    float:               uint,
    double:              uint,
    long_double:         uint,
    _Bool:               uint,
    float_Complex:       uint,
    double_Complex:      uint,
    long_double_Complex: uint,
}

int_sizes_from_host :: proc() -> (is: Int_Sizes, err: errors.Error) {
    rd: strings.Reader
    rd_str := strings.to_reader(&rd, INT_SIZES_C)

    when ODIN_OS == .Windows {
        is_bin := parser.reserve_random_file("int_sizes{}.exe")
    } else {
        is_bin := parser.reserve_random_file("/tmp/int_sizes{}")
    }
    defer delete(is_bin)
    defer os.remove(is_bin)

    when ODIN_DEBUG {
        fmt.eprintfln("INT_SIZES: zig cc -o \"{}\" --std=c89 -xc -", is_bin)
    }

    status := exec.command(
        "zig",
        {"cc", "-o", is_bin, "--std=c89", "-xc", "-"},
        stdin = rd_str,
    ) or_return

    if status != 0 do return is, errors.message("build failed")

    out: strings.Builder
    defer strings.builder_destroy(&out)
    out_str := strings.to_stream(&out)

    when ODIN_DEBUG {
        fmt.eprintfln("INT_SIZES: \"{}\"", is_bin)
    }

    status = exec.command(
        is_bin,
        {},
        stdout = out_str,
        env = exec.Env.None,
    ) or_return
    if status != 0 do return is, errors.message("execution failed")

    sizes, all_err := strings.split(strings.to_string(out), "\n")
    defer delete(sizes)
    errors.wrap(all_err) or_return

    is.char, _ = strconv.parse_uint(sizes[0])
    is.short, _ = strconv.parse_uint(sizes[1])
    is.Int, _ = strconv.parse_uint(sizes[2])
    is.long, _ = strconv.parse_uint(sizes[3])
    is.longlong, _ = strconv.parse_uint(sizes[4])
    is.float, _ = strconv.parse_uint(sizes[5])
    is.double, _ = strconv.parse_uint(sizes[6])
    is.long_double, _ = strconv.parse_uint(sizes[7])
    is._Bool, _ = strconv.parse_uint(sizes[8])
    is.float_Complex, _ = strconv.parse_uint(sizes[9])
    is.double_Complex, _ = strconv.parse_uint(sizes[10])
    is.long_double_Complex, _ = strconv.parse_uint(sizes[11])

    return
}

int_sizes_from_platform :: proc(plat: runic.Platform) -> (is: Int_Sizes) {
    switch plat.os {
    case .Linux, .Macos, .BSD:
        switch plat.arch {
        case .x86_64, .arm64:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 8,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 16,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 32,
                } \
            )
        }
    case .Windows:
        switch plat.arch {
        case .x86_64, .arm64:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 4,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 8,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 16,
                } \
            )
        }
    }
    return
}

int_type :: proc(sz: uint, signed: bool) -> (t: runic.Builtin) {
    switch sz {
    case 1:
        t = .SInt8
    case 2:
        t = .SInt16
    case 4:
        t = .SInt32
    case 8:
        t = .SInt64
    case 16:
        t = .SInt128
    case:
        t = .Untyped
        return
    }

    if !signed {
        val := transmute(int)t
        val += 5
        t = transmute(runic.Builtin)val
    }
    return
}

bool_type :: proc(sz: uint) -> runic.Builtin {
    switch sz {
    case 1:
        return .Bool8
    case 2:
        return .Bool16
    case 4:
        return .Bool32
    case 8:
        return .Bool64
    }
    return .Untyped
}

float_type :: proc(sz: uint) -> runic.Builtin {
    switch sz {
    case 4:
        return .Float32
    case 8:
        return .Float64
    case 16:
        return .Float128
    }
    return .Untyped
}
