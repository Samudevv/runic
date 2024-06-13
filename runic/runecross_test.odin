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


LINUX_RUNESTONE :: `
version = 0

os = Linux
arch = x86_64

[lib]
shared = liblinux.so

[types]
BigInt = #SInt64

[symbols]
func.write_out = #Void data #RawPtr num #UInt64
func.say_hello = #Void
func.multiply = #Void value BigInt
`

WINDOWS_RUNESTONE :: `
version = 0

os = Windows
arch = x86_64

[lib]
shared = windows.lib

[types]
BigInt = #SInt32

[symbols]
func.write_out = #Void data #RawPtr
func.say_hello = #Void
func.multiply = #Void value BigInt
`

@(test)
test_runecross :: proc(t: ^testing.T) {
    using testing

    linux_rd, windows_rd: strings.Reader
    strings.reader_init(&linux_rd, LINUX_RUNESTONE)
    strings.reader_init(&windows_rd, WINDOWS_RUNESTONE)

    linux_stone, linux_err := parse_runestone(
        strings.reader_to_stream(&linux_rd),
        "/linux",
    )
    if !expect_value(t, linux_err, nil) do return
    windows_stone, windows_err := parse_runestone(
        strings.reader_to_stream(&windows_rd),
        "/windows",
    )
    if !expect_value(t, windows_err, nil) do return

    cross, cross_err := cross_the_runes({linux_stone, windows_stone})
    if !expect_value(t, cross_err, nil) do return

    expect_value(t, om.length(cross.general.types), 0)
    expect_value(t, om.length(cross.general.symbols), 2)

    linux_cross := cross.cross[Platform{.Linux, .x86_64}]
    expect_value(t, om.length(linux_cross.types), 1)
    expect_value(t, om.length(linux_cross.symbols), 1)

    windows_cross := cross.cross[Platform{.Windows, .x86_64}]
    expect_value(t, om.length(windows_cross.types), 1)
    expect_value(t, om.length(windows_cross.symbols), 1)
}
