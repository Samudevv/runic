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

package odin_codegen

import "core:os"
import "core:testing"
import ccdg "root:c/codegen"
import "root:diff"
import "root:runic"

@(test)
test_from_odin_codegen :: proc(t: ^testing.T) {
    using testing

    plats := [?]runic.Platform {
        {os = .Linux, arch = .x86_64},
        {os = .Windows, arch = .x86_64},
        {os = .Macos, arch = .arm64},
    }
    file_names := [?]string {
        "test_data/foozy/foozy.h",
        "test_data/foozy/foozy-windows.h",
        "test_data/foozy/foozy-macos.h",
    }

    rune_file, os_err := os.open("test_data/foozy/rune.yml")
    if !expect_value(t, os_err, nil) do return
    defer os.close(rune_file)

    rn, rn_err := runic.parse_rune(
        os.stream_from_handle(rune_file),
        "test_data/foozy/rune.yml",
    )
    if !expect_value(t, rn_err, nil) do return

    for plat, idx in plats {
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
            file_names[idx],
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if !expect_value(t, os_err, nil) do return
        defer os.close(out_file)

        runic.to_preprocess_runestone(&rs, rn.to.(runic.To), ccdg.C_RESERVED)

        ccdg_err := ccdg.generate_bindings(
            rs,
            rn.to.(runic.To),
            os.stream_from_handle(out_file),
        )
        if !expect_value(t, ccdg_err, nil) do return
    }

    diff.expect_diff_files(
        t,
        "test_data/foozy/foozy.expected.h",
        "test_data/foozy/foozy.h",
    )
    diff.expect_diff_files(
        t,
        "test_data/foozy/foozy-windows.expected.h",
        "test_data/foozy/foozy-windows.h",
    )
    diff.expect_diff_files(
        t,
        "test_data/foozy/foozy-macos.expected.h",
        "test_data/foozy/foozy-macos.h",
    )
}
