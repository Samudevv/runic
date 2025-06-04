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

@(private)
Import :: struct {
    collection: string,
    name:       string,
    abs_path:   string,
    pkg:        ^odina.Package,
}


@(private)
TypeToTypeContext :: struct {
    types:           ^om.OrderedMap(string, runic.Type),
    anon_counter:    ^int,
    imports:         ^map[string]Import,
    current_package: Maybe(^odina.Package),
    ow:              runic.OverwriteSet,
    allocator:       runtime.Allocator,
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

    ttt_ctx := TypeToTypeContext {
        types = &rs.types,
        anon_counter = &anon_counter,
        ow = overwrite,
        allocator = rs_arena_alloc,
    }

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

            imports := make(map[string]Import)
            defer delete(imports)

            ttt_ctx.imports = &imports

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
                            &ttt_ctx,
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
                                &ttt_ctx,
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
                                &ttt_ctx,
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
    ctx: ^TypeToTypeContext,
) -> (
    fn: runic.Function,
    err: errors.Error,
) {
    if p.generic do return fn, error_tok("generic proc is not supported", p.tok)

    #partial switch cc in p.calling_convention {
    case string:
        if cc != "\"c\"" do return fn, error_tok(fmt.aprintf("function needs to have c calling convention ({})", cc, allocator = errors.error_allocator), p.tok)
    }

    fn.parameters = make(
        [dynamic]runic.Member,
        allocator = ctx.allocator,
        len = 0,
        cap = len(p.params.list),
    )

    for param_field in p.params.list {
        first_name: Maybe(string)
        if len(param_field.names) != 0 {
            first_name = name_to_name(param_field.names[0]) or_return
        }

        type := type_to_type(
            plat,
            param_field.type,
            first_name,
            ctx,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            ctx.anon_counter,
            ctx.ow,
            ctx.allocator,
        ); is_anon {
            om.insert(ctx.types, anon_name, anon_type)
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
                    name = strings.clone(name, ctx.allocator),
                    type = type,
                },
            )
        }
    }

    if p.results == nil || len(p.results.list) == 0 {
        fn.return_type.spec = runic.Builtin.Untyped
        return
    }

    result_struct: runic.Struct
    result_struct.members = make(
        [dynamic]runic.Member,
        allocator = ctx.allocator,
        len = 0,
        cap = len(p.results.list),
    )
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
            ctx,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            ctx.anon_counter,
            ctx.ow,
            ctx.allocator,
        ); is_anon {
            om.insert(ctx.types, anon_name, anon_type)
            type.spec = anon_name
        }

        if len(result_field.names) == 0 {
            append(
                &result_struct.members,
                runic.Member {
                    name = fmt.aprintf(
                        "result{}",
                        result_idx,
                        allocator = ctx.allocator,
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
                    allocator = ctx.allocator,
                )
            } else {
                name = name_to_name(name_expr) or_return
                if name == "_" {
                    name = fmt.aprintf(
                        "result{}",
                        result_idx,
                        allocator = ctx.allocator,
                    )
                }
            }

            append(
                &result_struct.members,
                runic.Member {
                    name = strings.clone(name, ctx.allocator),
                    type = type,
                },
            )
        }
    }

    if len(result_struct.members) == 1 {
        fn.return_type = result_struct.members[0].type
        delete(result_struct.members[0].name, ctx.allocator)
        delete(result_struct.members)
    } else {
        result_type_name := fmt.aprintf(
            "{}_result",
            name.? if name != nil else "proc",
            allocator = ctx.allocator,
        )
        fn.return_type.spec = result_type_name
        om.insert(ctx.types, result_type_name, runic.Type{spec = result_struct})
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
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    #partial switch type_expr in t.derived_expr {
    case ^odina.Ident:
        switch type_expr.name {
        case "string":
            if !om.contains(ctx.types^, "string") {
                string_type: runic.Struct = ---
                string_type.members = make(
                    [dynamic]runic.Member,
                    len = 2,
                    cap = 2,
                    allocator = ctx.allocator,
                )

                string_type.members[0].name = "data"
                string_type.members[0].type.spec = runic.Builtin.UInt8
                string_type.members[0].type.pointer_info.count = 1

                string_type.members[1].name = "length"
                switch plat.arch {
                case .x86, .arm32:
                    string_type.members[1].type.spec = runic.Builtin.SInt32
                case .x86_64, .arm64:
                    string_type.members[1].type.spec = runic.Builtin.SInt64
                case .Any:
                    string_type.members[1].type.spec = runic.Builtin.Untyped
                }

                om.insert(ctx.types, "string", runic.Type{spec = string_type})
            }

            type.spec = string("string")
        case:
            type.spec = type_identifier_to_type_specifier(
                plat,
                type_expr.name,
                ctx.allocator,
            ) or_return

            if type_name, ok := type.spec.(string); ok {
                pkg: ^odina.Package = ---
                if pkg, ok = ctx.current_package.?; ok {
                    prefix_type_name := fmt.aprintf(
                        "{}_{}",
                        pkg.name,
                        type_name,
                        allocator = ctx.allocator,
                    )

                    if !om.contains(ctx.types^, prefix_type_name) {
                        om.insert(
                            ctx.types,
                            prefix_type_name,
                            runic.Type{spec = runic.Unknown(prefix_type_name)},
                        )
                        type = lookup_type_in_package(
                            plat,
                            type_name,
                            pkg,
                            ctx,
                        ) or_return
                        om.insert(ctx.types, prefix_type_name, type)
                    }

                    type.spec = prefix_type_name
                }
            }
        }
    case ^odina.Pointer_Type:
        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            ctx,
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
            ctx,
        ) or_return

        if len(type.array_info) == 0 {
            type.array_info = make([dynamic]runic.Array, ctx.allocator)
        }

        if type_expr.len != nil {
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
        } else {
            // Slice
            // TODO: are slices from different packages working?
            // TODO: output the name in different casing (camelCase, PascalCase etc.)
            // TODO: add prefix/suffix to name maybe?

            slice_name_elements := make([dynamic]string, len = 0, cap = 3) // []^[5]int

            needs_anon := false
            slice_name_loop: for expr := type_expr.elem; expr != nil; {
                #partial switch de in expr.derived_expr {
                case ^odina.Ident:
                    append(&slice_name_elements, de.name)
                    break slice_name_loop
                case ^odina.Array_Type:
                    if de.len != nil {
                        #partial switch l in de.len.derived_expr {
                        case ^odina.Ident:
                            append(&slice_name_elements, l.name)
                        case ^odina.Basic_Lit:
                            #partial switch l.tok.kind {
                            case .Integer:
                                append(&slice_name_elements, l.tok.text)
                            case:
                                append(&slice_name_elements, "unknown")
                            }
                        case:
                            append(&slice_name_elements, "unknown")
                            needs_anon = true
                        }

                        append(&slice_name_elements, "array")
                    } else {
                        append(&slice_name_elements, "slice")
                    }

                    expr = de.elem
                    continue
                case ^odina.Dynamic_Array_Type:
                    append(&slice_name_elements, "dynamic_array")
                    expr = de.elem
                    continue
                case ^odina.Pointer_Type:
                    append(&slice_name_elements, "pointer")
                    expr = de.elem
                    continue
                case:
                    append(&slice_name_elements, "unknown")
                    needs_anon = true
                    break slice_name_loop
                }

                break
            }

            slice_name_bd: strings.Builder
            strings.builder_init(&slice_name_bd, allocator = ctx.allocator)

            #reverse for e in slice_name_elements {
                strings.write_string(&slice_name_bd, e)
                strings.write_rune(&slice_name_bd, '_')
            }
            delete(slice_name_elements)

            strings.write_string(&slice_name_bd, "slice")

            if needs_anon {
                strings.write_rune(&slice_name_bd, '_')
                strings.write_int(&slice_name_bd, ctx.anon_counter^)
                ctx.anon_counter^ += 1
            }

            slice_name := strings.to_string(slice_name_bd)

            if needs_anon || !om.contains(ctx.types^, slice_name) {
                slice_type: runic.Struct = ---
                slice_type.members = make(
                    [dynamic]runic.Member,
                    len = 2,
                    cap = 2,
                    allocator = ctx.allocator,
                )

                slice_type.members[0].name = "data"
                slice_type.members[0].type = type
                if len(slice_type.members[0].type.array_info) != 0 {
                    slice_type.members[0].type.array_info[len(slice_type.members[0].type.array_info) - 1].pointer_info.count +=
                    1
                } else {
                    slice_type.members[0].type.pointer_info.count += 1
                }

                slice_type.members[1].name = "length"
                switch plat.arch {
                case .x86, .arm32:
                    slice_type.members[1].type.spec = runic.Builtin.SInt32
                case .x86_64, .arm64:
                    slice_type.members[1].type.spec = runic.Builtin.SInt64
                case .Any:
                    slice_type.members[1].type.spec = runic.Builtin.Untyped
                }

                om.insert(ctx.types, slice_name, runic.Type{spec = slice_type})
            }

            type = runic.Type {
                spec = slice_name,
            }
        }
    case ^odina.Multi_Pointer_Type:
        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            ctx,
        ) or_return
        if len(type.array_info) != 0 {
            type.array_info[len(type.array_info) - 1].pointer_info.count += 1
        } else {
            type.pointer_info.count += 1
        }
    case ^odina.Dynamic_Array_Type:
        // TODO: find out what 'tag' does

        type = type_to_type(
            plat,
            type_expr.elem,
            name,
            ctx,
        ) or_return

        dyn_name_elements := make([dynamic]string, len = 0, cap = 3) // [dynamic]^[5]int

        needs_anon := false
        dyn_name_loop: for expr := type_expr.elem; expr != nil; {
            #partial switch de in expr.derived_expr {
            case ^odina.Ident:
                append(&dyn_name_elements, de.name)
                break dyn_name_loop
            case ^odina.Array_Type:
                if de.len != nil {
                    #partial switch l in de.len.derived_expr {
                    case ^odina.Ident:
                        append(&dyn_name_elements, l.name)
                    case ^odina.Basic_Lit:
                        #partial switch l.tok.kind {
                        case .Integer:
                            append(&dyn_name_elements, l.tok.text)
                        case:
                            append(&dyn_name_elements, "unknown")
                        }
                    case:
                        append(&dyn_name_elements, "unknown")
                        needs_anon = true
                    }

                    append(&dyn_name_elements, "array")
                } else {
                    append(&dyn_name_elements, "slice")
                }

                expr = de.elem
                continue
            case ^odina.Dynamic_Array_Type:
                append(&dyn_name_elements, "dynamic_array")
                expr = de.elem
                continue
            case ^odina.Pointer_Type:
                append(&dyn_name_elements, "pointer")
                expr = de.elem
                continue
            case:
                append(&dyn_name_elements, "unknown")
                needs_anon = true
                break dyn_name_loop
            }

            break
        }

        dyn_name_bd: strings.Builder
        strings.builder_init(&dyn_name_bd, allocator = ctx.allocator)

        #reverse for e in dyn_name_elements {
            strings.write_string(&dyn_name_bd, e)
            strings.write_rune(&dyn_name_bd, '_')
        }
        delete(dyn_name_elements)

        strings.write_string(&dyn_name_bd, "dynamic_array")

        if needs_anon {
            strings.write_rune(&dyn_name_bd, '_')
            strings.write_int(&dyn_name_bd, ctx.anon_counter^)
            ctx.anon_counter^ += 1
        }

        dynamic_array_name := strings.to_string(dyn_name_bd)

        if needs_anon || !om.contains(ctx.types^, dynamic_array_name) {
            dynamic_array_type: runic.Struct = ---
            dynamic_array_type.members = make(
                [dynamic]runic.Member,
                len = 4,
                cap = 4,
                allocator = ctx.allocator,
            )

            dynamic_array_type.members[0].name = "data"
            dynamic_array_type.members[0].type = type
            if len(dynamic_array_type.members[0].type.array_info) != 0 {
                dynamic_array_type.members[0].type.array_info[len(dynamic_array_type.members[0].type.array_info) - 1].pointer_info.count +=
                1
            } else {
                dynamic_array_type.members[0].type.pointer_info.count += 1
            }

            dynamic_array_type.members[1].name = "length"
            switch plat.arch {
            case .x86, .arm32:
                dynamic_array_type.members[1].type.spec = runic.Builtin.SInt32
            case .x86_64, .arm64:
                dynamic_array_type.members[1].type.spec = runic.Builtin.SInt64
            case .Any:
                dynamic_array_type.members[1].type.spec = runic.Builtin.Untyped
            }

            dynamic_array_type.members[2].name = "capacity"
            switch plat.arch {
            case .x86, .arm32:
                dynamic_array_type.members[2].type.spec = runic.Builtin.SInt32
            case .x86_64, .arm64:
                dynamic_array_type.members[2].type.spec = runic.Builtin.SInt64
            case .Any:
                dynamic_array_type.members[2].type.spec = runic.Builtin.Untyped
            }

            dynamic_array_type.members[3].name = "allocator"
            dynamic_array_type.members[3].type.spec = string(
                "runtime_Allocator",
            )

            if !om.contains(ctx.types^, "runtime_Allocator") {
                allocator_type := lookup_type_of_import(
                    plat,
                    "runtime",
                    "Allocator",
                    ctx,
                ) or_return
                om.insert(ctx.types, "runtime_Allocator", allocator_type)
            }

            om.insert(
                ctx.types,
                dynamic_array_name,
                runic.Type{spec = dynamic_array_type},
            )
        }

        type = runic.Type {
            spec = dynamic_array_name,
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
                ctx,
            ) or_return

            ok: bool = ---
            e.type, ok = et.spec.(runic.Builtin)
            errors.wrap(ok) or_return
        }

        e.entries = make(
            [dynamic]runic.EnumEntry,
            len = 0,
            cap = len(type_expr.fields),
            allocator = ctx.allocator,
        )

        counter: i64
        for field in type_expr.fields {
            #partial switch f in field.derived_expr {
            case ^odina.Ident:
                append(
                    &e.entries,
                    runic.EnumEntry {
                        name = strings.clone(f.name, ctx.allocator),
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
                    name = strings.clone(name_ident.name, ctx.allocator)
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
                ctx,
            ) or_return
            type.spec = u
            return
        }
        s := struct_type_to_struct(
            plat,
            type_expr,
            ctx,
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

        type = lookup_type_of_import(
            plat,
            pkg.name,
            type_name,
            ctx,
        ) or_return

        imp, imp_ok := ctx.imports^[pkg.name]
        errors.assert(imp_ok, "import was expected to exist") or_return

        if imp.name != "builtin" {
            type_name = fmt.aprintf(
                "{}_{}",
                imp.name,
                type_name,
                allocator = ctx.allocator,
            )

            om.insert(ctx.types, type_name, type)
            type = runic.Type {
                spec = type_name,
            }
        }
    case ^odina.Helper_Type:
        type, err = type_to_type(
            plat,
            type_expr.type,
            name,
            ctx,
        )
    case ^odina.Proc_Type:
        func := proc_type_to_function(
            plat,
            type_expr,
            name,
            ctx,
        ) or_return

        type.spec = runic.FunctionPointer(new_clone(func, ctx.allocator))
    case ^odina.Bit_Set_Type:
        // TODO: Handle the case where the enum is defined after the bit_set and such similar cases
        bit_set_type: Maybe(runic.Type)

        underlying: runic.TypeSpecifier
        underlying_name: string

        if type_expr.underlying != nil {
            #partial switch d in type_expr.underlying.derived_expr {
            case ^odina.Ident:
                underlying_name = d.name
                underlying = type_identifier_to_type_specifier(
                    plat,
                    d.name,
                    ctx.allocator,
                ) or_return

                bit_set_type = runic.Type {
                    spec = underlying,
                }
            case:
                err = error_tok(
                    "underlying type of bit_set must be Ident",
                    t.pos,
                )
                return
            }
        }

        elem_name: string

        #partial switch e in type_expr.elem.derived_expr {
        case ^odina.Ident:
            elem_name = e.name

            if underlying == nil {
                if elem_type, ok := om.get(ctx.types^, e.name); ok {
                    if enum_type, enum_ok := elem_type.spec.(runic.Enum);
                       enum_ok {
                        bit_set_type = bit_set_type_from_enum(
                            enum_type,
                            ctx.allocator,
                        )
                    } else {
                        err = error_tok(
                            "bit_set does not refer to an enum",
                            t.pos,
                        )
                        return
                    }
                }
            }
        case ^odina.Binary_Expr:
            // TODO
            elem_name = "range"
            err = errors.not_implemented()
            return
        case ^odina.Enum_Type:
            // TODO
            elem_name = "anon"
            err = errors.not_implemented()
            return
        case ^odina.Selector_Expr:
            // TODO
            err = errors.not_implemented()
            return
        case:
            err = error_tok(
                fmt.aprintf(
                    "invalid bit_set elem={}",
                    reflect.get_union_variant(type_expr.elem.derived_expr).id,
                    allocator = errors.error_allocator,
                ),
                t.pos,
            )
            return
        }

        bit_set_type_name: strings.Builder
        strings.builder_init(&bit_set_type_name, allocator = ctx.allocator)

        strings.write_string(&bit_set_type_name, "bit_set_")
        strings.write_string(&bit_set_type_name, elem_name)
        if underlying != nil {
            strings.write_rune(&bit_set_type_name, '_')
            strings.write_string(&bit_set_type_name, underlying_name)
        }
        // TODO: Handle anon counter

        if bit_set_type != nil {
            if !om.contains(ctx.types^, strings.to_string(bit_set_type_name)) {
                om.insert(
                    ctx.types,
                    strings.to_string(bit_set_type_name),
                    bit_set_type.?,
                )
            }
        }

        type.spec = strings.to_string(bit_set_type_name)
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
        type.spec = runic.Builtin.Opaque
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
         "typeid",
         "any":
        err = errors.message("{} is not supported", ident)
    case "string":
        err = errors.message(
            "{} should not be used with this procedure",
            ident,
        )
    case:
        t = strings.clone(ident, allocator)
    }

    return
}

