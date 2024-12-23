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
import "core:path/filepath"
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

    cwd := os.get_current_directory()
    defer delete(cwd)

    expect_value(t, rn.version, 0)

    expect_value(t, rn.from.(From).language, "c")
    expect_value(t, len(rn.platforms), 2)
    expect_value(t, rn.platforms[0].os, OS.Linux)
    expect_value(t, rn.platforms[1].os, OS.Windows)
    expect_value(t, rn.platforms[0].arch, Architecture.x86_64)
    expect_value(t, rn.platforms[1].arch, Architecture.x86_64)

    foo_h := filepath.join({cwd, "test_data/foo.h"})
    foz_h := filepath.join({cwd, "test_data/foz.h"})
    bar_h := filepath.join({cwd, "test_data/bar.h"})
    wrapper_gen_h := filepath.join({cwd, "test_data/wrapper.gen.h"})
    wrapper_macos_h := filepath.join({cwd, "test_data/wrapper.macos.h"})
    plat_macos_h := filepath.join({cwd, "test_data/plat_macos.h"})
    defer delete(foo_h)
    defer delete(foz_h)
    defer delete(bar_h)
    defer delete(wrapper_gen_h)
    defer delete(wrapper_macos_h)
    defer delete(plat_macos_h)

    f := rn.from.(From)
    any_headers := f.headers.d[{.Any, .Any}]
    macos_headers := f.headers.d[{.Macos, .Any}]
    expect_value(t, f.shared.d[Platform{.Any, .Any}], "libfoo.so")
    expect_value(t, len(any_headers), 4)
    expect_value(t, len(macos_headers), 2)
    expect_value(t, any_headers[0], foo_h)
    expect_value(t, any_headers[1], foz_h)
    expect_value(t, any_headers[2], bar_h)
    expect_value(t, any_headers[3], wrapper_gen_h)
    expect_value(t, macos_headers[0], plat_macos_h)
    expect_value(t, macos_headers[1], wrapper_macos_h)
    expect_value(t, len(f.overwrite.d[Platform{.Any, .Any}].types), 4)
    expect_value(t, len(f.overwrite.d[Platform{.Any, .Any}].functions), 3)
    expect_value(t, f.enable_host_includes.d[Platform{.Any, .Any}], true)
    expect_value(t, f.enable_host_includes.d[Platform{.Linux, .arm64}], false)
    expect_value(t, f.disable_system_include_gen.d[Platform{.Any, .Any}], true)
    expect_value(
        t,
        f.disable_system_include_gen.d[Platform{.Windows, .Any}],
        false,
    )
    expect_value(t, f.disable_stdint_macros.d[Platform{.Any, .Any}], true)
    expect_value(t, f.disable_stdint_macros.d[Platform{.Windows, .Any}], false)

    load_all_includes_any := f.load_all_includes.d[Platform{.Any, .Any}]
    load_all_includes_macos := f.load_all_includes.d[Platform{.Macos, .Any}]
    expect_value(t, load_all_includes_any, true)
    expect_value(t, load_all_includes_macos, false)

    forward_decl_type_any := f.forward_decl_type.d[Platform{.Any, .Any}]
    forward_decl_type_linux := f.forward_decl_type.d[Platform{.Linux, .Any}]
    forward_decl_type_windows :=
        f.forward_decl_type.d[Platform{.Windows, .Any}]
    expect_value(t, forward_decl_type_any.spec.(Builtin), Builtin.RawPtr)
    expect_value(t, forward_decl_type_linux.spec.(Builtin), Builtin.Untyped)
    expect_value(t, forward_decl_type_windows.spec.(Builtin), Builtin.SInt32)

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

    expect_value(t, len(f.extern), 1)
    expect_value(t, f.extern[0], "test_data/the_system/*")

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

    remaps := f.remaps
    expect_value(t, len(remaps), 2)
    expect_value(t, remaps["wl_surface_interface"], "wl_surface_interface_v")
    expect_value(t, remaps["wl_cursor_interface"], "wl_cursor_interface_v")

    aliases := f.aliases
    expect_value(t, len(aliases), 2)
    expect_value(t, len(aliases["SDL_Event"]), 1)
    expect_value(t, aliases["SDL_Event"][0], "SDL_Happening")
    expect_value(t, len(aliases["SDL_Renderer"]), 2)
    expect_value(t, aliases["SDL_Renderer"][0], "SDL_Painter")
    expect_value(t, aliases["SDL_Renderer"][1], "SDL_Drawer")

    in_header := filepath.join({cwd, "test_data/wrapper.h"})
    out_header := filepath.join({cwd, "test_data/wrapper.gen.h"})
    out_source := filepath.join({cwd, "test_data/wrapper.gen.c"})
    defer delete(in_header)
    defer delete(out_header)
    defer delete(out_source)

    wrapper := rn.wrapper.?
    expect_value(t, wrapper.language, "c")
    expect_value(t, wrapper.from_compiler_flags.d[{.Any, .Any}], false)
    expect_value(t, wrapper.add_header_to_from, true)
    expect_value(t, wrapper.defines.d[{.Any, .Any}]["FOO"], "BAR")
    expect_value(t, len(wrapper.in_headers.d[{.Any, .Any}]), 1)
    expect_value(t, wrapper.in_headers.d[{.Any, .Any}][0], in_header)
    expect_value(t, wrapper.out_header.d[{.Any, .Any}], out_header)
    expect_value(t, wrapper.out_source.d[{.Any, .Any}], out_source)

    wrapper_incs := wrapper.include_dirs.d[{.Any, .Any}]
    expect_value(t, len(wrapper_incs), 2)
    wi1 := filepath.join({cwd, "test_data/header_files/"})
    wi2 := filepath.join({cwd, "test_data/inc/other_headers"})
    defer delete(wi1)
    defer delete(wi2)
    expect_value(t, wrapper_incs[0], wi1)
    expect_value(t, wrapper_incs[1], wi2)
    expect_value(t, len(wrapper.flags.d[{.Any, .Any}]), 2)
    expect_value(t, wrapper.flags.d[{.Any, .Any}][0], "-fsomething")
    expect_value(t, wrapper.flags.d[{.Any, .Any}][1], "-nostdinc")
    expect_value(t, wrapper.load_all_includes.d[{.Any, .Any}], true)
    expect_value(t, len(wrapper.extern.d[{.Any, .Any}]), 2)

    ext1 := filepath.join({cwd, "test_data/stdarg.h"})
    ext2 := filepath.join({cwd, "test_data/third_party/files/*"})
    defer delete(ext1)
    defer delete(ext2)
    expect_value(t, wrapper.extern.d[{.Any, .Any}][0], ext1)
    expect_value(t, wrapper.extern.d[{.Any, .Any}][1], ext2)

    add_libs_any := platform_value_get([]string, to.add_libs, {.Any, .Any})
    add_libs_linux := platform_value_get([]string, to.add_libs, {.Linux, .Any})
    add_libs_win64 := platform_value_get(
        []string,
        to.add_libs,
        {.Windows, .x86_64},
    )

    test_data_dir, _ := filepath.abs("test_data")
    defer delete(test_data_dir)
    GLx86 := filepath.join({test_data_dir, "lib", "GLx86.lib"})
    defer delete(GLx86)

    expect_value(t, len(add_libs_any), 1)
    expect_value(t, len(add_libs_linux), 2)
    expect_value(t, len(add_libs_win64), 1)
    expect_value(t, add_libs_any[0], "libGL.so")
    expect_value(t, add_libs_linux[0], "libEGL.so")
    expect_value(t, add_libs_linux[1], "libGLX.so")
    expect_value(t, add_libs_win64[0], GLx86)
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

