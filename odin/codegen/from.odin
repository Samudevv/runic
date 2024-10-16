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
import odina "core:odin/ast"
import odinp "core:odin/parser"
import odint "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

Import :: struct {
    abs_path: string,
    pkg:      ^odina.Package,
}

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

    rs_arena_alloc := runic.init_runestone(&rs)

    rs.platform = plat
    runic.set_library(plat, &rs, rf)

    packages := runic.platform_value_get([]string, rf.packages, plat)
    overwrite := runic.platform_value_get(
        runic.OverwriteSet,
        rf.overwrite,
        plat,
    )

    anon_counter: int

    for pack in packages {
        pack_name, pack_ok := runic.relative_to_file(
            rune_file_name,
            pack,
            arena_alloc,
        )
        if !pack_ok do continue

        parser: odinp.Parser
        pkg: ^odina.Package = ---
        pkg_ok: bool = ---
        {
            context.allocator = arena_alloc
            pkg, pkg_ok = odinp.parse_package_from_path(pack_name, &parser)
        }
        if !pkg_ok do continue

        file_names, fn_err := slice.map_keys(pkg.files, arena_alloc)
        errors.wrap(fn_err) or_return

        slice.sort(file_names)

        for file_name in file_names {
            file := pkg.files[file_name]

            imports := make(map[string]Import, allocator = arena_alloc)

            for decl in file.decls {
                #partial switch stm in decl.derived_stmt {
                case ^odina.Value_Decl:
                    link_name: Maybe(string)
                    exported: bool

                    for attr in stm.attributes {
                        for elem_expr in attr.elems {
                            #partial switch elem in elem_expr.derived_expr {
                            case ^odina.Ident:
                                switch elem.name {
                                case "export":
                                    exported = true
                                }
                            case ^odina.Field_Value:
                                #partial switch field in
                                    elem.field.derived_expr {
                                case ^odina.Ident:
                                    switch field.name {
                                    case "export":
                                        #partial switch value in
                                            elem.value.derived_expr {
                                        case ^odina.Ident:
                                            switch value.name {
                                            case "true":
                                                exported = true
                                            case "false":
                                            case:
                                                err = error_tok(
                                                    "export needs to be an boolean",
                                                    elem.value.pos,
                                                )
                                                return
                                            }
                                        case:
                                            err = error_tok(
                                                "export needs to be set to an identifier",
                                                elem.value.pos,
                                            )
                                            return
                                        }
                                    case "link_name":
                                        #partial switch value in
                                            elem.value.derived_expr {
                                        case ^odina.Basic_Lit:
                                            link_name = strings.trim_suffix(
                                                strings.trim_prefix(
                                                    value.tok.text,
                                                    `"`,
                                                ),
                                                `"`,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    first_name: Maybe(string)
                    if len(stm.names) != 0 {
                        first_name = name_to_name(stm.names[0]) or_return
                    }

                    decl_type: Maybe(runic.Type)
                    if stm.type != nil {
                        type_err: errors.Error = ---
                        decl_type, type_err = type_to_type(
                            plat,
                            stm.type,
                            first_name,
                            &rs.types,
                            &anon_counter,
                            &imports,
                            nil,
                            overwrite,
                            rs_arena_alloc,
                        )
                        if type_err != nil {
                            fmt.eprintln(type_err)
                            continue
                        }
                    }

                    for name_expr, idx in stm.names {
                        name := name_to_name(name_expr) or_return

                        if len(stm.values) <= idx {
                            if !exported do continue

                            if type, ok := decl_type.?; ok {
                                if link_name != nil {
                                    name = link_name.?
                                }

                                if om.contains(rs.symbols, name) {
                                    fmt.eprintf("{} is defined as \"", name)
                                    sym := om.get(rs.symbols, name)
                                    switch v in sym.value {
                                    case runic.Type:
                                        runic.write_type(
                                            os.stream_from_handle(os.stderr),
                                            v,
                                        )
                                    case runic.Function:
                                        runic.write_function(
                                            os.stream_from_handle(os.stderr),
                                            v,
                                        )
                                    }
                                    fmt.eprintln("\" and \"")
                                    runic.write_type(
                                        os.stream_from_handle(os.stderr),
                                        type,
                                    )
                                    fmt.eprintln('"')
                                }

                                om.insert(
                                    &rs.symbols,
                                    strings.clone(name, rs_arena_alloc),
                                    runic.Symbol{value = type},
                                )
                            }
                            continue
                        }

                        value_expr := stm.values[idx]

                        #partial switch value in value_expr.derived_expr {
                        case ^odina.Proc_Lit:
                            if !exported do continue

                            fn, fn_err := proc_type_to_function(
                                plat,
                                value.type,
                                name,
                                &rs.types,
                                &anon_counter,
                                &imports,
                                nil,
                                overwrite,
                                rs_arena_alloc,
                            )
                            if fn_err != nil {
                                fmt.eprintln(fn_err)
                                continue
                            }

                            if link_name != nil {
                                name = link_name.?
                            }

                            if om.contains(rs.symbols, name) {
                                fmt.eprintf("{} is defined as \"", name)
                                sym := om.get(rs.symbols, name)
                                switch v in sym.value {
                                case runic.Type:
                                    runic.write_type(
                                        os.stream_from_handle(os.stderr),
                                        v,
                                    )
                                case runic.Function:
                                    runic.write_function(
                                        os.stream_from_handle(os.stderr),
                                        v,
                                    )
                                }
                                fmt.eprintln("\" and \"")
                                runic.write_function(
                                    os.stream_from_handle(os.stderr),
                                    fn,
                                )
                                fmt.eprintln('"')
                            }

                            om.insert(
                                &rs.symbols,
                                strings.clone(name, rs_arena_alloc),
                                runic.Symbol{value = fn},
                            )
                        case ^odina.Basic_Lit:
                            const_val: union {
                                i64,
                                f64,
                                string,
                            }
                            const_spec := runic.Builtin.Untyped

                            #partial switch value.tok.kind {
                            case .Integer:
                                if ival, ok := strconv.parse_i64(
                                    value.tok.text,
                                ); !ok {
                                    fmt.eprintfln(
                                        "Failed to parse constant value \"{}\" to integer",
                                        value.tok.text,
                                    )
                                    continue
                                } else {
                                    const_val = ival
                                }
                            case .Float:
                                if fval, ok := strconv.parse_f64(
                                    value.tok.text,
                                ); !ok {
                                    fmt.eprintfln(
                                        "Failed to parse constant value \"{}\" as float",
                                        value.tok.text,
                                    )
                                    continue
                                } else {
                                    const_val = fval
                                }
                            case .String:
                                const_val = strings.clone(
                                    value.tok.text[1:len(value.tok.text) - 1],
                                    rs_arena_alloc,
                                )
                                const_spec = .String
                            case:
                                fmt.eprintfln(
                                    "Constants with token kind {} are not supported",
                                    value.tok.kind,
                                )
                                continue
                            }

                            if om.contains(rs.constants, name) {
                                fmt.eprintfln(
                                    "Constant {} is defined as \"{}\" and \"{}\"",
                                    om.get(rs.constants, name),
                                    const_val,
                                )
                            }

                            om.insert(
                                &rs.constants,
                                strings.clone(name, rs_arena_alloc),
                                runic.Constant {
                                    value = const_val,
                                    type = {spec = const_spec},
                                },
                            )
                        case:
                            type, type_err := type_to_type(
                                plat,
                                value_expr,
                                name,
                                &rs.types,
                                &anon_counter,
                                &imports,
                                nil,
                                overwrite,
                                rs_arena_alloc,
                            )
                            if type_err != nil {
                                fmt.eprintln(type_err)
                                continue
                            }

                            if om.contains(rs.symbols, name) {
                                fmt.eprintf("{} is defined as \"", name)
                                sym := om.get(rs.symbols, name)
                                switch v in sym.value {
                                case runic.Type:
                                    runic.write_type(
                                        os.stream_from_handle(os.stderr),
                                        v,
                                    )
                                case runic.Function:
                                    runic.write_function(
                                        os.stream_from_handle(os.stderr),
                                        v,
                                    )
                                }
                                fmt.eprintln("\" and \"")
                                runic.write_type(
                                    os.stream_from_handle(os.stderr),
                                    type,
                                )
                                fmt.eprintln('"')
                            }

                            om.insert(
                                &rs.types,
                                strings.clone(name, rs_arena_alloc),
                                type,
                            )
                        }
                    }
                case ^odina.Import_Decl:
                    name, imp, imp_err := parse_import(
                        file_name,
                        stm,
                        arena_alloc,
                    )
                    if imp_err != nil {
                        fmt.eprintln(imp_err)
                        continue
                    }
                    imports[name] = imp
                case:
                    fmt.println(
                        error_tok(
                            fmt.aprint(
                                reflect.get_union_variant(decl.derived_stmt).id,
                                allocator = errors.error_allocator,
                            ),
                            decl.pos,
                        ),
                    )
                }
            }
        }
    }

    return
}

proc_type_to_function :: proc(
    plat: runic.Platform,
    p: ^odina.Proc_Type,
    name: Maybe(string),
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    imports: ^map[string]Import,
    current_package: Maybe(^odina.Package),
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    fn: runic.Function,
    err: errors.Error,
) {
    if p.generic do return fn, error_tok("generic proc is not supported", p.tok)

    #partial switch cc in p.calling_convention {
    case string:
        if cc != "\"c\"" do return fn, error_tok(fmt.aprintf("function needs to have c calling convention ({})", cc, allocator = errors.error_allocator), p.tok)
    }

    fn.parameters = make([dynamic]runic.Member, allocator)

    for param_field in p.params.list {
        first_name: Maybe(string)
        if len(param_field.names) != 0 {
            first_name = name_to_name(param_field.names[0]) or_return
        }

        type := type_to_type(
            plat,
            param_field.type,
            first_name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            anon_counter,
            ow,
            allocator,
        ); is_anon {
            om.insert(types, anon_name, anon_type)
            type.spec = anon_name
        }

        if type.pointer_info.count != 0 {
            type.pointer_info.read_only = true
        } else {
            type.read_only = true
        }

        for name_expr in param_field.names {
            name := name_to_name(name_expr) or_return

            append(
                &fn.parameters,
                runic.Member {
                    name = strings.clone(name, allocator),
                    type = type,
                },
            )
        }
    }

    if p.results == nil || len(p.results.list) == 0 {
        fn.return_type.spec = runic.Builtin.Void
        return
    }

    result_struct: runic.Struct
    result_struct.members = make([dynamic]runic.Member, allocator)
    result_idx: int

    for result_field in p.results.list {
        first_name: Maybe(string)
        if len(result_field.names) != 0 {
            first_name = name_to_name(result_field.names[0]) or_return
        }

        type := type_to_type(
            plat,
            result_field.type,
            first_name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            anon_counter,
            ow,
            allocator,
        ); is_anon {
            om.insert(types, anon_name, anon_type)
            type.spec = anon_name
        }

        if len(result_field.names) == 0 {
            append(
                &result_struct.members,
                runic.Member {
                    name = fmt.aprintf(
                        "result{}",
                        result_idx,
                        allocator = allocator,
                    ),
                    type = type,
                },
            )
            result_idx += 1
            continue
        }

        for name_expr in result_field.names {
            defer result_idx += 1

            name: string = ---
            if name_expr == nil {
                name = fmt.aprintf(
                    "result{}",
                    result_idx,
                    allocator = allocator,
                )
            } else {
                name = name_to_name(name_expr) or_return
                if name == "_" {
                    name = fmt.aprintf(
                        "result{}",
                        result_idx,
                        allocator = allocator,
                    )
                }
            }

            append(
                &result_struct.members,
                runic.Member {
                    name = strings.clone(name, allocator),
                    type = type,
                },
            )
        }
    }

    if len(result_struct.members) == 1 {
        fn.return_type = result_struct.members[0].type
        delete(result_struct.members[0].name, allocator)
        delete(result_struct.members)
    } else {
        result_type_name := fmt.aprintf(
            "{}_result",
            name.? if name != nil else "proc",
            allocator = allocator,
        )
        fn.return_type.spec = result_type_name
        om.insert(types, result_type_name, runic.Type{spec = result_struct})
    }

    return
}

name_to_name :: proc(name: ^odina.Expr) -> (nm: string, err: errors.Error) {
    #partial switch n in name.derived_expr {
    case ^odina.Ident:
        nm = n.name
    case:
        err = error_tok("name has to be an identifier", name.pos)
    }
    return
}

