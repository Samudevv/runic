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

// +build linux, darwin
package odin_codegen

import "core:os"
import "core:strings"
import "core:testing"
import ccdg "root:c/codegen"
import "root:runic"

@(test)
test_from_odin_codegen :: proc(t: ^testing.T) {
    using testing

    plat := runic.platform_from_host()

    rune_file, os_err := os.open("test_data/foozy/rune.yml")
    if !expect_value(t, os_err, nil) do return
    defer os.close(rune_file)

    rn, rn_err := runic.parse_rune(
        os.stream_from_handle(rune_file),
        "test_data/foozy/rune.yml",
    )
    if !expect_value(t, rn_err, nil) do return

    rs, rs_err := generate_runestone(
        plat,
        "test_data/foozy/rune.yml",
        rn.from.(runic.From),
    )
    if !expect_value(t, rs_err, nil) do return
    defer runic.runestone_destroy(&rs)
    runic.from_postprocess_runestone(&rs, rn.from.(runic.From))

    out_file: os.Handle = ---
    out_file, os_err = os.open(
        "test_data/foozy/foozy.h",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return
    defer os.close(out_file)

    runic.to_preprocess_runestone(&rs, rn.to.(runic.To), ccdg.C_RESERVED)

    ccdg_err := ccdg.generate_bindings(
        plat,
        rs,
        rn.to.(runic.To),
        os.stream_from_handle(out_file),
    )
    if !expect_value(t, ccdg_err, nil) do return

    real_data, expected_data: []u8 = ---, ---
    ok: bool = ---

    real_data, ok = os.read_entire_file("test_data/foozy/foozy.h")
    if !expect(t, ok) do return
    defer delete(real_data)
    expected_data, ok = os.read_entire_file("test_data/foozy/foozy.expected.h")
    if !expect(t, ok) do return
    defer delete(expected_data)

    real_string, _ := strings.replace(string(real_data), "\r", "", -1)
    expected_string, _ := strings.replace(string(expected_data), "\r", "", -1)

    expect_value(t, len(real_string), len(expected_string))
    expect_value(t, real_string, expected_string)
}

