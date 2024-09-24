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

package main

import "../parser"
import "core:fmt"
import "core:io"
import "core:os"
import "root:errors"
import "root:runic"

main :: proc() {
    plat := runic.platform_from_host()

    in_file_name: string
    in_handle: os.Handle
    in_stream: io.Reader

    defer os.close(in_handle)

    if len(os.args) >= 2 {
        in_file_name = os.args[1]
    }

    if len(in_file_name) == 0 || in_file_name == "-" {
        in_file_name = "./stdin"
        in_stream = os.stream_from_handle(os.stdin)
    } else {
        os_err: os.Error = ---
        in_handle, os_err = os.open(in_file_name)
        if os_err != nil {
            fmt.eprintfln("{}", errors.wrap(os_err))
            os.exit(1)
        }
        in_stream = os.stream_from_handle(in_handle)
    }

    err := parser.preprocess_file(
        plat,
        in_stream,
        os.stream_from_handle(os.stdout),
    )
    if err != nil {
        fmt.eprintfln("failed to prepreprocess: {}", err)
        os.exit(1)
    }
}

