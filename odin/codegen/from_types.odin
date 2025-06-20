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
import "core:reflect"
import "core:strconv"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

@(private)
TypeToTypeContext :: struct {
    constants:           ^om.OrderedMap(string, runic.Constant),
    symbols:             ^om.OrderedMap(string, runic.Symbol),
    types:               ^om.OrderedMap(string, runic.Type),
    externs:             ^om.OrderedMap(string, runic.Extern),
    anon_counter:        ^int,
    imports:             ^map[string]Import,
    current_package:     Maybe(^odina.Package),
    current_import_path: Maybe(string),
    ow:                  runic.OverwriteSet,
    pending_bit_sets:    ^map[string]string,
    allocator:           runtime.Allocator,
}

type_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    t: ^odina.Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    #partial switch type_expr in t.derived_expr {
    case ^odina.Ident:
        return ident_to_type(plat, ctx, type_expr.name)
    case ^odina.Typeid_Type:
        return typeid_to_type(plat, ctx)
    case ^odina.Pointer_Type:
        return pointer_to_type(plat, ctx, name, type_expr.elem)
    case ^odina.Array_Type:
        return array_or_slice_to_type(
            plat,
            ctx,
            name,
            type_expr.elem,
            type_expr.len,
        )
    case ^odina.Multi_Pointer_Type:
        return pointer_to_type(plat, ctx, name, type_expr.elem)
    case ^odina.Dynamic_Array_Type:
        return dynamic_array_to_type(plat, ctx, name, type_expr.elem)
    case ^odina.Enum_Type:
        return enum_to_type(plat, type_expr, name, ctx)
    case ^odina.Struct_Type:
        return struct_or_raw_union_to_type(plat, ctx, name, type_expr)
    case ^odina.Union_Type:
        return union_to_type(plat, ctx, name, type_expr)
    case ^odina.Selector_Expr:
        return selector_to_type(plat, ctx, type_expr)
    case ^odina.Helper_Type:
        return type_to_type(plat, ctx, name, type_expr.type)
    case ^odina.Proc_Type:
        func := proc_to_function(plat, ctx, type_expr, name) or_return
        type.spec = runic.FunctionPointer(new_clone(func, ctx.allocator))
    case ^odina.Bit_Set_Type:
        return bit_set_to_type(plat, ctx, type_expr)
    case ^odina.Bit_Field_Type:
        return bit_field_to_type(plat, ctx, name, type_expr)
    case ^odina.Call_Expr:
        return maybe_to_type(plat, ctx, name, type_expr)
    case ^odina.Map_Type:
        return map_to_type(plat, ctx, name, type_expr)
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

string_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
) {
    if !om.contains(ctx.externs^, "string") {
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
        string_type.members[1].type.spec = runic.Builtin.SIntX

        om.insert(
            ctx.externs,
            "string",
            runic.Extern{type = {spec = string_type}, source = "base:builtin"},
        )
    }

    type.spec = runic.ExternType("string")
    return
}

any_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
) {
    if !om.contains(ctx.externs^, "any") {
        any_spec: runic.Struct

        any_spec.members = make(
            [dynamic]runic.Member,
            len = 2,
            cap = 2,
            allocator = ctx.allocator,
        )

        any_spec.members[0].name = "data"
        any_spec.members[0].type.spec = runic.Builtin.RawPtr

        any_spec.members[1].name = "id"
        any_spec.members[1].type.spec = runic.ExternType("typeid")

        typeid_to_type(plat, ctx)

        om.insert(
            ctx.externs,
            "any",
            runic.Extern{type = {spec = any_spec}, source = "base:builtin"},
        )
    }

    type.spec = runic.ExternType("any")
    return
}

typeid_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    specialization: ^odina.Expr = nil,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    if specialization != nil {
        err = error_tok(
            "specialization of typeid is not supported",
            specialization.pos,
        )
        return
    }

    if !om.contains(ctx.externs^, "typeid") {
        typeid_spec := runic.Builtin.SIntX

        om.insert(
            ctx.externs,
            "typeid",
            runic.Extern{type = {spec = typeid_spec}, source = "base:builtin"},
        )
    }

    type.spec = runic.ExternType("typeid")
    return
}

pointer_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    elem: ^odina.Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    type = type_to_type(plat, ctx, name, elem) or_return
    if len(type.array_info) != 0 {
        type.array_info[len(type.array_info) - 1].pointer_info.count += 1
    } else {
        type.pointer_info.count += 1
    }

    return
}

array_or_slice_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    elem, len: ^odina.Expr,
) -> (
    runic.Type,
    errors.Error,
) {
    if len != nil {
        return array_to_type(plat, ctx, name, elem, len)
    }
    return slice_to_type(plat, ctx, name, elem)
}

array_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    elem, length: ^odina.Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    type = type_to_type(plat, ctx, name, elem) or_return
    if len(type.array_info) == 0 {
        type.array_info = make([dynamic]runic.Array, ctx.allocator)
    }

    size: runic.ArraySize

    #partial switch l in length.derived_expr {
    case ^odina.Basic_Lit:
        #partial switch l.tok.kind {
        case .Integer:
            value, ok := strconv.parse_u64(l.tok.text)
            errors.wrap(ok) or_return
            size = value
        }
    }

    append(&type.array_info, runic.Array{size = size})

    return
}