type_to_type :: proc(
    plat: runic.Platform,
    t: ^odina.Expr,
    name: Maybe(string),
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    imports: ^map[string]Import,
    current_package: Maybe(^odina.Package),
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    #partial switch type_expr in t.derived_expr {
    case ^odina.Ident:
        type.spec = type_identifier_to_type_specifier(
            plat,
            type_expr.name,
            allocator,
        ) or_return

        if type_name, ok := type.spec.(string); ok {
            pkg: ^odina.Package = ---
            if pkg, ok = current_package.?; ok {
                prefix_type_name := fmt.aprintf(
                    "{}_{}",
                    pkg.name,
                    type_name,
                    allocator = allocator,
                )

                if !om.contains(types^, prefix_type_name) {
                    om.insert(
                        types,
                        prefix_type_name,
                        runic.Type{spec = runic.Unknown(prefix_type_name)},
                    )
                    type = lookup_type_in_package(
                        plat,
                        type_name,
                        pkg,
                        types,
                        anon_counter,
                        ow,
                        allocator,
                    ) or_return
                    om.insert(types, prefix_type_name, type)
                }

                type.spec = prefix_type_name
            }
        }
    case ^odina.Pointer_Type:
        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return
        if len(type.array_info) != 0 {
            type.array_info[len(type.array_info) - 1].pointer_info.count += 1
        } else {
            type.pointer_info.count += 1
        }
    case ^odina.Array_Type:
        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return

        if len(type.array_info) == 0 {
            type.array_info = make([dynamic]runic.Array, allocator)
        }

        size: runic.ArraySize
        #partial switch l in type_expr.len.derived_expr {
        case ^odina.Basic_Lit:
            #partial switch l.tok.kind {
            case .Integer:
                value, ok := strconv.parse_u64(l.tok.text)
                errors.wrap(ok) or_return
                size = value
            }
        }

        append(&type.array_info, runic.Array{size = size})
    case ^odina.Multi_Pointer_Type:
        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return
        if len(type.array_info) != 0 {
            type.array_info[len(type.array_info) - 1].pointer_info.count += 1
        } else {
            type.pointer_info.count += 1
        }
    case ^odina.Enum_Type:
        e: runic.Enum
        if type_expr.base_type == nil {
            switch plat.arch {
            case .Any:
                panic("invalid arch any")
            case .x86_64, .arm64:
                e.type = .SInt64
            case .x86, .arm32:
                e.type = .SInt32
            }
        } else {
            et := type_to_type(
                plat,
                type_expr.base_type,
                name,
                types,
                anon_counter,
                imports,
                current_package,
                ow,
                allocator,
            ) or_return

            ok: bool = ---
            e.type, ok = et.spec.(runic.Builtin)
            errors.wrap(ok) or_return
        }

        e.entries = make([dynamic]runic.EnumEntry, allocator)

        counter: i64
        for field in type_expr.fields {
            #partial switch f in field.derived_expr {
            case ^odina.Ident:
                append(
                    &e.entries,
                    runic.EnumEntry {
                        name = strings.clone(f.name, allocator),
                        value = counter,
                    },
                )
            case ^odina.Field_Value:
                name: string = ---
                if name_ident, ok := f.field.derived_expr.(^odina.Ident); !ok {
                    err = error_tok(
                        "enum entry needs to be an identifier",
                        f.field.pos,
                    )
                    return
                } else {
                    name = strings.clone(name_ident.name, allocator)
                }

                value := evaluate_expr(i64, f.value) or_return
                counter = value

                append(&e.entries, runic.EnumEntry{name = name, value = value})
            case:
                err = error_tok("invalid enum entry", field.pos)
                return
            }

            counter += 1
        }

        type.spec = e
    case ^odina.Struct_Type:
        if type_expr.is_raw_union {
            u := struct_type_to_union(
                plat,
                type_expr,
                types,
                anon_counter,
                imports,
                current_package,
                ow,
                allocator,
            ) or_return
            type.spec = u
            return
        }
        s := struct_type_to_struct(
            plat,
            type_expr,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return
        type.spec = s
        return
    case ^odina.Selector_Expr:
        errors.assert(
            type_expr.op.kind == .Period,
            fmt.aprint(type_expr.op.kind, allocator = errors.error_allocator),
        ) or_return

        pkg, ok := type_expr.expr.derived_expr.(^odina.Ident)
        errors.wrap(
            ok,
            fmt.aprint(
                reflect.get_union_variant(type_expr.expr.derived_expr).id,
                allocator = errors.error_allocator,
            ),
        ) or_return

        type_name := type_expr.field.name

        if pkg.name == "builtin" {
            type = type_to_type(
                plat,
                &type_expr.field.node,
                type_name,
                types,
                anon_counter,
                imports,
                nil,
                ow,
                allocator,
            ) or_return
            return
        } else {
            type = lookup_type_of_import(
                plat,
                imports,
                pkg.name,
                type_name,
                types,
                anon_counter,
                ow,
                allocator,
            ) or_return
        }

        type_name = fmt.aprintf(
            "{}_{}",
            pkg.name,
            type_name,
            allocator = allocator,
        )

        om.insert(types, type_name, type)
        type.spec = type_name
    case ^odina.Helper_Type:
        type, err = type_to_type(
            plat,
            type_expr.type,
            name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        )
    case ^odina.Proc_Type:
        func := proc_type_to_function(
            plat,
            type_expr,
            name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return

        type.spec = runic.FunctionPointer(new_clone(func, allocator))
    case:
        fmt.eprintln(
            error_tok(
                fmt.aprintf(
                    "type {} not supported",
                    reflect.get_union_variant(t.derived_expr).id,
                    allocator = errors.error_allocator,
                ),
                t.pos,
            ),
        )
        type.spec = runic.Builtin.RawPtr
    }
    return
}

