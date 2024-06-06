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

package c_codegen

import "../../runic"
import "core:io"
import "core:os"
import "core:testing"

@(test)
test_c_generate_runestone :: proc(t: ^testing.T) {
    using testing

    plat := runic.platform_from_host()

    from := runic.From {
        shared         = "libtest_data.so",
        shared_windows = "test_data.dll",
        headers        =  {
            "test_data/array.h",
            "test_data/builtin.h",
            "test_data/enum.h",
            "test_data/function.h",
            "test_data/function_pointer.h",
            "test_data/gnu_attribute.h",
            "test_data/include.h",
            "test_data/macros.h",
            "test_data/pointer.h",
        },
    }

    to := runic.To{}

    rs, rs_err := generate_runestone(plat, "./stdin", from)
    defer runic.runestone_destroy(&rs)
    if !expect_value(t, rs_err, nil) do return

    file, os_err := os.open(
        "test_data/generate_runestone.ini",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, 0) do return
    defer os.close(file)

    io_err := runic.write_runestone(rs, os.stream_from_handle(file))
    if !expect_value(t, io_err, io.Error.None) do return

    binds: os.Handle = ---
    binds, os_err = os.open(
        "test_data/bindings.h",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, 0) do return
    defer os.close(binds)

    e_err := generate_bindings(plat, rs, to, os.stream_from_handle(binds))
    if !expect_value(t, e_err, nil) do return
}

when ODIN_OS == .Linux {
    @(test)
    test_int_sizes :: proc(t: ^testing.T) {
        using testing

        is, err := int_sizes()
        if !expect_value(t, err, nil) do return

        expect_value(t, is.char, 1)
        expect_value(t, is.short, 2)
        expect_value(t, is.Int, 4)
        expect_value(t, is.long, 8)
        expect_value(t, is.longlong, 8)
        expect_value(t, is.float, 4)
        expect_value(t, is.double, 8)
        expect_value(t, is.long_double, 16)
        expect_value(t, is._Bool, 1)
        expect_value(t, is.float_Complex, 8)
        expect_value(t, is.double_Complex, 16)
        expect_value(t, is.long_double_Complex, 32)

        expect_value(t, int_type(is.char, true), runic.Builtin.SInt8)
        expect_value(t, int_type(is.char, false), runic.Builtin.UInt8)
        expect_value(t, int_type(is.Int, true), runic.Builtin.SInt32)
        expect_value(t, int_type(is.Int, false), runic.Builtin.UInt32)
    }
}