slice_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    elem: ^odina.Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    // TODO: output the name in different casing (camelCase, PascalCase etc.)
    // TODO: add prefix/suffix to name maybe?

    slice_name_elements := make([dynamic]string, len = 0, cap = 3) // []^[5]int

    needs_anon := false
    slice_name_loop: for expr := elem; expr != nil; {
        #partial switch de in expr.derived_expr {
        case ^odina.Ident:
            append(&slice_name_elements, de.name)
        case ^odina.Selector_Expr:
            errors.assert(de.expr != nil) or_return

            append(&slice_name_elements, de.field.name)

            #partial switch e in de.expr.derived_expr {
            case ^odina.Ident:
                append(&slice_name_elements, e.name)
            case:
                err = error_tok("invalid selector", de.expr.pos)
                return
            }
        case ^odina.Typeid_Type:
            append(&slice_name_elements, "typeid")
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
        }

        break
    }

    slice_name_bd: strings.Builder
    strings.builder_init(&slice_name_bd, allocator = ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&slice_name_bd, ctx.current_package.?.name)
        strings.write_rune(&slice_name_bd, '_')
    }

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

    slice_type: runic.Struct = ---
    slice_type.members = make(
        [dynamic]runic.Member,
        len = 2,
        cap = 2,
        allocator = ctx.allocator,
    )

    slice_type.members[0].name = "data"
    slice_type.members[0].type = type_to_type(plat, ctx, name, elem) or_return
    if len(slice_type.members[0].type.array_info) != 0 {
        slice_type.members[0].type.array_info[len(slice_type.members[0].type.array_info) - 1].pointer_info.count +=
        1
    } else {
        slice_type.members[0].type.pointer_info.count += 1
    }

    slice_type.members[1].name = "length"
    slice_type.members[1].type.spec = runic.Builtin.SIntX

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            slice_name,
            runic.Extern {
                type = {spec = slice_type},
                source = ctx.current_import_path.?,
            },
        )
        type.spec = runic.ExternType(slice_name)
    } else {
        om.insert(ctx.types, slice_name, runic.Type{spec = slice_type})
        type.spec = slice_name
    }

    return
}

dynamic_array_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    elem: ^odina.Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    // TODO: find out what 'tag' does

    type = type_to_type(plat, ctx, name, elem) or_return

    dyn_name_elements := make([dynamic]string, len = 0, cap = 3) // [dynamic]^[5]int

    needs_anon := false
    dyn_name_loop: for expr := elem; expr != nil; {
        #partial switch de in expr.derived_expr {
        case ^odina.Ident:
            append(&dyn_name_elements, de.name)
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
        case ^odina.Selector_Expr:
            errors.assert(de.expr != nil) or_return

            append(&dyn_name_elements, de.field.name)

            #partial switch e in de.expr.derived_expr {
            case ^odina.Ident:
                append(&dyn_name_elements, e.name)
            case:
                err = error_tok("invalid selector", de.expr.pos)
                return
            }
        case ^odina.Typeid_Type:
            append(&dyn_name_elements, "typeid")
        case:
            append(&dyn_name_elements, "unknown")
            needs_anon = true
        }

        break
    }

    dyn_name_bd: strings.Builder
    strings.builder_init(&dyn_name_bd, allocator = ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&dyn_name_bd, ctx.current_package.?.name)
        strings.write_rune(&dyn_name_bd, '_')
    }

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
    dynamic_array_type.members[1].type.spec = runic.Builtin.SIntX

    dynamic_array_type.members[2].name = "capacity"
    dynamic_array_type.members[2].type.spec = runic.Builtin.SIntX

    dynamic_array_type.members[3].name = "allocator"
    dynamic_array_type.members[3].type.spec = runic.ExternType(
        "runtime_Allocator",
    )

    maybe_add_runtime_extern(plat, ctx, "Allocator") or_return

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            dynamic_array_name,
            runic.Extern {
                type = {spec = dynamic_array_type},
                source = ctx.current_import_path.?,
            },
        )
        type = runic.Type {
            spec = dynamic_array_name,
        }
    } else {
        om.insert(
            ctx.types,
            dynamic_array_name,
            runic.Type{spec = dynamic_array_type},
        )
        type = runic.Type {
            spec = dynamic_array_name,
        }
    }

    return
}

struct_or_raw_union_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    s: ^odina.Struct_Type,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    if s.is_raw_union {
        return raw_union_to_type(plat, s, ctx)
    }
    return struct_to_type(plat, s, ctx)
}

