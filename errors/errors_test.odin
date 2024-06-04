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

package errors

import "core:encoding/json"
import "core:io"
import "core:strings"
import "core:testing"

@(test)
test_wrap :: proc(t: ^testing.T) {
    using testing

    err: union {
        io.Error,
        json.Error,
    }

    expect_value(t, wrap_union(err), nil)

    err = io.Error.Unknown

    expect(t, strings.has_prefix(wrap_union(err).?, "io.Error: Unknown"))
    expect(t, strings.has_prefix(wrap(io.Error.EOF).?, "io.Error: EOF"))
    expect(
        t,
        strings.has_prefix(
            wrap(json.Error.Illegal_Character).?,
            "json.Error: Illegal_Character",
        ),
    )

    expect(t, strings.has_prefix(wrap("Success").?, "Success"))
}

