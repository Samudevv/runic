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

package runic

import "base:runtime"
import "core:os"
import "core:testing"
import "root:errors"
import om "root:ordered_map"

@(test)
test_rune :: proc(t: ^testing.T) {
    using testing

    file, os_err := os.open("test_data/rune.yml")
    if !expect_value(t, os_err, nil) do return
    defer os.close(file)

    rn, err := parse_rune(os.stream_from_handle(file), "test_data/rune.yml")
    defer rune_destroy(&rn)
    if !expect_value(t, err, nil) do return

    expect_value(t, rn.version, 0)

    expect_value(t, rn.from.(From).language, "c")
    expect_value(t, len(rn.platforms), 2)
    expect_value(t, rn.platforms[0].os, OS.Linux)
    expect_value(t, rn.platforms[1].os, OS.Windows)
    expect_value(t, rn.platforms[0].arch, Architecture.x86_64)
    expect_value(t, rn.platforms[1].arch, Architecture.x86_64)

    f := rn.from.(From)
    expect_value(t, f.shared.d[Platform{.Any, .Any}], "libfoo.so")
    expect_value(t, len(f.headers.d[Platform{.Any, .Any}]), 3)
    expect_value(t, len(f.headers.d[Platform{.Macos, .Any}]), 1)
    expect_value(t, len(f.overwrite.d[Platform{.Any, .Any}].types), 4)
    expect_value(t, len(f.overwrite.d[Platform{.Any, .Any}].functions), 3)

    ow := f.overwrite.d[Platform{.Any, .Any}]
    expect_value(t, len(ow.functions), 3)
    for func in ow.functions {
        switch func.name {
        case "funcy":
            expect_value(t, func.instruction.(OverwriteParameterName).idx, 0)
            expect_value(
                t,
                func.instruction.(OverwriteParameterName).overwrite,
                "input",
            )
        case "sunky":
            expect_value(t, func.instruction.(OverwriteParameterType).idx, 1)
            expect_value(
                t,
                func.instruction.(OverwriteParameterType).overwrite,
                "output",
            )
        case "uinky":
            expect_value(t, func.instruction.(OverwriteReturnType), "#SInt32")
        case:
            fail(t)
        }
    }

    for type in ow.types {
        switch type.name {
        case "size_t":
            expect_value(t, type.instruction.(OverwriteWhole), "#UInt64")
        case "func_ptr":
            #partial switch ins in type.instruction {
            case OverwriteParameterType:
                expect_value(t, ins.idx, 1)
                expect_value(t, ins.overwrite, "wl_seat #Attr Ptr 1 #AttrEnd")
            case OverwriteParameterName:
                expect_value(t, ins.idx, 0)
                expect_value(t, ins.overwrite, "bar")
            case OverwriteReturnType:
                expect_value(t, ins, "#RawPtr")
            case:
                fail(t)
            }
        case:
            fail(t)
        }
    }

    to := rn.to.(To)
    expect_value(t, to.static_switch, "FOO_STATIC")

    extern := to.extern
    expect_value(t, extern.trim_prefix, true)
    expect_value(t, extern.trim_suffix, false)
    expect_value(t, extern.add_prefix, false)
    expect_value(t, extern.add_suffix, false)
    expect_value(t, len(extern.sources), 2)
    expect_value(t, extern.sources["SDL2/SDL_Event.h"], "vendor:sdl2")
    expect_value(t, extern.sources["SDL2/SDL_Renderer.h"], "vendor:sdl2")
    expect_value(t, len(extern.remaps), 1)
    expect_value(t, extern.remaps["SDL_Renderer"], "Renderer")
}

