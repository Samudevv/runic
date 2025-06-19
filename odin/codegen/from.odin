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
    pending_bit_sets := make(map[string]string)
    defer delete(pending_bit_sets)

    ttt_ctx := TypeToTypeContext {
        constants        = &rs.constants,
        symbols          = &rs.symbols,
        types            = &rs.types,
        anon_counter     = &anon_counter,
        ow               = overwrite,
        pending_bit_sets = &pending_bit_sets,
        allocator        = rs_arena_alloc,
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
                    parse_value_decl(plat, &ttt_ctx, stm) or_return
                case ^odina.Import_Decl:
                    parse_import_decl(&ttt_ctx, file_name, stm) or_return
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

parse_import_decl :: proc(
    ctx: ^TypeToTypeContext,
    file_name: string,
    stm: ^odina.Import_Decl,
) -> (
    err: errors.Error,
) {
    col_path, a_err := strings.split_n(
        strings.trim_suffix(strings.trim_prefix(stm.fullpath, `"`), `"`),
        ":",
        2,
        ctx.allocator,
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
        // TODO: dynamically load ODIN_ROOT
        path = filepath.join({ODIN_ROOT, collection, path}, ctx.allocator)
    case "":
        ok: bool = ---
        path, ok = runic.relative_to_file(file_name, path, ctx.allocator)
        errors.wrap(ok, "import relative") or_return
    case:
        err = error_tok("unknown collection", stm.relpath)
        return
    }

    name: string = ---
    if len(stm.name.text) != 0 {
        name = stm.name.text
    } else {
        name = filepath.base(path)
    }

    imp := Import {
        abs_path   = path,
        name       = filepath.base(path),
        collection = collection,
    }

    ctx.imports^[name] = imp
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
                return ident_to_type(plat, ctx, type_name)
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
                        om.insert(
                            ctx.types,
                            "runtime_Allocator",
                            allocator_type,
                        )
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
                slice.map_keys(
                    ctx.imports^,
                    allocator = errors.error_allocator,
                ),
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

    // TODO: Maybe hardcode some types of "core:c"

    type, err = lookup_type_in_package(plat, type_name, imp.pkg, ctx)

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
                parse_import_decl(ctx, file_name, stm) or_return
            case ^odina.Value_Decl:
                for name_expr, idx in stm.names {
                    if len(stm.values) <= idx {
                        continue
                    }

                    name := name_to_name(name_expr) or_return

                    if name == type_name {
                        value_expr := stm.values[idx]

                        return type_to_type(plat, ctx, name, value_expr)
                    }
                }
            }
        }
    }

    err = errors.message("type {} not found in {}", type_name, pkg.name)
    return
}

