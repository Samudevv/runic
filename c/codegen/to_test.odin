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

package c_codegen

import "core:os"
import "core:strings"
import "core:testing"
import "root:errors"
import "root:runic"

@(test)
test_c_to :: proc(t: ^testing.T) {
    using testing

    LINUX_RUNESTONE :: `
version = 0

os = Linux
arch = x86_64

[lib]
static = libfoo.a

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32


`
    WINDOWS_RUNESTONE :: `
version = 0

os = Windows
arch = x86_64

[lib]
static = foo.lib

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32

`
    MACOS_RUNESTONE :: `
version = 0

os = Macos
arch = arm64

[lib]
static = libfoo.a

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32

`

    rn := runic.To {
        language = "c",
    }

    linux_rd, windows_rd, macos_rd: strings.Reader
    linux_rs, windows_rs, macos_rs: runic.Runestone = ---, ---, ---
    rs_err: errors.Error = ---

    strings.reader_init(&linux_rd, string(LINUX_RUNESTONE))
    strings.reader_init(&windows_rd, string(WINDOWS_RUNESTONE))
    strings.reader_init(&macos_rd, string(MACOS_RUNESTONE))

    linux_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&linux_rd),
        "/linux",
    )
    if !expect_value(t, rs_err, nil) do return

    windows_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&windows_rd),
        "/windows",
    )
    if !expect_value(t, rs_err, nil) do return

    macos_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&macos_rd),
        "/macos",
    )
    if !expect_value(t, rs_err, nil) do return

    runic.to_preprocess_runestone(&linux_rs, rn, C_RESERVED)
    runic.to_preprocess_runestone(&windows_rs, rn, C_RESERVED)
    runic.to_preprocess_runestone(&macos_rs, rn, C_RESERVED)

    runestones := []runic.Runestone{linux_rs, windows_rs, macos_rs}
    file_paths := []string{"/linux", "/windows", "/macos"}

    rc, rc_err := runic.cross_the_runes(file_paths, runestones)
    if !expect_value(t, rc_err, nil) do return
    defer runic.runecross_destroy(&rc)

    out_file, os_err := os.open(
        "test_data/to_c_test.h",
        os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return
    defer os.close(out_file)

    err := generate_bindings(rc, rn, os.stream_from_handle(out_file))
    if !expect_value(t, err, nil) do return

    data, os_ok := os.read_entire_file("test_data/to_c_test.h")
    if !expect(t, os_ok) do return
    defer delete(data)

    EXPECTED_HEADER :: `#pragma once

#include <stddef.h>
#include <stdint.h>

#if 1

extern Window* create_window(char* name, uint32_t width, uint32_t height);

#endif
#if ((defined(_WIN32) || defined(_WIN16) || defined(_WIN64)) && (defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64)))

#endif
#if ((defined(__linux__) || defined(__linux) || defined(linux)) && (defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64))) || (defined(__APPLE__) && (defined(macintosh) || defined(Macintosh) || defined(__MACH__)) && defined(__arm__) && defined(__aarch64__))

#endif
`

    expect_value(t, len(string(data)), len(EXPECTED_HEADER))
    expect_value(t, string(data), EXPECTED_HEADER)
}

