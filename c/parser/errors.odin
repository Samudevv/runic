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

package parser

import ctz "root:c/tokenizer"
import "root:errors"

@(private)
errors_eof :: proc(t: ^ctz.Token, loc := #caller_location) -> errors.Error {
    return errors.message(
        "{}:{}: file ended prematurely",
        t.pos.file,
        t.pos.line,
        loc = loc,
    )
}

@(private)
errors_expect :: proc(
    t: ^ctz.Token,
    what: string,
    loc := #caller_location,
) -> errors.Error {
    return errors.message(
        "{}:{}:{}: {} expected but got {}",
        t.pos.file,
        t.pos.line,
        t.pos.column,
        what,
        t.lit,
        loc = loc,
    )
}

@(private)
errors_ident :: proc(t: ^ctz.Token, loc := #caller_location) -> errors.Error {
    return errors_expect(t, "identifier", loc = loc)
}