range_info_from_binary_expr :: proc(
    expr: ^odina.Binary_Expr,
) -> (
    count: int,
    left_text: string,
    right_text: string,
    full: bool,
    is_number: bool,
    err: errors.Error,
) {
    #partial switch expr.op.kind {
    case .Range_Half:
    case .Range_Full:
        full = true
    case:
        err = error_tok(
            fmt.aprintf(
                "invalid range operator {}",
                expr.op.kind,
                allocator = errors.error_allocator,
            ),
            expr.op.pos,
        )
        return
    }

    start, end: int

    #partial switch left in expr.left.derived_expr {
    case ^odina.Basic_Lit:
        #partial switch left.tok.kind {
        case .Integer:
            ok: bool = ---
            start, ok = strconv.parse_int(left.tok.text)
            if !ok {
                err = error_tok(
                    fmt.aprintf(
                        "invalid integer at left of range: \"{}\"",
                        left.tok.text,
                        allocator = errors.error_allocator,
                    ),
                    left.tok,
                )
                return
            }

            left_text = left.tok.text
            is_number = true
        case .Rune:
            left_text = strings.trim_suffix(
                strings.trim_prefix(left.tok.text, "'"),
                "'",
            )

            start_rune: rune = ---
            for r in left_text {
                start_rune = r
                break
            }

            start = int(start_rune)
            is_number = false
        case:
            err = error_tok(
                fmt.aprintf(
                    "invalid basic literal at left of range: {}",
                    left.tok.kind,
                    allocator = errors.error_allocator,
                ),
                left.tok.pos,
            )
            return
        }
    case ^odina.Ident:
        // TODO
        left_text = left.name
        is_number = false
        err = error_tok(
            "bit_sets with ranges that use constants are not supported",
            expr.left.pos,
        )
        return
    case ^odina.Selector_Expr:
        // TODO
        is_number = false
        err = error_tok(
            "bit_sets with ranges that use constants from other packages are not supported",
            expr.left.pos,
        )
        return
    case:
        err = error_tok(
            fmt.aprintf(
                "invalid left of range: {}",
                reflect.get_union_variant(expr.left.derived_expr).id,
                allocator = errors.error_allocator,
            ),
            expr.left.pos,
        )
    }

    #partial switch right in expr.right.derived_expr {
    case ^odina.Basic_Lit:
        #partial switch right.tok.kind {
        case .Integer:
            ok: bool = ---
            end, ok = strconv.parse_int(right.tok.text)
            if !ok {
                err = error_tok(
                    fmt.aprintf(
                        "invalid integer at right of range: \"{}\"",
                        right.tok.text,
                        allocator = errors.error_allocator,
                    ),
                    right.tok,
                )
                return
            }

            right_text = right.tok.text
            is_number = true
        case .Rune:
            right_text = strings.trim_suffix(
                strings.trim_prefix(right.tok.text, "'"),
                "'",
            )

            end_rune: rune = ---
            for r in right_text {
                end_rune = r
                break
            }

            end = int(end_rune)
            is_number = false
        case:
            err = error_tok(
                fmt.aprintf(
                    "invalid basic literal at right of range: {}",
                    right.tok.kind,
                    allocator = errors.error_allocator,
                ),
                right.tok.pos,
            )
            return
        }
    case ^odina.Ident:
        // TODO
        right_text = right.name
        is_number = false
        err = error_tok(
            "bit_sets with ranges that use constants are not supported",
            expr.right.pos,
        )
        return
    case ^odina.Selector_Expr:
        // TODO
        is_number = false
        err = error_tok(
            "bit_sets with ranges that use constants from other packages are not supported",
            expr.right.pos,
        )
        return
    case:
        err = error_tok(
            fmt.aprintf(
                "invalid right of range: {}",
                reflect.get_union_variant(expr.right.derived_expr).id,
                allocator = errors.error_allocator,
            ),
            expr.right.pos,
        )
    }

    if end < start {
        err = error_tok("end of range is less than start of range", expr.pos)
        return
    }

    count = end - start
    if full {
        count += 1
    }

    return
}

is_odin_builtin_type_identifier :: proc(ident: string) -> bool {
    switch ident {
    case "int",
         "uint",
         "i8",
         "i16",
         "i32",
         "i64",
         "i128",
         "byte",
         "u8",
         "u16",
         "u32",
         "u64",
         "u128",
         "uintptr",
         "f16",
         "f32",
         "f64",
         "rune",
         "rawptr",
         "bool",
         "b8",
         "b16",
         "b32",
         "b64",
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
         "any",
         "string":
        return true
    }

    return false
}

extract_attributes :: proc(
    stm: ^odina.Value_Decl,
) -> (
    link_name: Maybe(string),
    exported: bool,
    err: errors.Error,
) {
    for attr in stm.attributes {
        for elem_expr in attr.elems {
            #partial switch elem in elem_expr.derived_expr {
            case ^odina.Ident:
                switch elem.name {
                case "export":
                    exported = true
                }
            case ^odina.Field_Value:
                #partial switch field in elem.field.derived_expr {
                case ^odina.Ident:
                    switch field.name {
                    case "export":
                        #partial switch value in elem.value.derived_expr {
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
                        #partial switch value in elem.value.derived_expr {
                        case ^odina.Basic_Lit:
                            link_name = strings.trim_suffix(
                                strings.trim_prefix(value.tok.text, `"`),
                                `"`,
                            )
                        }
                    }
                }
            }
        }
    }

    return
}