union_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    u: ^odina.Union_Type,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    if u.poly_params != nil do return type, error_tok("unions with poly_params are not supported", u.poly_params.pos)
    if u.align != nil do return type, error_tok("unions with alignment are not supported", u.align.pos)

    if len(u.variants) == 0 {
        type.spec = runic.Builtin.Opaque
        return
    }

    tag_type: runic.TypeSpecifier = ---
    switch len(u.variants) {
    case 1 ..= int(max(u8)):
        tag_type = runic.Builtin.UInt8
    case int(max(u8)) + 1 ..= int(max(u16)):
        tag_type = runic.Builtin.UInt16
    case:
        err = error_tok(
            fmt.aprintf(
                "unions with more than {} variants are not supported. len(variants)={}",
                max(u16),
                len(u.variants),
            ),
            u.pos,
        )
        return
    }

    values_union: runic.Union
    values_union.members = make(
        [dynamic]runic.Member,
        len = 0,
        cap = len(u.variants),
        allocator = ctx.allocator,
    )

    for var, idx in u.variants {
        var_name := fmt.aprintf("v{}", idx, allocator = ctx.allocator)
        var_type := type_to_type(plat, ctx, var_name, var) or_return

        append(
            &values_union.members,
            runic.Member{name = var_name, type = var_type},
        )
    }

    values_union_type_name: strings.Builder
    strings.builder_init(&values_union_type_name, ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(
            &values_union_type_name,
            ctx.current_package.?.name,
        )
        strings.write_rune(&values_union_type_name, '_')
    }

    if type_name, type_name_ok := name.?; type_name_ok {
        strings.write_string(&values_union_type_name, type_name)
        strings.write_string(&values_union_type_name, "_values")
    } else {
        strings.write_string(&values_union_type_name, "anon_values_union_")
        strings.write_int(&values_union_type_name, ctx.anon_counter^)
        ctx.anon_counter^ += 1
    }

    union_type: runic.Struct
    union_type.members = make(
        [dynamic]runic.Member,
        len = 2,
        cap = 2,
        allocator = ctx.allocator,
    )

    union_type.members[0].name = "tag"
    union_type.members[0].type.spec = tag_type
    union_type.members[1].name = "values"

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            strings.to_string(values_union_type_name),
            runic.Extern {
                type = {spec = values_union},
                source = ctx.current_import_path.?,
            },
        )

        union_type.members[1].type.spec = runic.ExternType(
            strings.to_string(values_union_type_name),
        )
    } else {
        om.insert(
            ctx.types,
            strings.to_string(values_union_type_name),
            runic.Type{spec = values_union},
        )

        union_type.members[1].type.spec = strings.to_string(
            values_union_type_name,
        )
    }

    type.spec = union_type
    return
}

selector_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    sel: ^odina.Selector_Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    errors.assert(sel.op.kind == .Period) or_return

    pkg, ok := sel.expr.derived_expr.(^odina.Ident)
    if !ok {
        err = errors.message(
            "{}",
            reflect.get_union_variant(sel.expr.derived_expr).id,
        )
        return
    }

    type_name := sel.field.name

    type = lookup_type_of_import(plat, pkg.name, type_name, ctx) or_return

    imp, imp_ok := ctx.imports^[pkg.name]
    errors.assert(imp_ok, "import was expected to exist") or_return

    if imp.name != "builtin" {
        type_name = fmt.aprintf(
            "{}_{}",
            imp.name,
            type_name,
            allocator = ctx.allocator,
        )

        om.insert(
            ctx.externs,
            type_name,
            runic.Extern{type = type, source = imp.imp_path},
        )
        type = runic.Type {
            spec = runic.ExternType(type_name),
        }
    }

    return
}

