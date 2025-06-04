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
