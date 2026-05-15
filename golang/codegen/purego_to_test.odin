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
package golang_codegen

import "core:os"
import "core:strings"
import "core:testing"
import "root:diff"
import "root:errors"
import "root:runic"

@(test)
test_purego_golang_to :: proc(t: ^testing.T) {
    errors.init()
    defer errors.destroy()

    LINUX_RUNESTONE :: `
version = 0

os = Linux
arch = x86_64

[lib]
static = libfoo.a
shared = libfoo.so

[constants]
MAX_ARRAY_SIZE = 4096 #Untyped
MAX_ARRAY_CAP = 4096 #Untyped

[types]
my_size_type = #UInt64
Window = #Struct name #String width #UInt32 height #UInt32
Array = #Struct len my_size_type cap my_size_type els #UInt32 #Attr Ptr 1 #AttrEnd

[extern]
FILE = "stdinc/stdio.h" #SInt32

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.get_window_handle = #Extern FILE #Attr Ptr 1 #AttrEnd window Window #Attr Ptr 1 #AttrEnd
func.create_array = Array size my_size_type
func.array_append = Array arr Array #Attr Ptr 1 #AttrEnd value #UInt32

var.linux_globals = Array

`

    WINDOWS_RUNESTONE :: `
version = 0

os = Windows
arch = x86_64

[lib]
static = foo.lib
shared = foo.dll

[constants]
MAX_ARRAY_SIZE = 4096 #Untyped
MAX_ARRAY_CAP = 4096 #Untyped

[types]
my_size_type = #UInt64
Window = #Struct name #String width #UInt32 height #UInt32
WindowWin32 = #Struct name #String width #UInt32 height #UInt32 win32Id #UIntX
Array = #Struct len my_size_type cap my_size_type els #UInt32 #Attr Ptr 1 #AttrEnd

[extern]
FILE = "stdinc/stdio.h" #SInt32

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.create_window_win32 = WindowWin32 #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.get_window_handle = #Extern FILE #Attr Ptr 1 #AttrEnd window Window #Attr Ptr 1 #AttrEnd
func.create_array = Array size my_size_type
func.array_append = Array arr Array #Attr Ptr 1 #AttrEnd value #UInt32

var.windows_globals = Array

`

    when ODIN_OS == .Windows {
        RUNE_FILE_NAME :: "test_data\\rune.yml"
    } else {
        RUNE_FILE_NAME :: "test_data/rune.yml"
    }

    extern_sources := make(map[string]string)
    extern_remaps := make(map[string]string)
    defer delete(extern_sources)
    defer delete(extern_remaps)

    extern_sources["stdinc/stdio.h"] = "operatingsystem os"
    extern_remaps["FILE"] = "Handle"

    rn := runic.To {
        language = "golang",
        package_name = "greatwave",
        purego = true,
        out = "test_data/to_purego_golang_test.go",
        extern = {sources = extern_sources, remaps = extern_remaps},
    }

    linux_rd, windows_rd: strings.Reader
    linux_rs, windows_rs: runic.Runestone = ---, ---
    rs_err: errors.Error = ---

    strings.reader_init(&linux_rd, string(LINUX_RUNESTONE))
    strings.reader_init(&windows_rd, string(WINDOWS_RUNESTONE))

    linux_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&linux_rd),
        "/linux",
    )
    if !testing.expect_value(t, rs_err, nil) do return
    windows_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&windows_rd),
        "/windows",
    )
    if !testing.expect_value(t, rs_err, nil) do return

    defer runic.runestone_destroy(&linux_rs)
    defer runic.runestone_destroy(&windows_rs)

    runic.to_preprocess_runestone(&linux_rs, rn, GO_RESERVED)
    runic.to_preprocess_runestone(&windows_rs, rn, GO_RESERVED)

    runestones := []runic.Runestone{linux_rs, windows_rs}
    file_paths := []string{"/linux", "/windows"}

    rc, rc_err := runic.cross_the_runes(file_paths, runestones)
    if !testing.expect_value(t, rc_err, nil) do return
    defer runic.runecross_destroy(&rc)

    out_file, os_err := os.open(
        "test_data/to_purego_golang_test.go",
        os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
        os.perm(0o644),
    )
    if !testing.expect_value(t, os_err, nil) do return
    defer os.close(out_file)

    err := generate_bindings(rc, rn, RUNE_FILE_NAME, os.to_stream(out_file))
    if !testing.expect_value(t, err, nil) do return

    data, data_err := os.read_entire_file(
        "test_data/to_purego_golang_test.go",
        context.allocator,
    )
    if !testing.expect_value(t, data_err, nil) do return
    defer delete(data)

    EXPECTED_SOURCE :: `package greatwave

func BananaIsMyFan() {
}
`

    diff.expect_diff_strings(t, EXPECTED_SOURCE, string(data))
}