bit_set_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    bs: ^odina.Bit_Set_Type,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    bit_set_type: Maybe(runic.Type)

    underlying: runic.TypeSpecifier
    underlying_name: string

    if bs.underlying != nil {
        #partial switch d in bs.underlying.derived_expr {
        case ^odina.Ident:
            underlying_name = d.name

            if ctx.current_package != nil &&
               !is_odin_builtin_type_identifier(underlying_name) {
                pkg_type := lookup_type_in_package(
                    plat,
                    underlying_name,
                    ctx.current_import_path.?,
                    ctx.current_package.?,
                    ctx,
                ) or_return

                pkg_type_name := strings.concatenate(
                    {ctx.current_package.?.name, "_", underlying_name},
                    ctx.allocator,
                )

                om.insert(
                    ctx.externs,
                    pkg_type_name,
                    runic.Extern {
                        type = pkg_type,
                        source = ctx.current_import_path.?,
                    },
                )

                underlying = runic.ExternType(pkg_type_name)
            } else {
                under_type := ident_to_type(plat, ctx, d.name) or_return
                underlying = under_type.spec
            }

            bit_set_type = runic.Type {
                spec = underlying,
            }
        case ^odina.Selector_Expr:
            errors.assert(d.expr != nil) or_return

            underlying_name = d.field.name

            pkg_name: string = ---

            #partial switch pkg in d.expr.derived_expr {
            case ^odina.Ident:
                pkg_name = pkg.name
            case:
                err = error_tok("invalid Selector_Expr", d.expr.pos)
                return
            }

            pkg_type := lookup_type_of_import(
                plat,
                pkg_name,
                underlying_name,
                ctx,
            ) or_return

            imp, imp_ok := ctx.imports^[pkg_name]
            errors.assert(imp_ok) or_return

            underlying_name = strings.concatenate(
                {imp.name, "_", underlying_name},
                ctx.allocator,
            )
            underlying = runic.ExternType(underlying_name)

            om.insert(
                ctx.externs,
                underlying_name,
                runic.Extern{type = pkg_type, source = imp.imp_path},
            )

            bit_set_type = runic.Type {
                spec = underlying,
            }
        case:
            err = error_tok(
                "underlying type of bit_set must be Ident or Selector_Expr",
                bs.pos,
            )
            return
        }
    }

    elem_name: string

    #partial switch e in bs.elem.derived_expr {
    case ^odina.Ident:
        elem_name = e.name

        if underlying == nil {
            if ctx.current_package != nil {
                elem_type := lookup_type_in_package(
                    plat,
                    elem_name,
                    ctx.current_import_path.?,
                    ctx.current_package.?,
                    ctx,
                ) or_return

                if enum_type, enum_ok := elem_type.spec.(runic.Enum); enum_ok {
                    enum_type_name := strings.concatenate(
                        {ctx.current_package.?.name, "_", elem_name},
                        ctx.allocator,
                    )

                    om.insert(
                        ctx.externs,
                        enum_type_name,
                        runic.Extern {
                            type = elem_type,
                            source = ctx.current_import_path.?,
                        },
                    )

                    bit_set_type = bit_set_type_from_enum(
                        enum_type,
                        ctx.allocator,
                    )
                } else {
                    err = error_tok("bit_set does not refer to an enum", e.pos)
                    return
                }
            } else {
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
                            bs.pos,
                        )
                        return
                    }
                }
            }
        }
    case ^odina.Binary_Expr:
        range_count, range_left, range_right, range_full, range_is_number :=
            range_info_from_binary_expr(e) or_return

        if range_is_number {
            elem_name = fmt.aprintf(
                "range_{}_{}_{}",
                range_left,
                "upto" if range_full else "to",
                range_right,
                allocator = ctx.allocator,
            )
        } else {
            // NOTE: In this case 'a'..='z' and 'A'..='Z' would be the same bit_set
            elem_name = fmt.aprintf(
                "range_{}",
                range_count,
                allocator = ctx.allocator,
            )
        }

        if underlying == nil {
            bit_set_type = bit_set_type_from_count(range_count, ctx.allocator)
        }
    case ^odina.Enum_Type:
        elem_name = fmt.aprintf(
            "anon_bit_set_enum_{}",
            ctx.anon_counter^,
            allocator = ctx.allocator,
        )
        ctx.anon_counter^ += 1

        anon_enum := enum_to_type(plat, e, elem_name, ctx) or_return

        if ctx.current_package != nil {
            om.insert(
                ctx.externs,
                elem_name,
                runic.Extern {
                    type = anon_enum,
                    source = ctx.current_import_path.?,
                },
            )
        } else {
            om.insert(ctx.types, elem_name, anon_enum)
        }

        if underlying == nil {
            bit_set_type = bit_set_type_from_enum(
                anon_enum.spec.(runic.Enum),
                ctx.allocator,
            )
        }
    case ^odina.Selector_Expr:
        errors.assert(e.op.kind == .Period) or_return

        pkg, pkg_ok := e.expr.derived_expr.(^odina.Ident)
        errors.assert(pkg_ok) or_return

        elem_name = e.field.name

        pkg_type := lookup_type_of_import(
            plat,
            pkg.name,
            elem_name,
            ctx,
        ) or_return

        enum_type, enum_ok := pkg_type.spec.(runic.Enum)
        errors.assert(
            enum_ok,
            "bit_set elem type needs to be an enum",
        ) or_return

        imp, imp_ok := ctx.imports^[pkg.name]
        errors.assert(imp_ok) or_return

        elem_name = fmt.aprintf(
            "{}_{}",
            imp.name,
            elem_name,
            allocator = ctx.allocator,
        )

        om.insert(
            ctx.externs,
            elem_name,
            runic.Extern{type = pkg_type, source = imp.imp_path},
        )

        if underlying == nil {
            bit_set_type = bit_set_type_from_enum(enum_type, ctx.allocator)
        }
    case:
        err = error_tok(
            fmt.aprintf(
                "invalid bit_set elem={}",
                reflect.get_union_variant(bs.elem.derived_expr).id,
                allocator = errors.error_allocator,
            ),
            bs.pos,
        )
        return
    }

    bit_set_type_name: strings.Builder
    strings.builder_init(&bit_set_type_name, allocator = ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&bit_set_type_name, ctx.current_package.?.name)
        strings.write_rune(&bit_set_type_name, '_')
    }

    strings.write_string(&bit_set_type_name, "bit_set_")
    strings.write_string(&bit_set_type_name, elem_name)
    if underlying != nil {
        strings.write_rune(&bit_set_type_name, '_')
        strings.write_string(&bit_set_type_name, underlying_name)
    }

    if bit_set_type != nil {
        if ctx.current_package != nil {
            om.insert(
                ctx.externs,
                strings.to_string(bit_set_type_name),
                runic.Extern {
                    type = bit_set_type.?,
                    source = ctx.current_import_path.?,
                },
            )

            type.spec = runic.ExternType(strings.to_string(bit_set_type_name))
        } else {
            om.insert(
                ctx.types,
                strings.to_string(bit_set_type_name),
                bit_set_type.?,
            )

            type.spec = strings.to_string(bit_set_type_name)
        }
    } else {
        ctx.pending_bit_sets^[elem_name] = strings.to_string(bit_set_type_name)

        type.spec = strings.to_string(bit_set_type_name)
    }

    return
}

