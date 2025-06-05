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

package diff

import "base:runtime"
import "core:testing"

@(test)
test_diff :: proc(t: ^testing.T) {
    using testing

    internal_T: testing.T

    rs: bool
    {
        context.logger = runtime.default_logger()
        rs = expect_diff_files(
            &internal_T,
            "test_data/diff_old.c",
            "test_data/diff_new.c",
        )
    }

    expect_value(t, rs, false)

    {
        OLD_TEXT :: `#pragma once

#include <stdio.h>

static void hello_world() { printf("Hello World\n"); }

`

        NEW_TEXT :: `#pragma once

#include <stdio.h>

static void hello_world() { printf("こんにちは世界！"); }

`

        context.logger = runtime.default_logger()

        rs = expect_diff_strings(t, OLD_TEXT, NEW_TEXT, ".c")
    }

    expect_value(t, rs, false)
}
