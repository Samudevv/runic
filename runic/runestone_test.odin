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

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"
import om "root:ordered_map"

EXAMPLE_RUNESTONE :: `
version = 0

os = Linux
arch = x86_64

[lib]
shared = libfoo.so
static = libfoo.a

[symbols]
func.foo1234 = #Void a #SInt32 #Attr Ptr 1 #AttrEnd b #SInt32 #Attr Ptr 1 #AttrEnd
func.output_print_name = #SInt32 output output #Attr Ptr 1 #AttrEnd
func.print = #Void args #Variadic
func.funcy = #RawPtr
var.foo_varZZXX6 = #Float32 #Attr Ptr 1 Arr 10 #AttrEnd
var.idx = #UInt64
var.counter = #UInt8

[remap]
foo = foo1234
foo_var = foo_varZZXX6

[alias]
oof = foo

[types]
i32 = #SInt32
str = #UInt8 #Attr Ptr 1 #AttrEnd
anon_0 = #Struct desc str apple #UInt8
output = #Struct x #SInt32 y #SInt32 name str pear anon_0
output_flags = #Enum #SInt32 SHOWN 0 HIDDEN 1 OFF ARR_CAP ON "1+2"
numbers = #Float32 #Attr Arr ARR_SIZE #AttrEnd
transform = #Float64 #Attr ReadOnly Arr 4 ReadOnly Arr 4 WriteOnly #AttrEnd
outer = #Float32 #Attr Ptr 1 Arr 2 #AttrEnd
times = #SInt32 #Attr Arr "5*6/3*(8%9)" #AttrEnd
anon_1 = #Struct x #SInt32 y #SInt32
super_ptr = anon_1 #Attr Ptr 1 #AttrEnd

[methods]
output.print_name = output_print_name

[constants]
ARR_SIZE = 5 #Untyped
ARR_CAP = 20 #UInt64
APP_NAME = "Hello World" #SInt8 #Attr Ptr 1 #AttrEnd
LENGTH = 267.345 #Float64
`

@(test)
test_example_runestone :: proc(t: ^testing.T) {
    using testing

    rd: strings.Reader
    strings.reader_init(&rd, string(EXAMPLE_RUNESTONE))


    rs, err := parse_runestone(strings.reader_to_stream(&rd), "/example")
    defer runestone_destroy(&rs)
    if !expect_value(t, err, nil) do return

    using rs

    expect_value(t, version, 0)

    expect_value(t, platform.os, OS.Linux)
    expect_value(t, platform.arch, Architecture.x86_64)

    expect_value(t, lib.shared.?, "libfoo.so")
    expect_value(t, lib.static.?, "libfoo.a")

    expect_value(t, om.length(symbols), 7)
    expect_value(
        t,
        om.get(symbols, "foo").value.(Function).return_type.spec.(Builtin),
        Builtin.Void,
    )
    expect_value(t, len(om.get(symbols, "foo").value.(Function).parameters), 2)
    expect_value(
        t,
        om.get(symbols, "foo").value.(Function).parameters[0].name,
        "a",
    )
    expect_value(
        t,
        om.get(symbols, "foo").value.(Function).parameters[1].name,
        "b",
    )
    expect_value(t, om.get(symbols, "foo").aliases[0], "oof")
    expect_value(t, om.get(symbols, "foo").remap, "foo1234")
    expect_value(t, om.get(symbols, "foo_var").remap, "foo_varZZXX6")
    expect_value(
        t,
        om.get(symbols, "funcy").value.(Function).return_type.spec.(Builtin),
        Builtin.RawPtr,
    )
    expect_value(
        t,
        len(om.get(symbols, "funcy").value.(Function).parameters),
        0,
    )
    expect_value(
        t,
        om.get(symbols, "output_print_name").value.(Function).method_info.?.type,
        "output",
    )
    expect_value(
        t,
        om.get(symbols, "output_print_name").value.(Function).method_info.?.name,
        "print_name",
    )
    expect_value(
        t,
        om.get(symbols, "idx").value.(Type).spec.(Builtin),
        Builtin.UInt64,
    )
    expect_value(
        t,
        om.get(symbols, "counter").value.(Type).spec.(Builtin),
        Builtin.UInt8,
    )

    expect_value(t, om.length(types), 11)
    expect_value(t, om.get(types, "super_ptr").pointer_info.count, 1)
    expect_value(t, len(om.get(types, "numbers").array_info), 1)
    expect_value(
        t,
        om.get(types, "numbers").array_info[0].size.(ConstantRef).name,
        "ARR_SIZE",
    )
    expect_value(
        t,
        om.get(types, "times").array_info[0].size.(string),
        "5*6/3*(8%9)",
    )
    expect_value(t, om.get(types, "transform").array_info[0].size.(u64), 4)
    expect_value(t, om.get(types, "transform").array_info[1].size.(u64), 4)

    out_file, os_err := os.open(
        "test_data/example_runestone.ini",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return
    defer os.close(out_file)

    io_err := write_runestone(
        rs,
        os.stream_from_handle(out_file),
        "test_data/example_runestone.ini",
    )
    if !expect_value(t, io_err, io.Error.None) do return

    if !expect_value(t, om.length(constants), 4) do return
    expect_value(t, om.get(constants, "ARR_SIZE").value.(i64), 5)
    expect_value(t, om.get(constants, "ARR_CAP").value.(i64), 20)
    expect_value(
        t,
        om.get(constants, "APP_NAME").value.(string),
        "Hello World",
    )
    expect_value(t, om.get(constants, "LENGTH").value.(f64), 267.345)
}