bit_field_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    bf: ^odina.Bit_Field_Type,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    back_type := type_to_type(plat, ctx, name, bf.backing_type) or_return

    bit_field_type_name: strings.Builder
    strings.builder_init(&bit_field_type_name, ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&bit_field_type_name, ctx.current_package.?.name)
        strings.write_rune(&bit_field_type_name, '_')
    }

    strings.write_string(&bit_field_type_name, "bit_field_")

    #partial switch e in bf.backing_type.derived_expr {
    case ^odina.Ident:
        strings.write_string(&bit_field_type_name, e.name)
    case ^odina.Selector_Expr:
        errors.assert(e.op.kind == .Period) or_return

        pkg, pkg_ok := e.expr.derived_expr.(^odina.Ident)
        errors.assert(pkg_ok) or_return

        type_name := e.field.name

        imp, imp_ok := ctx.imports^[pkg.name]
        errors.assert(imp_ok) or_return

        strings.write_string(&bit_field_type_name, imp.name)
        strings.write_rune(&bit_field_type_name, '_')
        strings.write_string(&bit_field_type_name, type_name)
    case ^odina.Array_Type:
        #partial switch elem in e.elem.derived_expr {
        case ^odina.Ident:
            strings.write_string(&bit_field_type_name, elem.name)
            strings.write_rune(&bit_field_type_name, '_')
        case ^odina.Selector_Expr:
            errors.assert(elem.op.kind == .Period) or_return

            pkg, pkg_ok := elem.expr.derived_expr.(^odina.Ident)
            errors.assert(pkg_ok) or_return

            type_name := elem.field.name

            imp, imp_ok := ctx.imports^[pkg.name]
            errors.assert(imp_ok) or_return

            strings.write_string(&bit_field_type_name, imp.name)
            strings.write_rune(&bit_field_type_name, '_')
            strings.write_string(&bit_field_type_name, type_name)
            strings.write_rune(&bit_field_type_name, '_')
        case:
            err = error_tok("invalid bit_field backing type", e.elem.pos)
            return
        }

        errors.assert(e.len != nil) or_return

        #partial switch length in e.len.derived_expr {
        case ^odina.Basic_Lit:
            #partial switch length.tok.kind {
            case .Integer:
                strings.write_string(&bit_field_type_name, "array_")
                strings.write_string(&bit_field_type_name, length.tok.text)
            case:
                err = error_tok(
                    "invalid array length of backing type of bit_field",
                    length.tok,
                )
            }
        case:
            err = error_tok(
                "invalid array length of backing type of bit_field",
                e.len.pos,
            )
            return
        }
    }

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            strings.to_string(bit_field_type_name),
            runic.Extern{type = back_type, source = ctx.current_import_path.?},
        )
        type.spec = runic.ExternType(strings.to_string(bit_field_type_name))
    } else {
        om.insert(ctx.types, strings.to_string(bit_field_type_name), back_type)
        type.spec = strings.to_string(bit_field_type_name)
    }

    return
}