type_identifier_to_type_specifier :: proc(
    plat: runic.Platform,
    ident: string,
    allocator := context.allocator,
) -> (
    t: runic.TypeSpecifier,
    err: errors.Error,
) {
    using runic.Builtin

    switch ident {
    case "int":
        switch plat.arch {
        case .Any:
            panic("invalid arch Any")
        case .x86_64, .arm64:
            t = SInt64
        case .x86, .arm32:
            t = SInt32
        }
    case "uint":
        switch plat.arch {
        case .Any:
            panic("invalid arch Any")
        case .x86_64, .arm64:
            t = UInt64
        case .x86, .arm32:
            t = UInt32
        }
    case "i8":
        t = SInt8
    case "i16":
        t = SInt16
    case "i32":
        t = SInt32
    case "i64":
        t = SInt64
    case "byte":
        t = UInt8
    case "u8":
        t = UInt8
    case "u16":
        t = UInt16
    case "u32":
        t = UInt32
    case "u64":
        t = UInt64
    case "uintptr":
        t = UInt64
    case "f16":
        err = errors.message("f16 is not supported")
    case "f32":
        t = Float32
    case "f64":
        t = Float64
    case "rune":
        t = SInt32
    case "cstring":
        t = String
    case "rawptr":
        t = RawPtr
    case "bool":
        switch plat.arch {
        case .Any:
            panic("invalid arch Any")
        case .x86_64, .arm64:
            t = Bool64
        case .x86, .arm32:
            t = Bool32
        }
    case "b8":
        t = Bool8
    case "b16":
        t = Bool16
    case "b32":
        t = Bool32
    case "b64":
        t = Bool64
    case "i128",
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
         "any":
        err = errors.message("{} is not supported", ident)
    case:
        t = strings.clone(ident, allocator)
    }

    return
}

