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

package ordered_map

import "core:testing"

@(test)
test_ordered_map :: proc(t: ^testing.T) {
    using testing

    omap := make(string, f32)

    insert(&omap, "1", 0)
    insert(&omap, "5", 4)
    insert(&omap, "8", 6)
    insert(&omap, "3", 9)

    for entry, idx in omap.data {
        key, value := entry.key, entry.value

        switch idx {
        case 0:
            expect_value(t, key, "1")
            expect_value(t, value, 0)
        case 1:
            expect_value(t, key, "5")
            expect_value(t, value, 4)
        case 2:
            expect_value(t, key, "8")
            expect_value(t, value, 6)
        case 3:
            expect_value(t, key, "3")
            expect_value(t, value, 9)
        case:
            fail(t)
        }
    }

    delete_key(&omap, "8")

    for entry, idx in omap.data {
        key, value := entry.key, entry.value

        switch idx {
        case 0:
            expect_value(t, key, "1")
            expect_value(t, value, 0)
        case 1:
            expect_value(t, key, "5")
            expect_value(t, value, 4)
        case 2:
            expect_value(t, key, "3")
            expect_value(t, value, 9)
        case:
            fail(t)
        }
    }
}
