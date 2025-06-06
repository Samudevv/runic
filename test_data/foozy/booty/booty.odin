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

package booty

import "hooty"

treasure :: struct {
    a:  f32,
    b:  f64,
    sh: hooty.shmooty,
}

boots :: enum i32 {
    long_ones,
    small_ones,
    wide_ones,
}

boot_int :: i32

large_array :: [dynamic]f32
small_array :: [dynamic]boot_int
large_slice :: []boot_int
small_slice :: []f64

large_union :: union {
    i64,
    u32,
    boot_int,
}

small_bit_set :: bit_set[boots]
large_bit_field :: bit_field u32 {}
