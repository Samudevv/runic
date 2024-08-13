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

package cpp_codegen

import "core:testing"
import "root:runic"

@(test)
test_int_sizes :: proc(t: ^testing.T) {
    using testing

    is := int_sizes_from_platform({os = .Linux, arch = .x86_64})

    expect_value(t, is.char, 1)
    expect_value(t, is.short, 2)
    expect_value(t, is.Int, 4)
    expect_value(t, is.long, 8)
    expect_value(t, is.longlong, 8)
    expect_value(t, is.float, 4)
    expect_value(t, is.double, 8)
    expect_value(t, is.long_double, 16)
    expect_value(t, is._Bool, 1)
    expect_value(t, is.float_Complex, 8)
    expect_value(t, is.double_Complex, 16)
    expect_value(t, is.long_double_Complex, 32)

    expect_value(t, int_type(is.char, true), runic.Builtin.SInt8)
    expect_value(t, int_type(is.char, false), runic.Builtin.UInt8)
    expect_value(t, int_type(is.Int, true), runic.Builtin.SInt32)
    expect_value(t, int_type(is.Int, false), runic.Builtin.UInt32)
}