struct_type_to_union :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    imports: ^map[string]Import,
    current_package: Maybe(^odina.Package),
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    u: runic.Union,
    err: errors.Error,
) {
    s := struct_type_to_struct(
        plat,
        st,
        types,
        anon_counter,
        imports,
        current_package,
        ow,
        allocator,
    ) or_return
    u.members = s.members
    return
}

struct_type_to_struct :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    imports: ^map[string]Import,
    current_package: Maybe(^odina.Package),
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    s: runic.Struct,
    err: errors.Error,
) {
    if st.poly_params != nil do return s, error_tok("poly_params is not supported", st.pos)
    if st.align != nil do return s, error_tok("struct alignment is not supported", st.align.pos)
    if st.is_packed do return s, error_tok("packed structs are not supported", st.pos)

    s.members = make([dynamic]runic.Member, allocator)

    for field in st.fields.list {
        first_name: Maybe(string)
        if len(field.names) != 0 {
            first_name = name_to_name(field.names[0]) or_return
        }

        type := type_to_type(
            plat,
            field.type,
            first_name,
            types,
            anon_counter,
            imports,
            current_package,
            ow,
            allocator,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            anon_counter,
            ow,
            allocator,
        ); is_anon {
            om.insert(types, anon_name, anon_type)
            type.spec = anon_name
        }

        for name_expr in field.names {
            name := name_to_name(name_expr) or_return

            append(
                &s.members,
                runic.Member {
                    name = strings.clone(name, allocator),
                    type = type,
                },
            )
        }
    }

    return
}

