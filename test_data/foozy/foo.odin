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

package foozy

import "../../runic"
import "base:runtime"
import fmty "core:fmt"

FOO_VALUE :: 5
FOO_VALUE_STR :: "5"
FOO_VALUE_LONG_STR :: `five`
FOO_FLOAT :: 5.6

cycle_pointer :: ^pointed_cycle
pointed_cycle :: struct {
    data: ^cycle_pointer,
}

foo_sausage :: sausage_foo

sausage_foo :: struct {
    s:    sausage,
    type: sausages,
}

my_foo :: struct {
    x: i8,
    y: u64,
}

your_foo :: struct #raw_union {
    x: u32,
    y: i32,
}

nested :: struct {
    x:   int,
    abc: struct {
        y:   int,
        cba: struct {
            z: int,
        },
    },
}

sausage :: i32

sausages :: enum {
    Weißwurst,
    Bratwurst,
    Käsekrainer = 69,
    Frankfurter = 1 + (1 + 1) * 2,
    Räucherwurst,
}

pants :: enum i32 {
    trousers,
    skirt,
    pantalones,
}

mega_int_slice :: [][][]int
super_int_slice :: []^^^[5][6][7]mega_int_slice

@(export)
foo :: proc "c" (a, b: int) -> int {
    return a + b * 2
}

@(export)
multi_foo :: proc "c" (a, b: int) -> (c, d: int) {
    return a + b, a - b
}

@(export = true)
super_foo :: proc "c" (a: my_foo) -> u32 {
    return u32(int(a.x) + int(a.y))
}

@(export)
print_pants :: proc "c" (a: pants) {
    context = runtime.default_context()
    fmty.println(a)
}

@(export)
print_sausages :: proc "c" (b: sausages) {
    context = runtime.default_context()
    fmty.println(b)
}

@(export)
multi_sausage :: proc "c" (over: ^^struct {
        a, b: int,
    }) -> struct #raw_union {
        x: u32,
        y: i32,
    } {
    context = runtime.default_context()
    fmty.print(over)
    rs: struct #raw_union {
        x: u32,
        y: i32,
    }
    rs.x = 5
    return rs
}

@(export)
print_slice :: proc "c" (s: []i64) {
    for i, idx in s {
        fmty.printfln("{}: \"{}\"", idx + 1, i)
    }
}

@(export)
add_slice :: proc "c" (s: ^[]i64, a: i64) {
    for &i in s {
        i += a
    }
}

@(export)
multi_add_slice :: proc "c" (ss: ^[5][]i64, a: i64) {
    for &s in ss {
        for &i in s {
            i += a
        }
    }
}

@(export)
cstring_to_string :: proc "c" (str: cstring) -> string {
    return strings.string_from_ptr(cast(^u8)str, len(str))
}

@(export)
print_strings :: proc "c" (str: []string) {
    for s, idx in str {
        fmt.printfln("{}: \"{}\"", idx, s)
    }
}

@(export, link_name = "your_var")
my_var: super_multi

@(export)
mumu: [^]f32

@(export)
error_callback: #type proc "c" (err: int) -> bool