parse_value_decl :: proc(
    plat: runic.Platform,
    ctx: ^TypeToTypeContext,
    stm: ^odina.Value_Decl,
) -> (
    err: errors.Error,
) {
    link_name, exported := extract_attributes(stm) or_return

    first_name: Maybe(string)
    if len(stm.names) != 0 {
        first_name = name_to_name(stm.names[0]) or_return
    }

    decl_type: Maybe(runic.Type)
    if stm.type != nil {
        type_err: errors.Error = ---
        decl_type, type_err = type_to_type(plat, ctx, first_name, stm.type)
        if type_err != nil {
            fmt.eprintln(type_err)
            return
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

                if om.contains(ctx.symbols^, name) {
                    fmt.eprintf("{} is defined as \"", name)
                    sym := om.get(ctx.symbols^, name)
                    switch v in sym.value {
                    case runic.Type:
                        runic.write_type(os.stream_from_handle(os.stderr), v)
                    case runic.Function:
                        runic.write_function(
                            os.stream_from_handle(os.stderr),
                            v,
                        )
                    }
                    fmt.eprintln("\" and \"")
                    runic.write_type(os.stream_from_handle(os.stderr), type)
                    fmt.eprintln('"')
                }

                om.insert(
                    ctx.symbols,
                    strings.clone(name, ctx.allocator),
                    runic.Symbol{value = type},
                )
            }
            continue
        }

        value_expr := stm.values[idx]

        #partial switch value in value_expr.derived_expr {
        case ^odina.Proc_Lit:
            if !exported do continue

            fn, fn_err := proc_to_function(plat, ctx, value.type, name)
            if fn_err != nil {
                fmt.eprintln(fn_err)
                continue
            }

            if link_name != nil {
                name = link_name.?
            }

            if om.contains(ctx.symbols^, name) {
                fmt.eprintf("{} is defined as \"", name)
                sym := om.get(ctx.symbols^, name)
                switch v in sym.value {
                case runic.Type:
                    runic.write_type(os.stream_from_handle(os.stderr), v)
                case runic.Function:
                    runic.write_function(os.stream_from_handle(os.stderr), v)
                }
                fmt.eprintln("\" and \"")
                runic.write_function(os.stream_from_handle(os.stderr), fn)
                fmt.eprintln('"')
            }

            om.insert(
                ctx.symbols,
                strings.clone(name, ctx.allocator),
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
                if ival, ok := strconv.parse_i64(value.tok.text); !ok {
                    fmt.eprintfln(
                        "Failed to parse constant value \"{}\" to integer",
                        value.tok.text,
                    )
                    continue
                } else {
                    const_val = ival
                }
            case .Float:
                if fval, ok := strconv.parse_f64(value.tok.text); !ok {
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
                    ctx.allocator,
                )
                const_spec = .String
            case:
                fmt.eprintfln(
                    "Constants with token kind {} are not supported",
                    value.tok.kind,
                )
                continue
            }

            if om.contains(ctx.constants^, name) {
                fmt.eprintfln(
                    "Constant {} is defined as \"{}\" and \"{}\"",
                    om.get(ctx.constants^, name),
                    const_val,
                )
            }

            om.insert(
                ctx.constants,
                strings.clone(name, ctx.allocator),
                runic.Constant{value = const_val, type = {spec = const_spec}},
            )
        case:
            type, type_err := type_to_type(plat, ctx, name, value_expr)
            if type_err != nil {
                fmt.eprintln(type_err)
                continue
            }

            if om.contains(ctx.symbols^, name) {
                fmt.eprintf("{} is defined as \"", name)
                sym := om.get(ctx.symbols^, name)
                switch v in sym.value {
                case runic.Type:
                    runic.write_type(os.stream_from_handle(os.stderr), v)
                case runic.Function:
                    runic.write_function(os.stream_from_handle(os.stderr), v)
                }
                fmt.eprintln("\" and \"")
                runic.write_type(os.stream_from_handle(os.stderr), type)
                fmt.eprintln('"')
            }

            #partial switch enum_type in type.spec {
            case runic.Enum:
                if bit_set_type_name, bit_set_ok :=
                       ctx.pending_bit_sets^[name]; bit_set_ok {
                    if !om.contains(ctx.types^, bit_set_type_name) {
                        bit_set_type := bit_set_type_from_enum(
                            enum_type,
                            ctx.allocator,
                        )
                        om.insert(ctx.types, bit_set_type_name, bit_set_type)
                    }

                    delete_key(ctx.pending_bit_sets, name)
                }
            }

            om.insert(ctx.types, strings.clone(name, ctx.allocator), type)
        }
    }

    return
}
