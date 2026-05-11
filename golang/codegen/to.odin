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
package golang_codegen

import "root:runic"
import "root:errors"
import "core:io"

GO_RESERVED :: []string{
    "int",
    "uint",
}

generate_bindings :: proc {
    generate_bindings_from_runecross,
}

generate_bindings_from_runecross :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    wd: io.Writer,
) -> union {
    io.Error,
    errors.Error,
} {
    if !rn.purego do return errors.Error(errors.message("\"to.purego\" must be true. Only purego golang bindings are supported"))

    for rs in rc.cross {
        purego_generate_bindings_from_runestone(rs, rn, wd) or_return
    }

    return nil
}

