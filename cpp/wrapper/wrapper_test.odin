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
import "core:strings"
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
        in_headers          = {{{} = {in_header}}},
        out_header          = {{{} = out_header}},
        out_source          = {{{} = out_source}},
        from_compiler_flags = {{{} = true}},
        multi_platform      = true,
    }
    defer delete(rn.in_headers.d)
    defer delete(rn.out_header.d)
    defer delete(rn.out_source.d)
    defer delete(rn.from_compiler_flags.d)

    rf := runic.From {
        defines = {{{} = {"DYNA_FUNC" = "1"}}},
    }
    defer delete(rf.defines.d)
    defer delete(rf.defines.d[{}])

    err := generate_wrapper(
        rune_file_name,
        {{.Linux, .x86_64}, {.Windows, .x86_64}},
        rn,
        rf,
    )
    expect_value(t, err, nil)

    header_data_linux, linux_ok := os.read_entire_file(
        "test_data/wrapper_out_header-Linux_x86_64.h",
    )
    header_data_windows, windows_ok := os.read_entire_file(
        "test_data/wrapper_out_header-Windows_x86_64.h",
    )
    if !expect(t, linux_ok && windows_ok) do return
    defer delete(header_data_linux)
    defer delete(header_data_windows)

    source_data_linux, linux_src_ok := os.read_entire_file(
        "test_data/wrapper_out_source-Linux_x86_64.c",
    )
    source_data_windows, windows_src_ok := os.read_entire_file(
        "test_data/wrapper_out_source-Windows_x86_64.c",
    )
    if !expect(t, linux_src_ok && windows_src_ok) do return
    defer delete(source_data_linux)
    defer delete(source_data_windows)

    HEADER_EXPECTED :: `#pragma once

#include "wrapper_in_header.h"

extern void print_stuff_wrapper(int a, int b);
extern const float ** do_other_stuff_wrapper(float c, float ** d);
extern spelling_t alphabet_wrapper();
extern struct foo_t japanese_wrapper();
extern int dyna_func_wrapper(int a, int b);
`


    SOURCE_EXPECTED :: `#include "wrapper_out_header-%OS_ARCH%.h"

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


    source_expected_linux, _ := strings.replace(
        SOURCE_EXPECTED,
        "%OS_ARCH%",
        "Linux_x86_64",
        1,
    )
    source_expected_windows, _ := strings.replace(
        SOURCE_EXPECTED,
        "%OS_ARCH%",
        "Windows_x86_64",
        1,
    )
    defer delete(source_expected_linux)
    defer delete(source_expected_windows)


    if expect_value(t, len(string(header_data_linux)), len(HEADER_EXPECTED)) {
        expect_value(t, string(header_data_linux), HEADER_EXPECTED)
    }
    if expect_value(
        t,
        len(string(header_data_windows)),
        len(HEADER_EXPECTED),
    ) {
        expect_value(t, string(header_data_windows), HEADER_EXPECTED)
    }

    if expect_value(
        t,
        len(string(source_data_linux)),
        len(source_expected_linux),
    ) {
        expect_value(t, string(source_data_linux), source_expected_linux)
    }
    if expect_value(
        t,
        len(string(source_data_windows)),
        len(source_expected_windows),
    ) {
        expect_value(t, string(source_data_windows), source_expected_windows)
    }
}

