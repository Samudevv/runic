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
parse_int :: proc "c" (value: c.int64_t) -> cstring {
    context = runtime.default_context()
    str := fmt.aprint(value)
    return strings.clone_to_cstring(str)
}

@(export)
do_alloc :: proc "c" (ctx: booty.treasure) {
    context = runtime.default_context()
    fmt.print(ctx)
}

print_result :: proc(msg: cstring, result: int) -> string {
    text := fmt.aprintf("{}: result={}", msg, result)
    return text
}
