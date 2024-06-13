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

import "core:strings"
import "core:testing"
import om "root:ordered_map"

SAME_RUNESTONE1 :: `
version = 0

os = Linux
arch = x86_64

[lib]
static = libsame1.a

[symbols]
var.a = #SInt32
var.b = #Struct x type1 y #UInt8 #Attr Ptr 1 #AttrEnd
func.c = #Void a #String b #String #Attr Arr 5 #AttrEnd
`

SAME_RUNESTONE2 :: `
version = 0

os = Linux
arch = x86_64

[lib]
static = libsame2.a

[symbols]
var.a = #SInt32
var.b = #Struct x type1 y #UInt8 #Attr Ptr 1 #AttrEnd
func.c = #Void a #String b #String #Attr Arr 4 #AttrEnd
`

@(test)
test_is_same :: proc(t: ^testing.T) {
    using testing

    rd1, rd2: strings.Reader
    strings.reader_init(&rd1, SAME_RUNESTONE1)
    strings.reader_init(&rd2, SAME_RUNESTONE2)

    rs1, rs1_err := parse_runestone(strings.reader_to_stream(&rd1), "/rd1")
    if !expect_value(t, rs1_err, nil) do return
    rs2, rs2_err := parse_runestone(strings.reader_to_stream(&rd2), "/rd2")
    if !expect_value(t, rs2_err, nil) do return

    expect(t, rs1.lib_static != rs2.lib_static)

    expect(t, is_same(om.get(rs1.symbols, "a"), om.get(rs2.symbols, "a")))
    expect(t, is_same(om.get(rs1.symbols, "b"), om.get(rs2.symbols, "b")))
    expect(t, !is_same(om.get(rs1.symbols, "a"), om.get(rs2.symbols, "b")))
    expect(t, !is_same(om.get(rs1.symbols, "c"), om.get(rs2.symbols, "c")))
}