error_tok :: proc(msg: string, tok: union #no_nil {
        odint.Token,
        odint.Pos,
    }, loc := #caller_location) -> string {
    switch t in tok {
    case odint.Token:
        return errors.message(
            "{}:{}:{}: {}",
            t.pos.file,
            t.pos.line,
            t.pos.column,
            msg,
            loc = loc,
        )
    case odint.Pos:
        return errors.message(
            "{}:{}:{}: {}",
            t.file,
            t.line,
            t.column,
            msg,
            loc = loc,
        )
    }

    return errors.empty(loc = loc)
}

evaluate_expr :: proc(
    $T: typeid,
    expr: ^odina.Expr,
    loc := #caller_location,
) -> (
    rs: T,
    err: errors.Error,
) {
    #partial switch e in expr.derived_expr {
    case ^odina.Basic_Lit:
        if reflect.is_integer(type_info_of(T)) {
            value, ok := strconv.parse_i64(e.tok.text)
            errors.wrap(
                ok,
                fmt.aprintf(
                    "{}:{}:{}",
                    e.tok.pos.file,
                    e.tok.pos.line,
                    e.tok.pos.column,
                    allocator = errors.error_allocator,
                ),
                loc = loc,
            ) or_return
            rs = T(value)
            return
        } else if reflect.is_float(type_info_of(T)) {
            value, ok := strconv.parse_f64(e.tok.text)
            errors.wrap(
                ok,
                fmt.aprintf(
                    "{}:{}:{}",
                    e.tok.pos.file,
                    e.tok.pos.line,
                    e.tok.pos.column,
                    allocator = errors.error_allocator,
                ),
                loc = loc,
            ) or_return
            rs = T(value)
            return
        } else {
            err = error_tok("not a number", expr.pos)
            return
        }
    case ^odina.Binary_Expr:
        left := evaluate_expr(T, e.left, loc) or_return
        right := evaluate_expr(T, e.right, loc) or_return

        #partial switch e.op.kind {
        case .Add:
            rs = left + right
            return
        case .Sub:
            rs = left - right
            return
        case .Mul:
            rs = left * right
            return
        case .Quo:
            rs = left / right
            return
        case .Mod:
            rs = left % right
            return
        case .And:
            rs = left & right
            return
        case .Or:
            rs = left | right
            return
        case .Xor:
            rs = left ~ right
            return
        case .And_Not:
            rs = left &~ right
            return
        case .Shl:
            rs = left << u64(right)
            return
        case .Shr:
            rs = left >> u64(right)
            return
        case .Cmp_And:
            rs = T(b64(left) && b64(right))
            return
        case .Cmp_Or:
            rs = T(b64(left) && b64(right))
            return
        case:
            err = error_tok(
                fmt.aprintf(
                    "unsupported operator {}",
                    e.op.kind,
                    allocator = errors.error_allocator,
                ),
                e.pos,
                loc = loc,
            )
            return
        }
    case ^odina.Paren_Expr:
        rs, err = evaluate_expr(T, e.expr, loc)
        return
    case:
        err = error_tok(
            fmt.aprintf(
                "unsupported expression {}",
                reflect.get_union_variant(expr.derived_expr).id,
                allocator = errors.error_allocator,
            ),
            expr.pos,
            loc = loc,
        )
        return
    }

    err = errors.empty(loc = loc)
    return
}

