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

import "core:slice"
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
func.c = #Untyped a #String b #String #Attr Arr 5 #AttrEnd
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
func.c = #Untyped a #String b #String #Attr Arr 4 #AttrEnd
`

@(test)
test_is_same :: proc(t: ^testing.T) {
    using testing

    rd1, rd2: strings.Reader
    strings.reader_init(&rd1, SAME_RUNESTONE1)
    strings.reader_init(&rd2, SAME_RUNESTONE2)

    rs1, rs1_err := parse_runestone(strings.reader_to_stream(&rd1), "/rd1")
    if !expect_value(t, rs1_err, nil) do return
    defer runestone_destroy(&rs1)

    rs2, rs2_err := parse_runestone(strings.reader_to_stream(&rd2), "/rd2")
    if !expect_value(t, rs2_err, nil) do return
    defer runestone_destroy(&rs2)

    expect(t, rs1.lib.static != rs2.lib.static)

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
PFNGLDELETEARRAYSETSEXTPROC = #FuncPtr #Untyped n GLsizei arrayset #RawPtr #Attr ReadOnly Arr 0 #AttrEnd
PFNGLWINDOWRECTANGLESEXTPROC = #FuncPtr #Untyped mode GLenum count GLsizei box GLint #Attr ReadOnly Arr 0 #AttrEnd
PFNGLPROGRAMNAMEDPARAMETER4DVNVPROC = #FuncPtr #Untyped id GLuint len GLsizei name GLubyte #Attr ReadOnly Ptr 1 #AttrEnd v GLdouble #Attr ReadOnly Arr 0 #AttrEnd
PFNGLPROGRAMNAMEDPARAMETER4FVNVPROC = #FuncPtr #Untyped id GLuint len GLsizei name GLubyte #Attr ReadOnly Ptr 1 #AttrEnd v GLfloat #Attr ReadOnly Arr 0 #AttrEnd
PFNGLWEIGHTPATHSNVPROC = #FuncPtr #Untyped resultPath GLuint numPaths GLsizei paths GLuint #Attr ReadOnly Arr 0 #AttrEnd weights GLfloat #Attr ReadOnly Arr 0 #AttrEnd
PFNGLGETINTEGERUI64I_VNVPROC = #FuncPtr #Untyped value GLenum index GLuint result GLuint64EXT #Attr Arr 0 #AttrEnd

[symbols]
func.write_out = #Untyped data #RawPtr num #UInt64
func.say_hello = #Untyped
func.multiply = #Untyped value BigInt
`

WINDOWS_RUNESTONE :: `
version = 0

os = Windows
arch = x86_64

[lib]
shared = windows.lib

[types]
BigInt = #SInt32
PFNGLDELETEARRAYSETSEXTPROC = #FuncPtr #Untyped n GLsizei arrayset #RawPtr #Attr ReadOnly Arr 0 #AttrEnd
PFNGLWINDOWRECTANGLESEXTPROC = #FuncPtr #Untyped mode GLenum count GLsizei box GLint #Attr ReadOnly Arr 0 #AttrEnd
PFNGLPROGRAMNAMEDPARAMETER4DVNVPROC = #FuncPtr #Untyped id GLuint len GLsizei name GLubyte #Attr ReadOnly Ptr 1 #AttrEnd v GLdouble #Attr ReadOnly Arr 0 #AttrEnd
PFNGLPROGRAMNAMEDPARAMETER4FVNVPROC = #FuncPtr #Untyped id GLuint len GLsizei name GLubyte #Attr ReadOnly Ptr 1 #AttrEnd v GLfloat #Attr ReadOnly Arr 0 #AttrEnd
PFNGLWEIGHTPATHSNVPROC = #FuncPtr #Untyped resultPath GLuint numPaths GLsizei paths GLuint #Attr ReadOnly Arr 0 #AttrEnd weights GLfloat #Attr ReadOnly Arr 0 #AttrEnd
PFNGLGETINTEGERUI64I_VNVPROC = #FuncPtr #Untyped value GLenum index GLuint result GLuint64EXT #Attr Arr 0 #AttrEnd

[symbols]
func.write_out = #Untyped data #RawPtr
func.say_hello = #Untyped
func.multiply = #Untyped value BigInt
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
    defer runestone_destroy(&linux_stone)

    windows_stone, windows_err := parse_runestone(
        strings.reader_to_stream(&windows_rd),
        "/windows",
    )
    if !expect_value(t, windows_err, nil) do return
    defer runestone_destroy(&windows_stone)

    cross, cross_err := cross_the_runes(
        {"/linux", "/windows"},
        {linux_stone, windows_stone},
    )
    if !expect_value(t, cross_err, nil) do return
    defer runecross_destroy(&cross)

    general := &cross.cross[0]

    expect_value(t, len(general.plats), 1)
    expect_value(t, general.plats[0].os, OS.Any)
    expect_value(t, general.plats[0].arch, Architecture.Any)

    expect_value(t, om.length(general.types), 6)
    expect_value(t, om.length(general.symbols), 2)

    linux_cross_idx, found := slice.linear_search_proc(
        cross.cross[:],
        proc(value: PlatformRunestone) -> bool {
            return slice.contains(value.plats[:], Platform{.Linux, .Any})
        },
    )
    if !expect(t, found) do return

    linux_cross := cross.cross[linux_cross_idx]
    expect_value(t, om.length(linux_cross.types), 1)
    expect_value(t, om.length(linux_cross.symbols), 1)

    windows_cross_idx, found_win := slice.linear_search_proc(
        cross.cross[:],
        proc(value: PlatformRunestone) -> bool {
            return slice.contains(value.plats[:], Platform{.Windows, .Any})
        },
    )
    if !expect(t, found_win) do return

    windows_cross := cross.cross[windows_cross_idx]
    expect_value(t, om.length(windows_cross.types), 1)
    expect_value(t, om.length(windows_cross.symbols), 1)
}