maybe_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    ce: ^odina.Call_Expr,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    #partial switch e in ce.expr.derived_expr {
    case ^odina.Ident:
        if e.name != "Maybe" {
            err = error_tok(
                "\"Maybe\" expected, but got Call_Expr",
                ce.expr.pos,
            )
            return
        }
    case:
        err = error_tok("invalid call expr", ce.expr.pos)
        return
    }

    errors.assert(
        len(ce.args) == 1,
        "invalid number of arguments of Maybe expression",
    ) or_return

    underlying := type_to_type(plat, ctx, name, ce.args[0]) or_return

    underlying_anon_name, underlying_anon_type, underlying_is_anon :=
        runic.create_anon_type(
            underlying.spec,
            ctx.anon_counter,
            ctx.allocator,
        )

    if underlying_is_anon {
        om.insert(ctx.types, underlying_anon_name, underlying_anon_type)
        underlying.spec = underlying_anon_name
    }

    maybe_type: runic.Struct
    maybe_type.members = make(
        [dynamic]runic.Member,
        len = 2,
        cap = 2,
        allocator = ctx.allocator,
    )

    maybe_type.members[0].name = "ok"
    maybe_type.members[0].type = runic.Type {
        spec = runic.Builtin.Bool8,
    }

    maybe_type.members[1].name = "value"
    maybe_type.members[1].type = underlying

    maybe_type_name: strings.Builder
    strings.builder_init(&maybe_type_name, ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&maybe_type_name, ctx.current_package.?.name)
        strings.write_rune(&maybe_type_name, '_')
    }

    strings.write_string(&maybe_type_name, "maybe_")

    needs_anon: bool

    #partial switch spec in underlying.spec {
    case string:
        strings.write_string(&maybe_type_name, spec)
    case runic.ExternType:
        strings.write_string(&maybe_type_name, string(spec))
    case runic.Unknown:
        strings.write_string(&maybe_type_name, string(spec))
    case runic.Builtin:
        #partial switch e in ce.args[0].derived_expr {
        case ^odina.Ident:
            strings.write_string(&maybe_type_name, e.name)
        case:
            strings.write_string(&maybe_type_name, "unknown")
            needs_anon = true
        }
    case runic.Struct:
        err = errors.unknown()
        return
    case runic.Enum:
        err = errors.unknown()
        return
    case runic.Union:
        err = errors.unknown()
        return
    case runic.FunctionPointer:
        err = errors.unknown()
        return
    }

    if needs_anon {
        strings.write_rune(&maybe_type_name, '_')
        strings.write_int(&maybe_type_name, ctx.anon_counter^)
        ctx.anon_counter^ += 1
    }

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            strings.to_string(maybe_type_name),
            runic.Extern {
                type = {spec = maybe_type},
                source = ctx.current_import_path.?,
            },
        )
        type.spec = runic.ExternType(strings.to_string(maybe_type_name))
    } else {
        om.insert(
            ctx.types,
            strings.to_string(maybe_type_name),
            runic.Type{spec = maybe_type},
        )
        type.spec = strings.to_string(maybe_type_name)
    }

    return
}

map_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    name: Maybe(string),
    mt: ^odina.Map_Type,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    key_type := type_to_type(plat, ctx, name, mt.key) or_return
    value_type := type_to_type(plat, ctx, name, mt.value) or_return

    key_anon_name, key_anon_type, key_is_anon := runic.create_anon_type(
        key_type.spec,
        ctx.anon_counter,
        ctx.allocator,
    )
    value_anon_name, value_anon_type, value_is_anon := runic.create_anon_type(
        value_type.spec,
        ctx.anon_counter,
        ctx.allocator,
    )

    if key_is_anon {
        key_type.spec = key_anon_name
        om.insert(ctx.types, key_anon_name, key_anon_type)
    }

    if value_is_anon {
        value_type.spec = value_anon_name
        om.insert(ctx.types, value_anon_name, value_anon_type)
    }

    map_type_name: strings.Builder
    strings.builder_init(&map_type_name, ctx.allocator)

    if ctx.current_package != nil {
        strings.write_string(&map_type_name, ctx.current_package.?.name)
        strings.write_rune(&map_type_name, '_')
    }

    strings.write_string(&map_type_name, "map_")

    switch spec in key_type.spec {
    case string:
        strings.write_string(&map_type_name, spec)
    case runic.Unknown:
        strings.write_string(&map_type_name, string(spec))
    case runic.ExternType:
        strings.write_string(&map_type_name, string(spec))
    case runic.Builtin:
        #partial switch de in mt.key.derived_expr {
        case ^odina.Ident:
            strings.write_string(&map_type_name, de.name)
        case ^odina.Typeid_Type:
            strings.write_string(&map_type_name, "typeid")
        case:
            err = error_tok("invalid key type", mt.key.pos)
            return
        }
    case runic.Struct:
        err = errors.unknown()
        return
    case runic.Enum:
        err = errors.unknown()
        return
    case runic.Union:
        err = errors.unknown()
        return
    case runic.FunctionPointer:
        err = errors.unknown()
        return
    }

    strings.write_rune(&map_type_name, '_')

    switch spec in value_type.spec {
    case string:
        strings.write_string(&map_type_name, spec)
    case runic.Unknown:
        strings.write_string(&map_type_name, string(spec))
    case runic.ExternType:
        strings.write_string(&map_type_name, string(spec))
    case runic.Builtin:
        #partial switch de in mt.value.derived_expr {
        case ^odina.Ident:
            strings.write_string(&map_type_name, de.name)
        case ^odina.Typeid_Type:
            strings.write_string(&map_type_name, "typeid")
        case:
            err = error_tok("invalid value type", mt.value.pos)
            return
        }
    case runic.Struct:
        err = errors.unknown()
        return
    case runic.Enum:
        err = errors.unknown()
        return
    case runic.Union:
        err = errors.unknown()
        return
    case runic.FunctionPointer:
        err = errors.unknown()
        return
    }

    map_type: runic.Struct
    map_type.members = make(
        [dynamic]runic.Member,
        len = 3,
        cap = 3,
        allocator = ctx.allocator,
    )

    map_type.members[0].name = "data"
    switch plat.arch {
    case .x86_64, .arm64:
        map_type.members[0].type = runic.Type {
            spec = runic.Builtin.UInt64,
        }
    case .x86, .arm32:
        map_type.members[0].type = runic.Type {
            spec = runic.Builtin.UInt32,
        }
    case .Any:
        map_type.members[0].type = runic.Type {
            spec = runic.Builtin.Untyped,
        }
    }

    map_type.members[1].name = "length"
    switch plat.arch {
    case .x86_64, .arm64:
        map_type.members[1].type = runic.Type {
            spec = runic.Builtin.UInt64,
        }
    case .x86, .arm32:
        map_type.members[1].type = runic.Type {
            spec = runic.Builtin.UInt32,
        }
    case .Any:
        map_type.members[1].type = runic.Type {
            spec = runic.Builtin.Untyped,
        }
    }

    map_type.members[2].name = "allocator"
    map_type.members[2].type = runic.Type {
        spec = runic.ExternType("runtime_Allocator"),
    }

    maybe_add_runtime_extern(plat, ctx, "Allocator") or_return

    if ctx.current_package != nil {
        om.insert(
            ctx.externs,
            strings.to_string(map_type_name),
            runic.Extern {
                type = {spec = map_type},
                source = ctx.current_import_path.?,
            },
        )
        type.spec = runic.ExternType(strings.to_string(map_type_name))
    } else {
        om.insert(
            ctx.types,
            strings.to_string(map_type_name),
            runic.Type{spec = map_type},
        )
        type.spec = strings.to_string(map_type_name)
    }

    return
}

