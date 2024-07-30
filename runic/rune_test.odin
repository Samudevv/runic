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

import "core:os"
import "core:testing"

@(test)
test_rune :: proc(t: ^testing.T) {
    using testing

    file, os_err := os.open("test_data/rune.yml")
    if !expect_value(t, os_err, 0) do return
    defer os.close(file)

    rn, err := parse_rune(os.stream_from_handle(file), "test_data/rune.yml")
    defer rune_destroy(&rn)
    if !expect_value(t, err, nil) do return

    expect_value(t, rn.version, 0)

    expect_value(t, rn.from.(From).language, "c")
    expect_value(t, len(rn.platforms), 2)
    expect_value(t, rn.platforms[0].os, OS.Linux)
    expect_value(t, rn.platforms[1].os, OS.Windows)
    expect_value(t, rn.platforms[0].arch, Architecture.x86_64)
    expect_value(t, rn.platforms[1].arch, Architecture.x86_64)

    f := rn.from.(From)
    expect_value(t, f.shared.d[Platform{.Any, .Any}], "libfoo.so")
    expect_value(t, len(f.headers.d[Platform{.Any, .Any}]), 3)
    expect_value(t, len(f.headers.d[Platform{.Macos, .Any}]), 1)
    expect_value(t, len(f.overwrite.d[Platform{.Any, .Any}].types), 1)

    to := rn.to.(To)
    expect_value(t, to.static_switch, "FOO_STATIC")
}
