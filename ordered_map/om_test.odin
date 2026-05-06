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
    omap := make(string, f32)
    defer delete(omap)

    insert(&omap, "1", 0)
    insert(&omap, "5", 4)
    insert(&omap, "8", 6)
    insert(&omap, "3", 9)

    for entry, idx in omap.data {
        key, value := entry.key, entry.value

        switch idx {
        case 0:
            testing.expect_value(t, key, "1")
            testing.expect_value(t, value, 0)
        case 1:
            testing.expect_value(t, key, "5")
            testing.expect_value(t, value, 4)
        case 2:
            testing.expect_value(t, key, "8")
            testing.expect_value(t, value, 6)
        case 3:
            testing.expect_value(t, key, "3")
            testing.expect_value(t, value, 9)
        case:
            testing.fail(t)
        }
    }

    delete_key(&omap, "8")

    for entry, idx in omap.data {
        key, value := entry.key, entry.value

        switch idx {
        case 0:
            testing.expect_value(t, key, "1")
            testing.expect_value(t, value, 0)
        case 1:
            testing.expect_value(t, key, "5")
            testing.expect_value(t, value, 4)
        case 2:
            testing.expect_value(t, key, "3")
            testing.expect_value(t, value, 9)
        case:
            testing.fail(t)
        }
    }
}

@(test)
test_ordered_map_move :: proc(t: ^testing.T) {
    omap := make(string, f32)
    defer delete(omap)

    insert(&omap, "apple", 0)
    insert(&omap, "pear", 4)
    insert(&omap, "fruit", 6)
    insert(&omap, "kiwi", 5)
    insert(&omap, "banana", 10)
    insert(&omap, "pineapple", 11)
    insert(&omap, "strawberry", 12)

    move(&omap, "apple", 1)

    testing.expect_value(t, omap.data[0].key, "pear")
    testing.expect_value(t, omap.data[1].key, "apple")
    testing.expect_value(t, omap.data[2].key, "fruit")
    testing.expect_value(t, omap.data[3].key, "kiwi")
    testing.expect_value(t, omap.data[0].value, 4)
    testing.expect_value(t, omap.data[1].value, 0)
    testing.expect_value(t, omap.data[2].value, 6)
    testing.expect_value(t, omap.data[3].value, 5)
    testing.expect_value(t, omap.indices["pear"], 0)
    testing.expect_value(t, omap.indices["apple"], 1)
    testing.expect_value(t, omap.indices["fruit"], 2)
    testing.expect_value(t, omap.indices["kiwi"], 3)

    move(&omap, "strawberry", 3)

    testing.expect_value(t, omap.data[0].key, "pear")
    testing.expect_value(t, omap.data[1].key, "apple")
    testing.expect_value(t, omap.data[2].key, "fruit")
    testing.expect_value(t, omap.data[3].key, "strawberry")
    testing.expect_value(t, omap.data[4].key, "kiwi")
    testing.expect_value(t, omap.data[5].key, "banana")
    testing.expect_value(t, omap.data[6].key, "pineapple")
    testing.expect_value(t, omap.data[0].value, 4)
    testing.expect_value(t, omap.data[1].value, 0)
    testing.expect_value(t, omap.data[2].value, 6)
    testing.expect_value(t, omap.data[3].value, 12)
    testing.expect_value(t, omap.data[4].value, 5)
    testing.expect_value(t, omap.data[5].value, 10)
    testing.expect_value(t, omap.data[6].value, 11)
    testing.expect_value(t, omap.indices["pear"], 0)
    testing.expect_value(t, omap.indices["apple"], 1)
    testing.expect_value(t, omap.indices["fruit"], 2)
    testing.expect_value(t, omap.indices["strawberry"], 3)
    testing.expect_value(t, omap.indices["kiwi"], 4)
    testing.expect_value(t, omap.indices["banana"], 5)
    testing.expect_value(t, omap.indices["pineapple"], 6)

    move(&omap, "banana", 0)

    testing.expect_value(t, omap.data[0].key, "banana")
    testing.expect_value(t, omap.data[1].key, "pear")
    testing.expect_value(t, omap.data[2].key, "apple")
    testing.expect_value(t, omap.data[3].key, "fruit")
    testing.expect_value(t, omap.data[4].key, "strawberry")
    testing.expect_value(t, omap.data[5].key, "kiwi")
    testing.expect_value(t, omap.data[6].key, "pineapple")
    testing.expect_value(t, omap.data[0].value, 10)
    testing.expect_value(t, omap.data[1].value, 4)
    testing.expect_value(t, omap.data[2].value, 0)
    testing.expect_value(t, omap.data[3].value, 6)
    testing.expect_value(t, omap.data[4].value, 12)
    testing.expect_value(t, omap.data[5].value, 5)
    testing.expect_value(t, omap.data[6].value, 11)
    testing.expect_value(t, omap.indices["banana"], 0)
    testing.expect_value(t, omap.indices["pear"], 1)
    testing.expect_value(t, omap.indices["apple"], 2)
    testing.expect_value(t, omap.indices["fruit"], 3)
    testing.expect_value(t, omap.indices["strawberry"], 4)
    testing.expect_value(t, omap.indices["kiwi"], 5)
    testing.expect_value(t, omap.indices["pineapple"], 6)

    move(&omap, "kiwi", 6)

    testing.expect_value(t, omap.data[0].key, "banana")
    testing.expect_value(t, omap.data[1].key, "pear")
    testing.expect_value(t, omap.data[2].key, "apple")
    testing.expect_value(t, omap.data[3].key, "fruit")
    testing.expect_value(t, omap.data[4].key, "strawberry")
    testing.expect_value(t, omap.data[5].key, "pineapple")
    testing.expect_value(t, omap.data[6].key, "kiwi")
    testing.expect_value(t, omap.data[0].value, 10)
    testing.expect_value(t, omap.data[1].value, 4)
    testing.expect_value(t, omap.data[2].value, 0)
    testing.expect_value(t, omap.data[3].value, 6)
    testing.expect_value(t, omap.data[4].value, 12)
    testing.expect_value(t, omap.data[5].value, 11)
    testing.expect_value(t, omap.data[6].value, 5)
    testing.expect_value(t, omap.indices["banana"], 0)
    testing.expect_value(t, omap.indices["pear"], 1)
    testing.expect_value(t, omap.indices["apple"], 2)
    testing.expect_value(t, omap.indices["fruit"], 3)
    testing.expect_value(t, omap.indices["strawberry"], 4)
    testing.expect_value(t, omap.indices["pineapple"], 5)
    testing.expect_value(t, omap.indices["kiwi"], 6)
}

