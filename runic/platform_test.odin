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

import "core:testing"

@(test)
test_minimize_platforms :: proc(t: ^testing.T) {
    using testing

    {
        rune_platforms := []Platform {
            {.Windows, .x86_64},
            {.Linux, .x86_64},
            {.Macos, .x86_64},
            {.Windows, .arm64},
            {.Linux, .arm64},
            {.Macos, .arm64},
            {.Windows, .x86},
            {.Linux, .x86},
            {.Macos, .x86},
            {.Windows, .arm32},
            {.Linux, .arm32},
            {.Macos, .arm32},
        }
        plats := minimize_platforms(
            rune_platforms = rune_platforms,
            stone_plats = {
                {.Windows, .x86_64},
                {.Linux, .x86_64},
                {.Macos, .x86_64},
                {.Windows, .arm64},
                {.Linux, .arm64},
                {.Macos, .arm64},
            },
            ignore_arch = false,
        )

        expect_value(t, len(plats), 2)
        expect_value(t, plats[0].os, OS.Any)
        expect_value(t, plats[0].arch, Architecture.x86_64)
        expect_value(t, plats[1].os, OS.Any)
        expect_value(t, plats[1].arch, Architecture.arm64)

        delete(plats)

        plats = minimize_platforms(
            rune_platforms = rune_platforms,
            stone_plats = {
                {.Windows, .x86_64},
                {.Windows, .arm64},
                {.Windows, .x86},
                {.Windows, .arm32},
                {.Macos, .x86_64},
                {.Macos, .arm64},
                {.Macos, .x86},
                {.Macos, .arm32},
            },
            ignore_arch = false,
        )

        expect_value(t, len(plats), 2)
        expect_value(t, plats[0].os, OS.Windows)
        expect_value(t, plats[0].arch, Architecture.Any)
        expect_value(t, plats[1].os, OS.Macos)
        expect_value(t, plats[1].arch, Architecture.Any)

        delete(plats)
    }
}

