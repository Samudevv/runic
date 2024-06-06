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

package parser

import "base:runtime"
import ctz "core:c/frontend/tokenizer"
import "core:fmt"
import "core:strings"
import "root:errors"
import om "root:ordered_map"

MacroFuncCall :: struct {
    macro_func: MacroFunc,
    args:       [dynamic]string,
}

post_process :: proc(ps: ^Parser) {
    using ps

    context.allocator = runtime.arena_allocator(&arena)

    for entry in macros.data {
        m := entry.value
        if mv, ok := m.(MacroVar); ok && mv.value != nil {
            eval, eval_err := evaluate_macro_var(
                mv.value.?,
                macros,
                includes[:],
            )

            if eval_err != nil {
                when ODIN_DEBUG {
                    fmt.eprintfln(
                        "POST PROCESS :: macro eval err {}=\"{}\" {}",
                        mv.name,
                        mv.value.?,
                        eval_err,
                    )
                }

                continue
            }

            delete(mv.value.?)
            mv.value = eval
            om.insert(&macros, mv.name, mv)
        }
    }

    return
}

evaluate_macro_var :: proc(
    macro_value: string,
    macros: om.OrderedMap(string, Macro),
    includes: []IncludedHeader,
    allocator := context.allocator,
) -> (
    value_str: string,
    err: errors.Error,
) {

    macro_arena: runtime.Arena
    defer runtime.arena_destroy(&macro_arena)
    arena_alloc := runtime.arena_allocator(&macro_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = arena_alloc

        tz: ctz.Tokenizer
        file := ctz.add_new_file(&tz, "macro", transmute([]u8)macro_value, 1)
        token = ctz.tokenize(&tz, file)
    }

    errors.assert(token != nil) or_return

    nv: strings.Builder
    strings.builder_init(&nv, allocator)

    last_offset: int

    token_loop: for ; token != nil && token.kind != .EOF; token = token.next {
        eval_token := token.lit
        defer strings.write_string(&nv, eval_token)
        defer last_offset = token.pos.offset + len(token.lit)

        if token.has_space {
            for _ in 0 ..< (token.pos.offset - last_offset) {
                strings.write_rune(&nv, ' ')
            }
        }

        if token.kind == .Ident {
            p := token.next
            if p.kind == .Punct && p.lit == "(" {
                mc_name := token.lit
                macro: Macro = ---
                ok: bool = ---
                macro_func: MacroFunc = ---
                if macro, ok = om.get(macros, mc_name); ok {
                    macro_func, ok = macro.(MacroFunc)
                } else {
                    for inc in includes {
                        if macro, ok = om.get(inc.macros, mc_name); ok {
                            macro_func, ok = macro.(MacroFunc)
                            break
                        }
                    }
                }

                if !ok {
                    continue
                }

                mc: MacroFuncCall = ---
                mc, token = parse_macro_func_call(
                    p,
                    macros,
                    includes,
                ) or_return
                mc.macro_func = macro_func

                eval_token = evaluate_macro_func_call(
                    mc,
                    macros,
                    includes,
                    arena_alloc,
                ) or_return
            } else {
                mc_name := token.lit
                macro: Macro = ---
                ok: bool = ---
                v: MacroVar = ---
                if macro, ok = om.get(macros, mc_name); ok {
                    v, ok = macro.(MacroVar)
                } else {
                    for inc in includes {
                        if macro, ok = om.get(inc.macros, mc_name); ok {
                            v, ok = macro.(MacroVar)
                            break
                        }
                    }
                }

                if !ok {
                    continue token_loop
                }

                if v.value != nil {
                    eval, eval_err := evaluate_macro_var(
                        v.value.?,
                        macros,
                        includes,
                        arena_alloc,
                    )

                    if eval_err != nil {
                        when ODIN_DEBUG {
                            fmt.eprintfln(
                                "POST PROCESS :: macro var eval err {}=\"{}\" {}",
                                mc_name,
                                v.value.?,
                                eval_err,
                            )
                        }
                        continue token_loop
                    }

                    eval_token = eval
                } else {
                    eval_token = ""
                }
            }
        }
    }

    value_str = strings.to_string(nv)
    return
}

