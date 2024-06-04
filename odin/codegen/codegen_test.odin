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

import "../../runic"
import "core:c/libc"
import "core:io"
import "core:os"
import "core:strings"
import "core:testing"
import ccdg "root:c/codegen"
import om "root:ordered_map"

@(test)
test_to_odin_codegen :: proc(t: ^testing.T) {
    using testing

    ODIN_EXPECTED :: `package foo_pkg

odin_Anon0_bindings :: struct {
    x: f32,
    y: f32,
}
odin_Anon1_bindings :: struct {
    x: ^f32,
    y: ^f32,
}

odin_struct_bindings :: struct {
    context_: ^i32,
    baz: ^^[10]^^f64,
}
odin_complex_ptr_bindings :: [13][10][5]i32

when #config(FOO_PKG_STATIC, false) {
    foreign import foo_pkg_runic "system:libfoo.a"
} else {
    foreign import foo_pkg_runic "system:./libfoo.so"
}

@(default_calling_convention = "c")
foreign foo_pkg_runic {
    @(link_name = "foo_add_int_func")
    odin_add_int_bindings :: proc(a: i32, b: i32) -> i32 ---

    @(link_name = "foo_sub_float_funcZZtu73")
    odin_sub_float_bindings :: proc(a: odin_Anon0_bindings, b: odin_Anon1_bindings) -> f32 ---

    @(link_name = "foo_div_func")
    odin_div_bindings :: proc(a: [^]odin_struct_bindings, b: [^]odin_struct_bindings) -> f32 ---

}

odin_not_the_sub_bindings :: odin_add_int_bindings

main :: proc() {}`

    rs := runic.Runestone {
        version = 0,
        lib_shared = "./libfoo.so",
        lib_static = "libfoo.a",
        symbols = om.OrderedMap(string, runic.Symbol) {
            data =  {
                 {
                    key = "foo_add_int_func",
                    value =  {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.SInt32},
                            parameters =  {
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
                    value =  {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.Float32},
                            parameters =  {
                                {name = "a", type = {spec = runic.Anon(0)}},
                                {name = "b", type = {spec = runic.Anon(1)}},
                            },
                        },
                        remap = "foo_sub_float_funcZZtu73",
                    },
                },
                 {
                    key = "foo_div_func",
                    value =  {
                        value = runic.Function {
                            return_type = {spec = runic.Builtin.Float32},
                            parameters =  {
                                 {
                                    name = "a",
                                    type =  {
                                        spec = string("foo_struct_t"),
                                        array_info = {{}},
                                    },
                                },
                                 {
                                    name = "b",
                                    type =  {
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
            data =  {
                 {
                    key = "foo_struct_t",
                    value =  {
                        spec = runic.Struct {
                            members =  {
                                 {
                                    name = "context",
                                    type =  {
                                        spec = runic.Builtin.SInt32,
                                        pointer_info = {count = 1},
                                    },
                                },
                                 {
                                    name = "baz",
                                    type =  {
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
                    key = "complex_ptr_t",
                    value =  {
                        spec = runic.Builtin.SInt32,
                        array_info = {{size = 5}, {size = 10}, {size = 13}},
                    },
                },
            },
        },
        anon_types =  {
            runic.Struct {
                members =  {
                    {name = "x", type = {spec = runic.Builtin.Float32}},
                    {name = "y", type = {spec = runic.Builtin.Float32}},
                },
            },
            runic.Struct {
                members =  {
                     {
                        name = "x",
                        type =  {
                            spec = runic.Builtin.Float32,
                            pointer_info = {count = 1},
                        },
                    },
                     {
                        name = "y",
                        type =  {
                            spec = runic.Builtin.Float32,
                            pointer_info = {count = 1},
                        },
                    },
                },
            },
        },
    }

    rn := runic.To {
        language = "odin",
        package_name = "foo-pkg",
        trim_prefix = runic.TrimSet{"foo_", "foo_", "foo_", ""},
        trim_suffix = runic.TrimSet{functions = "_func", types = "_t"},
        add_prefix = runic.AddSet{"odin_", "odin_", "odin_", ""},
        add_suffix = runic.AddSet{"_bindings", "_bindings", "_bindings", ""},
    }

    {
        file, os_err := os.open(
            "test_data/bindings.odin",
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if !expect_value(t, os_err, 0) do return
        defer os.close(file)

        err := generate_bindings(rs, rn, os.stream_from_handle(file))
        if !expect_value(t, err, io.Error.None) do return

        os.write_string(file, "main :: proc() {}")
    }

    if c_err := libc.system("odin check test_data/bindings.odin -file"); !expect_value(t, c_err, 0) do return

    contents, os_err := os.read_entire_file("test_data/bindings.odin")
    if !expect(t, os_err) do return

    bindings := string(contents)
    expect_value(t, bindings, ODIN_EXPECTED)
}

@(test)
test_from_odin_codegen :: proc(t: ^testing.T) {
    using testing

    rune_file, os_err := os.open("test_data/foozy/rune.json")
    if !expect_value(t, os_err, 0) do return
    defer os.close(rune_file)

    rn, rn_err := runic.parse_rune(os.stream_from_handle(rune_file))
    if !expect_value(t, rn_err, nil) do return

    rs, rs_err := generate_runestone(
        "test_data/foozy/rune.json",
        rn.from.(runic.From),
    )
    if !expect_value(t, rs_err, nil) do return
    defer runic.runestone_destroy(&rs)

    out_file: os.Handle = ---
    out_file, os_err = os.open(
        "test_data/foozy/foozy.h",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, 0) do return
    defer os.close(out_file)

    ccdg_err := ccdg.generate_bindings(
        rs,
        rn.to.(runic.To),
        os.stream_from_handle(out_file),
    )
    if !expect_value(t, ccdg_err, nil) do return

    real_data, expected_data: []u8 = ---, ---
    ok: bool = ---

    real_data, ok = os.read_entire_file("test_data/foozy/foozy.h")
    if !expect(t, ok) do return
    expected_data, ok = os.read_entire_file("test_data/foozy/foozy.expected.h")
    if !expect(t, ok) do return

    real_string, _ := strings.replace(string(real_data), "\r", "", -1)
    expected_string, _ := strings.replace(string(expected_data), "\r", "", -1)

    expect_value(t, len(real_string), len(expected_string))
    expect_value(t, real_string, expected_string)
}