ident_to_type :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    ident: string,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    switch ident {
    case "int":
        type.spec = runic.Builtin.SIntX
    case "uint":
        type.spec = runic.Builtin.UIntX
    case "i8":
        type.spec = runic.Builtin.SInt8
    case "i16":
        type.spec = runic.Builtin.SInt16
    case "i32":
        type.spec = runic.Builtin.SInt32
    case "i64":
        type.spec = runic.Builtin.SInt64
    case "i128":
        type.spec = runic.Builtin.SInt128
    case "byte":
        type.spec = runic.Builtin.UInt8
    case "u8":
        type.spec = runic.Builtin.UInt8
    case "u16":
        type.spec = runic.Builtin.UInt16
    case "u32":
        type.spec = runic.Builtin.UInt32
    case "u64":
        type.spec = runic.Builtin.UInt64
    case "u128":
        type.spec = runic.Builtin.UInt128
    case "uintptr":
        type.spec = runic.Builtin.UInt64
    case "f16":
        err = errors.message("f16 is not supported")
    case "f32":
        type.spec = runic.Builtin.Float32
    case "f64":
        type.spec = runic.Builtin.Float64
    case "f128":
        type.spec = runic.Builtin.Float128
    case "rune":
        type.spec = runic.Builtin.SInt32
    case "cstring":
        type.spec = runic.Builtin.String
    case "rawptr":
        type.spec = runic.Builtin.RawPtr
    case "bool":
        type.spec = runic.Builtin.Bool8
    case "b8":
        type.spec = runic.Builtin.Bool8
    case "b16":
        type.spec = runic.Builtin.Bool16
    case "b32":
        type.spec = runic.Builtin.Bool32
    case "b64":
        type.spec = runic.Builtin.Bool64
    case "string":
        type = string_to_type(plat, ctx)
    case "any":
        type = any_to_type(plat, ctx)
    case "i16le",
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
         "quaternion256":
        err = errors.message("{} is not supported", ident)
    case "typeid":
        err = errors.message(
            "{} should not be used with this procedure",
            ident,
        )
    case:
        if ctx.current_package != nil {
            prefix_type_name := fmt.aprintf(
                "{}_{}",
                ctx.current_package.?.name,
                ident,
                allocator = ctx.allocator,
            )

            if !om.contains(ctx.externs^, prefix_type_name) {
                om.insert(
                    ctx.externs,
                    prefix_type_name,
                    runic.Extern {
                        type = {spec = runic.Unknown(prefix_type_name)},
                        source = ctx.current_import_path.?,
                    },
                )
                type = lookup_type_in_package(
                    plat,
                    ident,
                    ctx.current_import_path.?,
                    ctx.current_package.?,
                    ctx,
                ) or_return
                om.insert(
                    ctx.externs,
                    prefix_type_name,
                    runic.Extern {
                        type = type,
                        source = ctx.current_import_path.?,
                    },
                )
            }

            type.spec = runic.ExternType(prefix_type_name)
        } else {
            type.spec = strings.clone(ident, ctx.allocator)
        }
    }

    return
}