@(test)
test_overwrite :: proc(t: ^testing.T) {
    using testing

    rs: Runestone
    defer runestone_destroy(&rs)

    context.allocator = runtime.arena_allocator(&rs.arena)

    var, type, func_ptr, unon: Type = ---, ---, ---, ---
    func1, func2: Function = ---, ---
    const: Constant = ---
    err: errors.Error = ---

    var, err = parse_type("#SInt32")
    if !expect_value(t, err, nil) do return
    type, err = parse_type("#String #Attr Arr 5 #AttrEnd")
    if !expect_value(t, err, nil) do return
    func_ptr, err = parse_type("#FuncPtr #Void a #SInt32 b #Float32")
    if !expect_value(t, err, nil) do return
    unon, err = parse_type("#Union foo #RawPtr bar #RawPtr")
    if !expect_value(t, err, nil) do return

    func1, err = parse_func("#Void a #SInt32 b #String")
    if !expect_value(t, err, nil) do return
    func2, err = parse_func("#UInt32 a #SInt32 b #String")
    if !expect_value(t, err, nil) do return


    const, err = parse_constant("15 #Untyped")
    if !expect_value(t, err, nil) do return

    overwrite := OverwriteSet {
        variables = {{"var", OverwriteWhole("#UInt32")}},
        functions = {
            {"func1", OverwriteReturnType("#Bool32")},
            {"func1", OverwriteParameterName{idx = 1, overwrite = "str"}},
            {"func2", OverwriteParameterType{idx = 0, overwrite = "#UInt64"}},
            {
                "func2",
                OverwriteParameterType {
                    idx = 1,
                    overwrite = "#UInt8 #Attr Ptr 1 #AttrEnd",
                },
            },
        },
        types     = {
            {"type", OverwriteWhole("#RawPtr")},
            {
                "func_ptr",
                OverwriteParameterType{idx = 0, overwrite = "#Float32"},
            },
            {"func_ptr", OverwriteParameterName{idx = 1, overwrite = "c"}},
            {"func_ptr", OverwriteReturnType("#SInt32")},
            {"unon", OverwriteMemberType{idx = 0, overwrite = "#UInt64"}},
            {"unon", OverwriteMemberName{idx = 1, overwrite = "baz"}},
        },
        constants = {{"const", OverwriteWhole("27 #UInt64")}},
    }

    om.insert(&rs.types, "type", type)
    om.insert(&rs.types, "func_ptr", func_ptr)
    om.insert(&rs.types, "unon", unon)
    om.insert(&rs.symbols, "var", Symbol{value = var})
    om.insert(&rs.symbols, "func1", Symbol{value = func1})
    om.insert(&rs.symbols, "func2", Symbol{value = func2})
    om.insert(&rs.constants, "const", const)

    overwrite_runestone(&rs, overwrite)

    type = om.get(rs.types, "type")
    expect_value(t, type.spec.(Builtin), Builtin.RawPtr)
    expect_value(t, len(type.array_info), 0)

    func_ptr = om.get(rs.types, "func_ptr")
    expect_value(
        t,
        func_ptr.spec.(FunctionPointer).return_type.spec.(Builtin),
        Builtin.SInt32,
    )
    expect_value(t, len(func_ptr.spec.(FunctionPointer).parameters), 2)
    expect_value(
        t,
        func_ptr.spec.(FunctionPointer).parameters[0].type.spec.(Builtin),
        Builtin.Float32,
    )
    expect_value(t, func_ptr.spec.(FunctionPointer).parameters[1].name, "c")
    expect_value(t, func_ptr.spec.(FunctionPointer).parameters[0].name, "a")

    unon = om.get(rs.types, "unon")
    expect_value(t, len(unon.spec.(Union).members), 2)
    expect_value(
        t,
        unon.spec.(Union).members[0].type.spec.(Builtin),
        Builtin.UInt64,
    )
    expect_value(t, unon.spec.(Union).members[1].name, "baz")

    func1 = om.get(rs.symbols, "func1").value.(Function)
    expect_value(t, func1.return_type.spec.(Builtin), Builtin.Bool32)
    expect_value(t, func1.parameters[1].name, "str")

    func2 = om.get(rs.symbols, "func2").value.(Function)
    expect_value(t, func2.parameters[0].type.spec.(Builtin), Builtin.UInt64)
    expect_value(t, func2.parameters[1].type.spec.(Builtin), Builtin.UInt8)
    expect_value(t, func2.parameters[1].type.pointer_info.count, 1)

    var = om.get(rs.symbols, "var").value.(Type)
    expect_value(t, var.spec.(Builtin), Builtin.UInt32)

    const = om.get(rs.constants, "const")
    expect_value(t, const.value.(i64), 27)
    expect_value(t, const.type.spec.(Builtin), Builtin.UInt64)
}

