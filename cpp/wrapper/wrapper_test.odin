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

package cpp_wrapper

import "core:os"
import "core:path/filepath"
import "core:testing"
import "root:runic"

@(test)
test_cpp_wrapper :: proc(t: ^testing.T) {
    using testing

    cwd := os.get_current_directory()
    defer delete(cwd)

    rune_file_name := filepath.join({cwd, "test_data/wrapper_rune.yml"})
    in_header := filepath.join({cwd, "test_data/wrapper_in_header.h"})
    out_header := filepath.join({cwd, "test_data/wrapper_out_header.h"})
    out_source := filepath.join({cwd, "test_data/wrapper_out_source.c"})
    defer delete(rune_file_name)
    defer delete(in_header)
    defer delete(out_header)
    defer delete(out_source)

    rn := runic.Wrapper {
        language            = "c",
        in_headers          = {in_header},
        out_header          = out_header,
        out_source          = out_source,
        from_compiler_flags = true,
    }

    rf := runic.From {
        defines = {{{} = {"DYNA_FUNC" = "1"}}},
    }
    defer delete(rf.defines.d)
    defer delete(rf.defines.d[{}])

    err := generate_wrapper(rune_file_name, rn, rf)
    expect_value(t, err, nil)

    header_data, header_ok := os.read_entire_file(
        "test_data/wrapper_out_header.h",
    )
    if !expect(t, header_ok) do return
    defer delete(header_data)
    source_data, source_ok := os.read_entire_file(
        "test_data/wrapper_out_source.c",
    )
    if !expect(t, source_ok) do return
    defer delete(source_data)

    HEADER_EXPECTED :: `#pragma once

#include "wrapper_in_header.h"

extern void print_stuff_wrapper(int a, int b);
extern const float ** do_other_stuff_wrapper(float c, float ** d);
extern spelling_t alphabet_wrapper();
extern struct foo_t japanese_wrapper();
extern int dyna_func_wrapper(int a, int b);
`


    SOURCE_EXPECTED :: `#include "wrapper_out_header.h"

void print_stuff_wrapper(int a, int b) {
    print_stuff(a, b);
}

const float ** do_other_stuff_wrapper(float c, float ** d) {
    return do_other_stuff(c, d);
}

spelling_t alphabet_wrapper() {
    return alphabet();
}

struct foo_t japanese_wrapper() {
    return japanese();
}

int dyna_func_wrapper(int a, int b) {
    return dyna_func(a, b);
}

`


    if expect_value(t, len(string(header_data)), len(HEADER_EXPECTED)) {
        expect_value(t, string(header_data), HEADER_EXPECTED)
    }

    if expect_value(t, len(string(source_data)), len(SOURCE_EXPECTED)) {
        expect_value(t, string(source_data), SOURCE_EXPECTED)
    }
}