parse_import :: proc(
    file_name: string,
    stm: ^odina.Import_Decl,
    allocator := context.allocator,
) -> (
    name: string,
    imp: Import,
    err: errors.Error,
) {
    col_path, a_err := strings.split_n(
        strings.trim_suffix(strings.trim_prefix(stm.fullpath, `"`), `"`),
        ":",
        2,
        allocator,
    )
    errors.wrap(a_err, "import") or_return

    collection, path: string = ---, ---
    if len(col_path) == 2 {
        collection, path = col_path[0], col_path[1]
    } else {
        collection = ""
        path = col_path[0]
    }

    switch collection {
    case "core", "base", "vendor":
        path = filepath.join({ODIN_ROOT, collection, path}, allocator)
    case "":
        ok: bool = ---
        path, ok = runic.relative_to_file(file_name, path, allocator)
        errors.wrap(ok, "import relative") or_return
    case:
        err = error_tok("unknown collection", stm.relpath)
        return
    }

    if len(stm.name.text) != 0 {
        name = stm.name.text
    } else {
        name = filepath.base(path)
    }

    imp.abs_path = path
    return
}

lookup_type_of_import :: proc(
    plat: runic.Platform,
    imports: ^map[string]Import,
    pkg, type_name: string,
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    imp, ok := imports[pkg]
    errors.wrap(
        ok,
        fmt.aprint(
            "package",
            pkg,
            "does not exist in",
            slice.map_keys(imports^, allocator = errors.error_allocator),
            allocator = errors.error_allocator,
        ),
    ) or_return

    if imp.pkg == nil {
        context.allocator = allocator

        p: odinp.Parser
        p.flags = {.Optional_Semicolons}
        p.err = proc(pos: odint.Pos, msg: string, args: ..any) {
            whole_msg := fmt.aprintf(
                msg,
                ..args,
                allocator = errors.error_allocator,
            )
            if strings.has_prefix(whole_msg, "use of reserved package name") do return

            fmt.eprintln(error_tok(whole_msg, pos))
        }

        imp.pkg, ok = odinp.parse_package_from_path(imp.abs_path, &p)
        errors.wrap(
            ok,
            fmt.aprintf(
                "package {} at {} failed to parse",
                pkg,
                imp.abs_path,
                allocator = errors.error_allocator,
            ),
        ) or_return
    }

    type, err = lookup_type_in_package(
        plat,
        type_name,
        imp.pkg,
        types,
        anon_counter,
        ow,
        allocator,
    )

    return
}

lookup_type_in_package :: proc(
    plat: runic.Platform,
    type_name: string,
    pkg: ^odina.Package,
    types: ^om.OrderedMap(string, runic.Type),
    anon_counter: ^int,
    ow: runic.OverwriteSet,
    allocator := context.allocator,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    for file_name, file in pkg.files {
        local_imports := make(map[string]Import, allocator = allocator)

        for decl in file.decls {
            #partial switch stm in decl.derived_stmt {
            case ^odina.Import_Decl:
                name, impo := parse_import(file_name, stm, allocator) or_return
                local_imports[name] = impo
            case ^odina.Value_Decl:
                for name_expr, idx in stm.names {
                    if len(stm.values) <= idx {
                        continue
                    }

                    name := name_to_name(name_expr) or_return

                    if name == type_name {
                        value_expr := stm.values[idx]

                        type, err = type_to_type(
                            plat,
                            value_expr,
                            name,
                            types,
                            anon_counter,
                            &local_imports,
                            pkg,
                            ow,
                            allocator,
                        )
                        return
                    }
                }
            }
        }
    }

    err = errors.message("type {} not found in {}", type_name, pkg.name)
    return
}

