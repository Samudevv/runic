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
import bin "base:builtin"
import "base:intrinsics"
import "base:runtime"
import "booty"
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
confusing_type :: [dynamic][dynamic][dynamic][][][][5]^^^u8

my_allocator :: runtime.Allocator
my_obj :: intrinsics.objc_object
my_great_int :: bin.int

beans :: [128]u128

simple_bf :: bit_field u16 {}
array_bf :: bit_field [5]i32 {}
other_array_bf :: bit_field [2]my_great_int {}
package_bf :: bit_field booty.boot_int {}
other_package_bf :: bit_field [50]booty.boot_int {}
bean_plantation :: bit_field beans {}

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

@(export)
odin_default_context :: proc "c" () -> runtime.Context {
    return runtime.default_context()
}

@(export)
append_five :: proc "c" (arr: ^[dynamic]int, value: int) {
    for _ in 0 ..< 5 {
        append(arr, value)
    }
}

@(export)
make_large_array :: proc "c" (
    s: booty.small_array,
    t: typeid,
    a: any,
) -> booty.large_array {
    context = runtime.default_context()
    return make(booty.large_array)
}

@(export, link_name = "your_var")
my_var: super_multi

@(export)
mumu: [^]f32

@(export)
error_callback: #type proc "c" (err: int) -> bool

@(export)
multi_pant: bit_set[pants]

@(export)
polyglot: bit_set[languages]
@(export)
polyglot1: bit_set[languages]
@(export)
polyglot2: bit_set[languages]

languages :: enum {
    english,
    german,
    japanese,
    chinese,
    dutch,
    greek,
    hindi,
    urdu,
    latin,
    sanskrit,
}

@(export)
special_polyglot: bit_set[languages;u64]
@(export)
another_special_polyglot: bit_set[languages;u64]

@(export)
very_polyglot: bit_set[languages;polyglot_int]
polyglot_int :: i32

@(export)
numbers: bit_set[enum {
    one,
    two,
    three,
}]

@(export)
underlying_numbers: bit_set[enum {
    four,
    five,
    six,
};i8]

@(export)
abc_bitset: bit_set['A' ..= 'Z']

@(export)
number_range: bit_set[2 ..< 5]

@(export)
boot_options: bit_set[booty.boots]

@(export)
foo_booties: bit_set[booty.boots;booty.boot_int]

// TODO: handle bit_sets with ranges that use constants
// TODO: handle bit_sets with ranges that use constants from other packages
//NUMBER_RANGE_MIN :: 0
//NUMBER_RANGE_MAX :: 10
//
//@(export)
//number_range: bit_set[NUMBER_RANGE_MIN..<NUMBER_RANGE_MAX]

