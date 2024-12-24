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

import "core:fmt"
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
func.foo1234 = #Untyped a #SInt32 #Attr Ptr 1 #AttrEnd b #SInt32 #Attr Ptr 1 #AttrEnd
func.output_print_name = #SInt32 output output #Attr Ptr 1 #AttrEnd
func.print = #Untyped args #Variadic
func.funcy = #RawPtr
var.foo_varZZXX6 = #Float32 #Attr Ptr 1 Arr 10 #AttrEnd
var.idx = #UInt64
var.counter = #UInt8

[remap]
foo = foo1234
foo_var = foo_varZZXX6

[alias]
oof = foo

[extern]
SDL_Event = "SDL2/SDL_Event.h" #Struct key #SInt32 timestamp #SInt32

[types]
i32 = #SInt32
str = #UInt8 #Attr Ptr 1 #AttrEnd
anon_0 = #Struct desc str apple #UInt8
output = #Struct x #SInt32 y #SInt32 name str pear anon_0
output_flags = #Enum #SInt32 SHOWN 0 HIDDEN 1 OFF 20 ON "1+2"
numbers = #Float32 #Attr Arr 5 #AttrEnd
transform = #Float64 #Attr ReadOnly Arr 4 ReadOnly Arr 4 WriteOnly #AttrEnd
outer = #Float32 #Attr Ptr 1 Arr 2 #AttrEnd
times = #SInt32 #Attr Arr "5*6/3*(8%9)" #AttrEnd
anon_1 = #Struct x #SInt32 y #SInt32
super_ptr = anon_1 #Attr Ptr 1 #AttrEnd
Events = #Extern SDL_Event #Attr Arr 0 #AttrEnd

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
        Builtin.Untyped,
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

    expect_value(t, om.length(types), 12)
    expect_value(t, om.get(types, "super_ptr").pointer_info.count, 1)
    expect_value(t, len(om.get(types, "numbers").array_info), 1)
    expect_value(t, om.get(types, "numbers").array_info[0].size.(u64), 5)
    expect_value(
        t,
        om.get(types, "times").array_info[0].size.(string),
        "5*6/3*(8%9)",
    )
    expect_value(t, om.get(types, "transform").array_info[0].size.(u64), 4)
    expect_value(t, om.get(types, "transform").array_info[1].size.(u64), 4)
    expect_value(t, om.get(types, "Events").spec.(ExternType), "SDL_Event")

    expect_value(t, om.length(externs), 1)
    expect_value(t, om.get(externs, "SDL_Event").source, "SDL2/SDL_Event.h")
    expect_value(
        t,
        om.get(externs, "SDL_Event").type.spec.(Struct).members[0].name,
        "key",
    )

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

@(test)
test_cyclic_dependency :: proc(t: ^testing.T) {
    using testing

    types := om.OrderedMap(string, Type) {
        indices = {
            "little_foo" = 0,
            "big_foo" = 1,
            "cycle_0" = 2,
            "cycle_1" = 3,
            "cycle_2" = 4,
            "cycle_3" = 5,
            "struct_cycle_0" = 6,
            "random_thing" = 7,
            "random_int" = 8,
            "struct_cycle_1" = 9,
            "struct_cycle_2" = 10,
        },
        data = {
            {key = "little_foo", value = {spec = string("big_foo")}},
            {key = "big_foo", value = {spec = string("little_foo")}},
            {key = "cycle_0", value = {spec = string("cycle_1")}},
            {key = "cycle_1", value = {spec = string("cycle_2")}},
            {key = "cycle_2", value = {spec = string("cycle_3")}},
            {key = "cycle_3", value = {spec = string("cycle_0")}},
            {
                key = "struct_cycle_0",
                value = {
                    spec = Struct {
                        members = {
                            {type = {spec = string("random_thing")}},
                            {type = {spec = string("struct_cycle_1")}},
                        },
                    },
                },
            },
            {
                key = "random_thing",
                value = {
                    spec = Struct {
                        members = {{type = {spec = string("random_int")}}},
                    },
                },
            },
            {key = "random_int", value = {spec = Builtin.SInt32}},
            {
                key = "struct_cycle_1",
                value = {spec = string("struct_cycle_2")},
            },
            {
                key = "struct_cycle_2",
                value = {
                    spec = Struct {
                        members = {
                            {type = {spec = string("struct_cycle_1")}},
                            {type = {spec = string("struct_cycle_0")}},
                        },
                    },
                },
            },
        },
    }
    defer delete(types.indices)
    defer delete(types.data)
    defer for &entry in types.data {
        #partial switch &spec in entry.value.spec {
        case Struct:
            delete(spec.members)
        }
    }

    connected, visited_path := start_compute_cyclic_dependency(
        "little_foo",
        "big_foo",
        om.get(types, "big_foo"),
        types,
    )

    expect(t, connected)
    if expect_value(t, len(visited_path), 2) {
        expect_value(t, visited_path[0], "little_foo")
        expect_value(t, visited_path[1], "big_foo")
    }

    delete(visited_path)

    connected, visited_path = start_compute_cyclic_dependency(
        "cycle_0",
        "cycle_1",
        om.get(types, "cycle_1"),
        types,
    )

    expect(t, connected)
    if expect_value(t, len(visited_path), 4) {
        expect_value(t, visited_path[0], "cycle_0")
        expect_value(t, visited_path[1], "cycle_1")
        expect_value(t, visited_path[2], "cycle_2")
        expect_value(t, visited_path[3], "cycle_3")
    } else {
        fmt.printfln("visited_path: {}", visited_path)
    }

    delete(visited_path)

    connected, visited_path = start_compute_cyclic_dependency(
        "struct_cycle_0",
        "struct_cycle_1",
        om.get(types, "struct_cycle_1"),
        types,
    )

    expect(t, connected)
    if expect_value(t, len(visited_path), 3) {
        expect_value(t, visited_path[0], "struct_cycle_0")
        expect_value(t, visited_path[1], "struct_cycle_1")
        expect_value(t, visited_path[2], "struct_cycle_2")
    }

    delete(visited_path)

    pointer_type := Type {
        spec = string("pointed"),
        pointer_info = {count = 1},
    }

    expect(t, references_type_as_pointer_or_array(pointer_type, "pointed"))

    array_type := Type {
        spec       = string("arrayed"),
        array_info = {{size = 5}},
    }
    defer delete(array_type.array_info)

    expect(t, references_type_as_pointer_or_array(array_type, "arrayed"))
}