struct_type_to_union :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    ctx: ^TypeToTypeContext,
) -> (
    u: runic.Union,
    err: errors.Error,
) {
    s := struct_type_to_struct(
        plat,
        st,
        ctx,
    ) or_return
    u.members = s.members
    return
}

struct_type_to_struct :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    ctx: ^TypeToTypeContext,
) -> (
    s: runic.Struct,
    err: errors.Error,
) {
    if st.poly_params != nil do return s, error_tok("poly_params is not supported", st.pos)
    if st.align != nil do return s, error_tok("struct alignment is not supported", st.align.pos)
    if st.is_packed do return s, error_tok("packed structs are not supported", st.pos)

    s.members = make(
        [dynamic]runic.Member,
        allocator = ctx.allocator,
        len = 0,
        cap = len(st.fields.list),
    )

    for field in st.fields.list {
        first_name: Maybe(string)
        if len(field.names) != 0 {
            first_name = name_to_name(field.names[0]) or_return
        }

        type := type_to_type(
            plat,
            field.type,
            first_name,
            ctx,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            ctx.anon_counter,
            ctx.ow,
            ctx.allocator,
        ); is_anon {
            om.insert(ctx.types, anon_name, anon_type)
            type.spec = anon_name
        }

        for name_expr in field.names {
            name := name_to_name(name_expr) or_return

            append(
                &s.members,
                runic.Member {
                    name = strings.clone(name, ctx.allocator),
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
    imp.name = filepath.base(path)
    imp.collection = collection
    return
}

lookup_type_of_import :: proc(
    plat: runic.Platform,
    pkg, type_name: string,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    imp, ok := ctx.imports^[pkg]

    if !ok || imp.pkg == nil {
        if !ok {
            // Allow loading of base collection packages even if they have not been imported
            switch pkg {
            case "runtime", "builtin", "intrinsics", "sanitizer":
                imp = Import {
                    abs_path   = "",
                    pkg        = nil,
                    name       = pkg,
                    collection = "base",
                }
            case:
                imp = Import{}
            }
        }

        if imp.collection == "base" {
            switch imp.name {
            case "builtin":
                // A hack, because the 'builtin' package only has identifiers
                ident := odina.Ident {
                    name = type_name,
                }
                type_expr := odina.Expr {
                    derived_expr = &ident,
                }

                type = type_to_type(
                    plat,
                    &type_expr,
                    type_name,
                    ctx,
                ) or_return
                return
            case "runtime":
                // TODO: Implement more types
                switch type_name {
                case "Allocator":
                    s: runic.Struct = ---
                    s.members = make(
                        [dynamic]runic.Member,
                        len = 2,
                        cap = 2,
                        allocator = ctx.allocator,
                    )

                    s.members[0].name = "procedure"
                    s.members[0].type.spec = runic.Builtin.RawPtr

                    s.members[1].name = "data"
                    s.members[1].type.spec = runic.Builtin.RawPtr

                    type.spec = s
                case "Logger":
                    s: runic.Struct = ---
                    s.members = make(
                        [dynamic]runic.Member,
                        len = 4,
                        cap = 4,
                        allocator = ctx.allocator,
                    )

                    s.members[0].name = "procedure"
                    s.members[0].type.spec = runic.Builtin.RawPtr

                    s.members[1].name = "data"
                    s.members[1].type.spec = runic.Builtin.RawPtr

                    s.members[2].name = "lowest_level"
                    switch plat.arch {
                    case .x86, .arm32:
                        s.members[2].type.spec = runic.Builtin.UInt32
                    case .x86_64, .arm64:
                        s.members[2].type.spec = runic.Builtin.UInt64
                    case .Any:
                        s.members[2].type.spec = runic.Builtin.Untyped
                    }

                    s.members[3].name = "options"
                    // NOTE: This is a bit_set of which the size depends on the number of enum entries
                    s.members[3].type.spec = runic.Builtin.UInt16

                    type.spec = s
                case "Random_Generator":
                    s: runic.Struct = ---
                    s.members = make(
                        [dynamic]runic.Member,
                        len = 2,
                        cap = 2,
                        allocator = ctx.allocator,
                    )

                    s.members[0].name = "procedure"
                    s.members[0].type.spec = runic.Builtin.RawPtr

                    s.members[1].name = "data"
                    s.members[1].type.spec = runic.Builtin.RawPtr

                    type.spec = s
                case "Context":
                    // NOTE: This structure probably changes sometimes (unstable)
                    s: runic.Struct = ---
                    s.members = make(
                        [dynamic]runic.Member,
                        len = 8,
                        cap = 8,
                        allocator = ctx.allocator,
                    )

                    s.members[0].name = "allocator"
                    s.members[0].type.spec = string("runtime_Allocator")

                    s.members[1].name = "temp_allocator"
                    s.members[1].type.spec = string("runtime_Allocator")

                    s.members[2].name = "assertion_failure_proc"
                    s.members[2].type.spec = runic.Builtin.RawPtr

                    s.members[3].name = "logger"
                    s.members[3].type.spec = string("runtime_Logger")

                    s.members[4].name = "random_generator"
                    s.members[4].type.spec = string("runtime_Random_Generator")

                    s.members[5].name = "user_ptr"
                    s.members[5].type.spec = runic.Builtin.RawPtr

                    s.members[6].name = "user_index"
                    switch plat.arch {
                    case .x86, .arm32:
                        s.members[6].type.spec = runic.Builtin.SInt32
                    case .x86_64, .arm64:
                        s.members[6].type.spec = runic.Builtin.SInt64
                    case .Any:
                        s.members[6].type.spec = runic.Builtin.Untyped
                    }

                    s.members[7].name = "_internal"
                    s.members[7].type.spec = runic.Builtin.RawPtr

                    type.spec = s

                    if !om.contains(ctx.types^, "runtime_Allocator") {
                        allocator_type := lookup_type_of_import(
                            plat,
                            pkg,
                            "Allocator",
                            ctx,
                        ) or_return
                        om.insert(ctx.types, "runtime_Allocator", allocator_type)
                    }
                    if !om.contains(ctx.types^, "runtime_Logger") {
                        logger_type := lookup_type_of_import(
                            plat,
                            pkg,
                            "Logger",
                            ctx,
                        ) or_return
                        om.insert(ctx.types, "runtime_Logger", logger_type)
                    }
                    if !om.contains(ctx.types^, "runtime_Random_Generator") {
                        random_generator_type := lookup_type_of_import(
                            plat,
                            pkg,
                            "Random_Generator",
                            ctx,
                        ) or_return
                        om.insert(
                            ctx.types,
                            "runtime_Random_Generator",
                            random_generator_type,
                        )
                    }
                case:
                    type.spec = runic.Builtin.Opaque
                }
                return
            case "intrinsics":
                type.spec = runic.Builtin.Opaque
                return
            }
        }

        errors.assert(
            ok,
            fmt.aprint(
                "package",
                pkg,
                "does not exist in",
                slice.map_keys(ctx.imports^, allocator = errors.error_allocator),
                allocator = errors.error_allocator,
            ),
        ) or_return


        p: odinp.Parser
        p.flags = {.Optional_Semicolons}

        reserved_packages := make([dynamic]string)

        context.user_ptr = &reserved_packages
        context.allocator = ctx.allocator
        p.err = proc(pos: odint.Pos, msg: string, args: ..any) {
            whole_msg := fmt.aprintf(
                msg,
                ..args,
                allocator = errors.error_allocator,
            )
            if strings.has_prefix(whole_msg, "use of reserved package name") {
                when ODIN_DEBUG {
                    reserved_packages := cast(^[dynamic]string)context.user_ptr
                    if !slice.contains(reserved_packages^[:], whole_msg) {
                        fmt.eprintln("debug:", whole_msg)
                        append(reserved_packages, whole_msg)
                    }
                }
                return
            }

            fmt.eprintln(error_tok(whole_msg, pos))
        }

        imp.pkg, ok = odinp.parse_package_from_path(imp.abs_path, &p)
        delete(reserved_packages)

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
        ctx,
    )

    return
}

lookup_type_in_package :: proc(
    plat: runic.Platform,
    type_name: string,
    pkg: ^odina.Package,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    prev_pkg := ctx.current_package
    ctx.current_package = pkg
    defer ctx.current_package = prev_pkg

    prev_imports := ctx.imports
    defer ctx.imports = prev_imports

    for file_name, file in pkg.files {
        local_imports := make(map[string]Import)
        defer delete(local_imports)

        ctx.imports = &local_imports

        for decl in file.decls {
            #partial switch stm in decl.derived_stmt {
            case ^odina.Import_Decl:
                name, impo := parse_import(file_name, stm, ctx.allocator) or_return
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
                            ctx,
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

bit_set_type_from_enum :: proc(
    enum_type: runic.Enum,
    allocator := context.allocator,
) -> (
    type: runic.Type,
) {
    entry_count := len(enum_type.entries)
    bit_set_size := entry_count / 8
    if entry_count % 8 != 0 {
        bit_set_size += 1
    }

    switch bit_set_size {
    case 1:
        type.spec = runic.Builtin.UInt8
    case 2:
        type.spec = runic.Builtin.UInt16
    case 3 ..= 4:
        type.spec = runic.Builtin.UInt32
    case 5 ..= 8:
        type.spec = runic.Builtin.UInt64
    case 9 ..= 16:
        type.spec = runic.Builtin.UInt128
    case:
        type.spec = runic.Builtin.UInt8
        type.array_info = make(
            [dynamic]runic.Array,
            len = 1,
            cap = 1,
            allocator = allocator,
        )
        type.array_info[0].size = u64(bit_set_size)
    }

    return
}
