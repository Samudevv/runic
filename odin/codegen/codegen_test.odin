#+ feature dynamic-literals
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
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import cppcdg "root:cpp/codegen"
import "root:diff"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

when ODIN_OS == .Windows {
    RUNESTONE_TEST_PATH :: "C:\\inline"
} else {
    RUNESTONE_TEST_PATH :: "/inline"
}

@(test)
test_to_odin_codegen :: proc(t: ^testing.T) {
    using testing

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

    ODIN_EXPECTED :: `#+build darwin amd64
package foo_pkg

odin_anon_0_bindings :: struct {
    x: f32,
    y: f32,
}
odin_anon_1_bindings :: struct {
    x: ^f32,
    y: ^f32,
}
odin_struct_bindings :: struct {
    context_m: ^i32,
    baz: [10]^^f64,
}
odin_bar_struct_bindings :: struct {
    odin_struct_bindings_m: odin_struct_bindings,
}
odin_bar_union_bindings :: struct #raw_union {
    odin_struct_bindings_m: odin_struct_bindings,
}
odin_complex_ptr_bindings :: [13][10][5]i32
odin_this_is_multis_bindings :: [^]^u8
odin_this_is_multi1s_bindings :: [^][10]^^u8

@(default_calling_convention = "c")
foreign foo_pkg_runic {
    @(link_name = "foo_add_int_func")
    odin_add_int_bindings :: proc(a: i32, b: i32) -> i32 ---

    @(link_name = "foo_sub_float_funcZZtu73")
    odin_sub_float_bindings :: proc(a: odin_anon_0_bindings, b: odin_anon_1_bindings) -> f32 ---

    @(link_name = "foo_div_func")
    odin_div_bindings :: proc(a: [^]odin_struct_bindings, odin_struct_bindings_p: [^]odin_struct_bindings) -> f32 ---

}

odin_not_the_sub_bindings :: odin_add_int_bindings

when #config(FOO_PKG_STATIC, false) {
    when ODIN_OS == .Darwin {
        foreign import foo_pkg_runic { "system:foo", "system:baz", "system:bar", "system:autumn", "lib/libcompiled.a" }
    } else {
        foreign import foo_pkg_runic { "system:libfoo.a", "system:libbaz.a", "system:libbar.a", "system:libautumn.a", "lib/libcompiled.a" }
    }
} else {
    foreign import foo_pkg_runic { "libfoo.so", "system:libbaz.a", "system:bar", "system:autumn", "lib/libcompiled.a" }
}

main :: proc() {}`


    abs_test_data, abs_ok := filepath.abs("test_data")
    if !expect(t, abs_ok) do return
    defer delete(abs_test_data)
    lib_shared := filepath.join({abs_test_data, "libfoo.so"})
    defer delete(lib_shared)

    rs := runic.Runestone {
        version = 0,
        platform = {.Macos, .x86_64},
        lib = {shared = lib_shared, static = "libfoo.a"},
        symbols = om.OrderedMap(string, runic.Symbol) {
            indices = {
                "foo_add_int_func" = 0,
                "foo_sub_float_func" = 1,
                "foo_div_func" = 2,
            },
            data = {
                {
                    key = "foo_add_int_func",
                    value = {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.SInt32},
                            parameters = {
                                {
                                    name = "a",
                                    type = {spec = runic.Builtin.SInt32},
                                },
                                {
                                    name = "b",
                                    type = {spec = runic.Builtin.SInt32},
                                },
                            },
                        },
                        aliases = {"not_the_sub"},
                    },
                },
                {
                    key = "foo_sub_float_func",
                    value = {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.Float32},
                            parameters = {
                                {name = "a", type = {spec = string("anon_0")}},
                                {name = "b", type = {spec = string("anon_1")}},
                            },
                        },
                        remap = "foo_sub_float_funcZZtu73",
                    },
                },
                {
                    key = "foo_div_func",
                    value = {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.Float32},
                            parameters = {
                                {
                                    name = "a",
                                    type = {
                                        spec = string("foo_struct_t"),
                                        array_info = {{}},
                                    },
                                },
                                {
                                    name = "odin_struct_bindings",
                                    type = {
                                        spec = string("foo_struct_t"),
                                        array_info = {{}},
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
        types = om.OrderedMap(string, runic.Type) {
            indices = {
                "anon_0" = 0,
                "anon_1" = 1,
                "foo_struct_t" = 2,
                "bar_struct_t" = 3,
                "bar_union" = 4,
                "complex_ptr_t" = 5,
                "this_is_multis" = 6,
                "this_is_multi1s" = 7,
            },
            data = {
                {
                    key = "anon_0",
                    value = {
                        spec = runic.Struct {
                            members = {
                                {
                                    name = "x",
                                    type = {spec = runic.Builtin.Float32},
                                },
                                {
                                    name = "y",
                                    type = {spec = runic.Builtin.Float32},
                                },
                            },
                        },
                    },
                },
                {
                    key = "anon_1",
                    value = {
                        spec = runic.Struct {
                            members = {
                                {
                                    name = "x",
                                    type = {
                                        spec = runic.Builtin.Float32,
                                        pointer_info = {count = 1},
                                    },
                                },
                                {
                                    name = "y",
                                    type = {
                                        spec = runic.Builtin.Float32,
                                        pointer_info = {count = 1},
                                    },
                                },
                            },
                        },
                    },
                },
                {
                    key = "foo_struct_t",
                    value = {
                        spec = runic.Struct {
                            members = {
                                {
                                    name = "context",
                                    type = {
                                        spec = runic.Builtin.SInt32,
                                        pointer_info = {count = 1},
                                    },
                                },
                                {
                                    name = "baz",
                                    type = {
                                        spec = runic.Builtin.Float64,
                                        pointer_info = {count = 2},
                                        array_info = {{size = 10}},
                                    },
                                },
                            },
                        },
                    },
                },
                {
                    key = "bar_struct_t",
                    value = {
                        spec = runic.Struct {
                            members = {
                                {
                                    name = "odin_struct_bindings",
                                    type = {spec = string("foo_struct_t")},
                                },
                            },
                        },
                    },
                },
                {
                    key = "bar_union",
                    value = {
                        spec = runic.Union {
                            members = {
                                {
                                    name = "odin_struct_bindings",
                                    type = {spec = string("foo_struct_t")},
                                },
                            },
                        },
                    },
                },
                {
                    key = "complex_ptr_t",
                    value = {
                        spec = runic.Builtin.SInt32,
                        array_info = {{size = 5}, {size = 10}, {size = 13}},
                    },
                },
                {
                    key = "this_is_multis",
                    value = {
                        spec = runic.Builtin.UInt8,
                        pointer_info = {count = 2},
                    },
                },
                {
                    key = "this_is_multi1s",
                    value = {
                        spec = runic.Builtin.UInt8,
                        pointer_info = {count = 2},
                        array_info = {{size = 10, pointer_info = {count = 1}}},
                    },
                },
            },
        },
    }

    test_data_dir, _ := filepath.abs("test_data")
    defer delete(test_data_dir)
    libcompiled := filepath.join({test_data_dir, "lib", "libcompiled.a"})
    defer delete(libcompiled)

    rn := runic.To {
        language = "odin",
        package_name = "foo-pkg",
        trim_prefix = runic.TrimPrefix {
            {{"foo_"}, {"foo_"}, {"foo_"}, {""}},
            false,
        },
        trim_suffix = runic.TrimSet{functions = {"_func"}, types = {"_t"}},
        add_prefix = runic.AddSet{"odin_", "odin_", "odin_", ""},
        add_suffix = runic.AddSet{"_bindings", "_bindings", "_bindings", ""},
        detect = {multi_pointer = "auto"},
        add_libs_shared = {
            d = {
                {.Any, .Any} = {
                    "libbaz.a",
                    "libbar.so",
                    "libautumn.dylib",
                    libcompiled,
                },
            },
        },
        add_libs_static = {
            d = {
                {.Any, .Any} = {
                    "libbaz.a",
                    "libbar.a",
                    "libautumn.a",
                    libcompiled,
                },
            },
        },
    }
    defer delete(rn.add_libs_shared.d)
    defer delete(rn.add_libs_static.d)

    runic.to_preprocess_runestone(&rs, rn, ODIN_RESERVED)

    abs_file_name: string = ---
    defer delete(abs_file_name)
    {
        abs_file_name = filepath.join({abs_test_data, "bindings.odin"})

        file, os_err := os.open(
            abs_file_name,
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if !expect_value(t, os_err, nil) do return
        defer os.close(file)

        rc: runic.Runecross
        append(
            &rc.cross,
            runic.PlatformRunestone {
                plats = {{}},
                runestone = {file_path = abs_file_name, stone = rs},
            },
        )

        err := errors.wrap(
            generate_bindings(
                rc,
                rn,
                {{.Macos, .x86_64}},
                os.stream_from_handle(file),
                abs_file_name,
            ),
        )
        if !expect_value(t, err, nil) do return

        os.write_string(file, "main :: proc() {}")
    }

    contents, os_err := os.read_entire_file(abs_file_name)
    if !expect(t, os_err) do return

    diff.expect_diff_strings(t, ODIN_EXPECTED, string(contents), ".odin")
}

@(test)
test_to_odin_extern :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libsystem_include.so"}},
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/system_include.h"}},
        },
        flags = {
            d = {
                runic.Platform{.Any, .Any} = {
                    "-Itest_data/the_system",
                    "-Itest_data/third_party",
                    "-Itest_data/other_system",
                },
            },
        },
        extern = {
            "test_data/the_system/my_system.h",
            "test_data/third_party/third_party.h",
            "test_data/other_system/also_my_system.h",
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)
    defer delete(rf.flags.d)
    rt := runic.To {
        language = "odin",
        package_name = "extern_test",
        extern = {
            sources = {
                "test_data/the_system/my_system.h" = "the_system vendor:sys",
                "test_data/third_party/*" = "shared:third_party",
            },
            remaps = {"ant" = "Ant"},
        },
        no_build_tag = true,
    }
    defer delete(rt.extern.sources)
    defer delete(rt.extern.remaps)

    rs, err := cppcdg.generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    runic.from_postprocess_runestone(&rs, rf)

    rs_out, os_err := os.open(
        "test_data/extern_test_runestone.ini",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return
    defer os.close(rs_out)

    expect_value(
        t,
        runic.write_runestone(
            rs,
            os.stream_from_handle(rs_out),
            "test_data/extern_test_runestone.ini",
        ),
        io.Error.None,
    )

    runic.to_preprocess_runestone(&rs, rt, ODIN_RESERVED)

    rc: runic.Runecross = ---
    rc, err = runic.cross_the_runes({RUNESTONE_TEST_PATH}, {rs})
    if !expect_value(t, err, nil) do return
    defer runic.runecross_destroy(&rc)

    out_file: os.Handle = ---
    out_file, os_err = os.open(
        "test_data/extern_test.odin",
        os.O_CREATE | os.O_TRUNC | os.O_WRONLY,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return

    err = errors.wrap(
        generate_bindings(
            rc,
            rt,
            {runic.platform_from_host()},
            os.stream_from_handle(out_file),
            RUNESTONE_TEST_PATH,
        ),
    )
    os.close(out_file)
    if !expect_value(t, err, nil) do return

    EXPECT_BINDINGS :: `package extern_test

import "shared:third_party"
import the_system "vendor:sys"

sysi :: f64
from_main :: i32
from_other_system :: sysi
main_struct :: struct {
    b: the_system.from_system,
}

@(default_calling_convention = "c")
foreign extern_test_runic {
    @(link_name = "ctx")
    ctx: main_struct

    @(link_name = "part")
    part :: proc(a: the_system.from_system, b: ^third_party.Ant) -> the_system.from_system ---

    @(link_name = "make_feature")
    make_feature :: proc(feature: ^third_party.feature_t) -> cstring ---

    @(link_name = "new_donkey")
    new_donkey :: proc() -> third_party.donkey_t ---

}

foreign import extern_test_runic "system:system_include"

`


    data, ok := os.read_entire_file("test_data/extern_test.odin")
    if !expect(t, ok) do return
    defer delete(data)

    diff.expect_diff_strings(t, EXPECT_BINDINGS, string(data), ".odin")
}

@(test)
test_odin_import_path :: proc(t: ^testing.T) {
    using testing

    ow, path := import_path("util")
    expect_value(t, ow, "")
    expect_value(t, path, "util")

    ow, path = import_path("u util")
    expect_value(t, ow, "u")
    expect_value(t, path, "util")

    ow, path = import_path("u ../util")
    expect_value(t, ow, "u")
    expect_value(t, path, "../util")

    expect_value(t, import_prefix("util"), "util")
    expect_value(t, import_prefix("u util"), "u")
    expect_value(t, import_prefix("core:util"), "util")
    expect_value(t, import_prefix("u core:util"), "u")
    expect_value(t, import_prefix("../../../util"), "util")
}

@(test)
test_odin_to_multiple_files :: proc(t: ^testing.T) {
    using testing

    LINUX_RUNESTONE :: `version = 0
os = Linux
arch = x86_64

[lib]
shared = libmulti.so

[extern]
Person = "person.h" #Struct age #SInt32 name #String
Car = "car.h" #Struct tires #SInt32 owner #Extern Person
Animal = "animal.h" #Struct species #String vehicle #Extern Car
Dev = "dev.h" #Extern Person #Attr Ptr 1 #AttrEnd

[symbols]
func.car_drive = #Untyped car #Extern Car #Attr Ptr 1 #AttrEnd
func.animal_growl = #Untyped animal #Extern Animal #Attr Ptr 1 #AttrEnd
func.dev_code = #Untyped dev #Extern Dev #Attr Ptr 1 #AttrEnd lines #UInt64
`


    WINDOWS_RUNESTONE :: `version = 0
os = Windows
arch = x86_64

[lib]
shared = multid.lib

[extern]
Person = "person.h" #Struct age #SInt32 name #String
Car = "car.h" #Struct tires #SInt32 owner #Extern Person
Animal = "animal.h" #Struct species #String vehicle #Extern Car
OfficeWorker = "office_worker.h" #Extern Person #Attr Ptr 1 #AttrEnd

[symbols]
func.car_drive = #Untyped car #Extern Car #Attr Ptr 1 #AttrEnd
func.animal_growl = #Untyped animal #Extern Animal #Attr Ptr 1 #AttrEnd
func.office_worker_write_off_taxes = #Untyped ow #Extern OfficeWorker #Attr Ptr 1 #AttrEnd year #UInt64 amount_in_dollar #SInt64
`


    MACOS_RUNESTONE :: `version = 0
os = Macos
arch = x86_64

[lib]
shared = libmulti.so

[extern]
Person = "person.h" #Struct age #SInt32 name #String
Car = "car.h" #Struct tires #SInt32 owner #Extern Person
Animal = "animal.h" #Struct species #String vehicle #Extern Car
Designer = "designer.h" #Extern Person #Attr Ptr 1 #AttrEnd

[symbols]
func.car_drive = #Untyped car #Extern Car #Attr Ptr 1 #AttrEnd
func.animal_growl = #Untyped animal #Extern Animal #Attr Ptr 1 #AttrEnd
func.designer_draw_design = #Untyped designer #Extern Designer #Attr Ptr 1 #AttrEnd width #UInt64 height #UInt64
`


    cwd := os.get_current_directory()
    defer delete(cwd)
    test_data_dir := filepath.join({cwd, "test_data"})
    defer delete(test_data_dir)

    linux_rs_path := filepath.join({test_data_dir, "linux_rs"})
    windows_rs_path := filepath.join({test_data_dir, "windows_rs"})
    macos_rs_path := filepath.join({test_data_dir, "macos_rs"})
    defer delete(linux_rs_path)
    defer delete(windows_rs_path)
    defer delete(macos_rs_path)

    out_path := filepath.join(
        {test_data_dir, "test_odin_to_multiple_files.odin"},
    )
    defer delete(out_path)

    rn := runic.To {
        language = "odin",
        out = out_path,
        package_name = "multi",
        extern = {
            sources = {
                "person.h" = "vendor:person",
                "car.h" = "vendor:car",
                "animal.h" = "vendor:animal",
                "dev.h" = "vendor:dev",
                "office_worker.h" = "vendor:office",
                "designer.h" = "vendor:design",
            },
        },
    }
    defer delete(rn.extern.sources)


    linux_rs_reader, windows_rs_reader, macos_rs_reader: strings.Reader
    strings.reader_init(&linux_rs_reader, LINUX_RUNESTONE)
    strings.reader_init(&windows_rs_reader, WINDOWS_RUNESTONE)
    strings.reader_init(&macos_rs_reader, MACOS_RUNESTONE)

    linux_rs, linux_rs_err := runic.parse_runestone(
        strings.reader_to_stream(&linux_rs_reader),
        linux_rs_path,
    )
    if !expect_value(t, linux_rs_err, nil) do return
    windows_rs, windows_rs_err := runic.parse_runestone(
        strings.reader_to_stream(&windows_rs_reader),
        windows_rs_path,
    )
    if !expect_value(t, windows_rs_err, nil) do return
    macos_rs, macos_rs_err := runic.parse_runestone(
        strings.reader_to_stream(&macos_rs_reader),
        macos_rs_path,
    )
    if !expect_value(t, macos_rs_err, nil) do return

    defer runic.runestone_destroy(&linux_rs)
    defer runic.runestone_destroy(&windows_rs)
    defer runic.runestone_destroy(&macos_rs)

    rc, rc_err := runic.cross_the_runes(
        {linux_rs_path, windows_rs_path, macos_rs_path},
        {linux_rs, windows_rs, macos_rs},
        rn.extern.sources,
    )
    if !expect_value(t, rc_err, nil) do return
    defer runic.runecross_destroy(&rc)

    out_file, out_err := os.open(
        out_path,
        os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, out_err, nil) do return
    defer os.close(out_file)

    odin_err := generate_bindings(
        rc,
        rn,
        {{.Linux, .x86_64}, {.Windows, .x86_64}, {.Macos, .x86_64}},
        os.stream_from_handle(out_file),
        rn.out,
    )
    if !expect_value(t, errors.wrap(odin_err), nil) do return

    ANY_EXPECTED :: `#+build linux amd64, windows amd64, darwin amd64
package multi

import "vendor:animal"
import "vendor:car"

@(default_calling_convention = "c")
foreign multi_runic {
    @(link_name = "car_drive")
    car_drive :: proc(car: ^car.Car) ---

    @(link_name = "animal_growl")
    animal_growl :: proc(animal: ^animal.Animal) ---

}

when (ODIN_OS == .Windows) {

foreign import multi_runic "system:multid.lib"

}

when (ODIN_OS == .Linux) || (ODIN_OS == .Darwin) {

foreign import multi_runic "system:multi"

}

`


    LINUX_EXPECTED :: `#+build linux amd64
package multi

import "vendor:dev"

@(default_calling_convention = "c")
foreign multi_runic {
    @(link_name = "dev_code")
    dev_code :: proc(dev: ^dev.Dev, lines: u64) ---

}

foreign import multi_runic "system:multi"

`


    WINDOWS_EXPECTED :: `#+build windows amd64
package multi

import "vendor:office"

@(default_calling_convention = "c")
foreign multi_runic {
    @(link_name = "office_worker_write_off_taxes")
    office_worker_write_off_taxes :: proc(ow: ^office.OfficeWorker, year: u64, amount_in_dollar: i64) ---

}

foreign import multi_runic "system:multid.lib"

`


    MACOS_EXPECTED :: `#+build darwin amd64
package multi

import "vendor:design"

@(default_calling_convention = "c")
foreign multi_runic {
    @(link_name = "designer_draw_design")
    designer_draw_design :: proc(designer: ^design.Designer, width: u64, height: u64) ---

}

foreign import multi_runic "system:multi"

`


    linux_path := filepath.join(
        {test_data_dir, "test_odin_to_multiple_files-Linux.odin"},
    )
    windows_path := filepath.join(
        {test_data_dir, "test_odin_to_multiple_files-Windows.odin"},
    )
    macos_path := filepath.join(
        {test_data_dir, "test_odin_to_multiple_files-Macos.odin"},
    )
    defer delete(linux_path)
    defer delete(windows_path)
    defer delete(macos_path)

    any_data, any_data_ok := os.read_entire_file(out_path)
    if !expect(t, any_data_ok) do return
    defer delete(any_data)

    linux_data, linux_data_ok := os.read_entire_file(linux_path)
    if !expect(t, linux_data_ok) do return
    defer delete(linux_data)

    windows_data, windows_data_ok := os.read_entire_file(windows_path)
    if !expect(t, windows_data_ok) do return
    defer delete(windows_data)

    macos_data, macos_data_ok := os.read_entire_file(macos_path)
    if !expect(t, macos_data_ok) do return
    defer delete(macos_data)

    diff.expect_diff_strings(t, ANY_EXPECTED, string(any_data))
    diff.expect_diff_strings(t, LINUX_EXPECTED, string(linux_data))
    diff.expect_diff_strings(t, WINDOWS_EXPECTED, string(windows_data))
    diff.expect_diff_strings(t, MACOS_EXPECTED, string(macos_data))
}