parse_macro_func_call :: proc(
    _token: ^ctz.Token,
    macros: om.OrderedMap(string, Macro),
    includes: []IncludedHeader,
) -> (
    mc: MacroFuncCall,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token.next
    if token.kind == .EOF do return mc, token, errors_eof(token)

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    args: [dynamic]string

    token_loop: for ; token != nil && token.kind != .EOF; token = token.next {
        arg: strings.Builder
        strings.builder_init_none(&arg)
        defer append(&args, strings.to_string(arg))

        last_offset := token.pos.offset

        arg_loop: for ; token != nil && token.kind != .EOF;
            token = token.next {
            defer last_offset = token.pos.offset + len(token.lit)

            if token.has_space {
                for _ in 0 ..< (token.pos.offset - last_offset) {
                    strings.write_rune(&arg, ' ')
                }
            }

            if token.kind == .Ident {
                p := token.next
                if p.kind == .Punct && p.lit == "(" {
                    mc_name := token.lit
                    macro: Macro = ---
                    ok: bool = ---
                    macro_func: MacroFunc = ---

                    if macro, ok = om.get(macros, mc_name); ok {
                        macro_func, ok = macro.(MacroFunc)
                    } else {
                        for inc in includes {
                            if macro, ok = om.get(inc.macros, mc_name); ok {
                                macro_func, ok = macro.(MacroFunc)
                                break
                            }
                        }
                    }

                    if !ok {
                        strings.write_string(&arg, token.lit)
                        continue
                    }

                    child: MacroFuncCall = ---
                    child, token = parse_macro_func_call(
                        p,
                        macros,
                        includes,
                    ) or_return
                    child.macro_func = macro_func

                    eval := evaluate_macro_func_call(
                        child,
                        macros,
                        includes,
                    ) or_return
                    strings.write_string(&arg, eval)
                } else {
                    mc_name := token.lit
                    macro: Macro = ---
                    ok: bool = ---
                    v: MacroVar = ---
                    if macro, ok = om.get(macros, mc_name); ok {
                        v, ok = macro.(MacroVar)
                    } else {
                        for inc in includes {
                            if macro, ok = om.get(inc.macros, mc_name); ok {
                                v, ok = macro.(MacroVar)
                                break
                            }
                        }
                    }

                    if ok && v.value != nil {
                        eval, eval_err := evaluate_macro_var(
                            v.value.?,
                            macros,
                            includes,
                            arena_alloc,
                        )

                        if eval_err != nil {
                            when ODIN_DEBUG {
                                fmt.eprintfln(
                                    "POST PROCESS :: macro func arg eval err {}=\"{}\" {}",
                                    mc_name,
                                    v.value.?,
                                    eval_err,
                                )
                            }
                            strings.write_string(&arg, token.lit)
                            continue token_loop
                        }

                        strings.write_string(&arg, eval)
                        continue token_loop
                    }

                    strings.write_string(&arg, token.lit)
                }
            } else {
                if token.lit != "," do strings.write_string(&arg, token.lit)
            }

            p := token.next
            if p.kind == .Punct {
                switch p.lit {
                case ",":
                    token = p
                    break arg_loop
                case ")":
                    token = p
                    break token_loop
                }
            }
        }
    }

    mc.args = args

    return
}

// MAYBEDO: pass enum values because they can also be referenced like macros
evaluate_macro_func_call :: proc(
    mc: MacroFuncCall,
    macros: om.OrderedMap(string, Macro),
    includes: []IncludedHeader,
    allocator := context.allocator,
) -> (
    eval: string,
    err: errors.Error,
) {
    using mc
    using mc.macro_func

    errors.assert(len(args) == len(parameters)) or_return

    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    for b in body {
        switch v in b {
        case string:
            strings.write_string(&buf, v)
        case MacroInsertion:
            for _ in 0 ..< v.spaces do strings.write_rune(&buf, ' ')
            strings.write_string(&buf, args[v.parameter])
        }
    }

    eval = evaluate_macro_var(
        strings.to_string(buf),
        macros,
        includes,
        allocator,
    ) or_return
    return
}