proc_to_function :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    p: ^odina.Proc_Type,
    name: Maybe(string),
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

        type := type_to_type(plat, ctx, first_name, param_field.type) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            ctx.anon_counter,
            ctx.allocator,
        ); is_anon {
            if ctx.current_package != nil {
                anon_name = strings.concatenate(
                    {ctx.current_package.?.name, "_", anon_name},
                    ctx.allocator,
                )
                om.insert(
                    ctx.externs,
                    anon_name,
                    runic.Extern {
                        type = anon_type,
                        source = ctx.current_import_path.?,
                    },
                )
                type.spec = runic.ExternType(anon_name)
            } else {
                om.insert(ctx.types, anon_name, anon_type)
                type.spec = anon_name
            }
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
            ctx,
            first_name,
            result_field.type,
        ) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            type.spec,
            ctx.anon_counter,
            ctx.allocator,
        ); is_anon {
            if ctx.current_package != nil {
                anon_name = strings.concatenate(
                    {ctx.current_package.?.name, "_", anon_name},
                    ctx.allocator,
                )

                om.insert(
                    ctx.externs,
                    anon_name,
                    runic.Extern {
                        type = anon_type,
                        source = ctx.current_import_path.?,
                    },
                )

                type.spec = runic.ExternType(anon_name)
            } else {
                om.insert(ctx.types, anon_name, anon_type)
                type.spec = anon_name
            }
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
        if ctx.current_package != nil {
            result_type_name := fmt.aprintf(
                "{}_{}_result",
                ctx.current_package.?.name,
                name.? if name != nil else "proc",
                allocator = ctx.allocator,
            )
            fn.return_type.spec = runic.ExternType(result_type_name)
            om.insert(
                ctx.externs,
                result_type_name,
                runic.Extern {
                    type = {spec = result_struct},
                    source = ctx.current_import_path.?,
                },
            )
        } else {
            result_type_name := fmt.aprintf(
                "{}_result",
                name.? if name != nil else "proc",
                allocator = ctx.allocator,
            )
            fn.return_type.spec = result_type_name
            om.insert(
                ctx.types,
                result_type_name,
                runic.Type{spec = result_struct},
            )
        }
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

raw_union_to_type :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    s := struct_to_type(plat, st, ctx) or_return
    type.spec = runic.Union {
        members = s.spec.(runic.Struct).members,
    }
    return
}

struct_to_type :: proc(
    plat: runic.Platform,
    st: ^odina.Struct_Type,
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    if st.poly_params != nil do return type, error_tok("poly_params is not supported", st.pos)
    if st.align != nil do return type, error_tok("struct alignment is not supported", st.align.pos)
    if st.is_packed do return type, error_tok("packed structs are not supported", st.pos)

    s: runic.Struct

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

        field_type := type_to_type(plat, ctx, first_name, field.type) or_return

        if anon_name, anon_type, is_anon := runic.create_anon_type(
            field_type.spec,
            ctx.anon_counter,
            ctx.allocator,
        ); is_anon {
            if ctx.current_package != nil {
                anon_name = strings.concatenate(
                    {ctx.current_package.?.name, "_", anon_name},
                    ctx.allocator,
                )
                om.insert(
                    ctx.externs,
                    anon_name,
                    runic.Extern {
                        type = anon_type,
                        source = ctx.current_import_path.?,
                    },
                )
                field_type.spec = runic.ExternType(anon_name)
            } else {
                om.insert(ctx.types, anon_name, anon_type)
                field_type.spec = anon_name
            }
        }

        for name_expr in field.names {
            name := name_to_name(name_expr) or_return

            append(
                &s.members,
                runic.Member {
                    name = strings.clone(name, ctx.allocator),
                    type = field_type,
                },
            )
        }
    }

    type.spec = s

    return
}

enum_to_type :: proc(
    plat: runic.Platform,
    et: ^odina.Enum_Type,
    name: Maybe(string),
    ctx: ^TypeToTypeContext,
) -> (
    type: runic.Type,
    err: errors.Error,
) {
    e: runic.Enum

    if et.base_type == nil {
        e.type = .SIntX
    } else {
        underlying := type_to_type(plat, ctx, name, et.base_type) or_return

        ok: bool = ---
        e.type, ok = underlying.spec.(runic.Builtin)
        errors.wrap(ok) or_return
    }

    e.entries = make(
        [dynamic]runic.EnumEntry,
        len = 0,
        cap = len(et.fields),
        allocator = ctx.allocator,
    )

    counter: i64
    for field in et.fields {
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
            field_name: string = ---
            if name_ident, ok := f.field.derived_expr.(^odina.Ident); !ok {
                err = error_tok(
                    "enum entry needs to be an identifier",
                    f.field.pos,
                )
                return
            } else {
                field_name = strings.clone(name_ident.name, ctx.allocator)
            }

            value_any := evaluate_expr(plat, ctx, f.value) or_return
            value, value_ok := value_any.(i64)
            errors.wrap(value_ok, "enum field value is not integer") or_return

            counter = value

            append(
                &e.entries,
                runic.EnumEntry{name = field_name, value = value},
            )
        case:
            err = error_tok("invalid enum entry", field.pos)
            return
        }

        counter += 1
    }

    type.spec = e

    return
}

bit_set_type_from_count :: proc(
    count: int,
    allocator := context.allocator,
) -> (
    type: runic.Type,
) {
    bit_set_size := count / 8
    if count % 8 != 0 {
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

bit_set_type_from_enum :: proc(
    enum_type: runic.Enum,
    allocator := context.allocator,
) -> runic.Type {
    entry_count := len(enum_type.entries)
    return bit_set_type_from_count(entry_count)
}
