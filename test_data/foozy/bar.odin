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

import "base:runtime"
import "booty"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:strings"

int_ptr :: ^int
multi_int :: [10]int
multi_int_ptr :: ^[10]int
int_multi_ptr :: [10]^int
super_multi :: [10][20][30][40][50]^^f64
arr_ptr :: ^[14]int
complex_ptr :: ^^^[13][14]^[15]^[18]^^^[17]^^^int

typey_type :: []booty.treasure
type_typey :: []typeid
tüp_töp :: [dynamic]booty.treasure
töp_tüp :: [dynamic]typeid
mäybe :: Maybe(int)
möybe :: Maybe(struct {
        x: int,
        y: u128,
    })
müybe :: Maybe(booty.treasure)

bar_union :: union {
    int_ptr,
    multi_int,
    multi_int_ptr,
    int_multi_ptr,
    super_multi,
    arr_ptr,
    complex_ptr,
    booty.boots,
}

@(export)
bad_data: map[int]string

@(export)
good_data: map[enum {
    baked_beans,
    toast,
}]struct {
    x, y, z: f32,
}

@(export)
better_data: map[booty.boot_int]booty.treasure

@(export)
bar_value: booty.small_bit_set

@(export)
baz_value: booty.large_bit_field

@(export)
faz_value: booty.booties

@(export, link_name = "bar")
foozy_bar :: proc "c" (msg: cstring, result: int) -> cstring {
    context = runtime.default_context()

    text := print_result(msg, result)
    defer delete(text)

    rs := cast([^]u8)libc.malloc(len(text) + 1)
    for t, idx in text {
        rs[idx] = u8(t)
    }
    rs[len(text) - 1] = 0

    return cast(cstring)rs
}

@(export)
parse_int :: proc "c" (
    value: c.int64_t,
    v1: booty.large_slice,
    v2: booty.small_slice,
) -> cstring {
    context = runtime.default_context()
    str := fmt.aprint(value)
    return strings.clone_to_cstring(str)
}

@(export)
do_alloc :: proc "c" (ctx: booty.treasure, types: booty.large_union) {
    context = runtime.default_context()
    fmt.print(ctx)
}

print_result :: proc(msg: cstring, result: int) -> string {
    text := fmt.aprintf("{}: result={}", msg, result)
    return text
}

@(export)
process_orders :: proc "c" (orders: []i32, cb: booty.callback) -> bool {
    return false
}
