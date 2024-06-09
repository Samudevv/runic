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

    file, os_err := os.open("test_data/rune.json")
    if !expect_value(t, os_err, 0) do return
    defer os.close(file)

    rn, err := parse_rune(os.stream_from_handle(file))
    defer rune_destroy(&rn)
    if !expect_value(t, err, nil) do return

    expect_value(t, rn.version, 0)

    expect_value(t, rn.from.(From).language, "c")

    f := rn.from.(From)
    expect_value(t, f.shared, "libfoo.so")
    expect_value(t, len(f.headers), 3)
    expect_value(t, len(f.headers_macos), 1)
    expect_value(t, f.preprocessor.(string), "gcc")

    to := rn.to.(To)
    expect_value(t, to.static_switch, "FOO_STATIC")
}
