#+feature global-context
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

package errors

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:os"
import "core:reflect"

Error :: Maybe(string)

@(private)
error_arena: runtime.Arena
@(private)
error_arena_err := runtime.arena_init(
    &error_arena,
    0,
    runtime.default_allocator(),
)
error_allocator := runtime.arena_allocator(&error_arena)

message :: proc(
    fmt_str: string,
    args: ..any,
    allocator := error_allocator,
    loc := #caller_location,
) -> string {
    when ODIN_DEBUG {
        return fmt.aprintf(
            "{} at {}:{}:{}",
            fmt.aprintf(fmt_str, ..args, allocator = allocator),
            loc.file_path,
            loc.line,
            loc.column,
            allocator = allocator,
        )
    } else {
        return fmt.aprintf(fmt_str, ..args, allocator = allocator)
    }
}

empty :: proc(
    allocator := error_allocator,
    loc := #caller_location,
) -> string {
    return fmt.aprintf("error at {}", loc, allocator = allocator)
}

not_implemented :: proc(
    allocator := error_allocator,
    loc := #caller_location,
) -> string {
    return message("not implemented", allocator = allocator, loc = loc)
}

unknown :: proc(
    allocator := error_allocator,
    loc := #caller_location,
) -> string {
    return message("unknown", allocator = allocator, loc = loc)
}

to_error :: proc(
    err: any,
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    return message("{}", err, allocator = allocator, loc = loc)
}


wrap_io :: proc(
    err: io.Error,
    msg := "",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    if err == .None do return nil
    return message(
        "{}io.Error: {}",
        msg,
        err,
        allocator = allocator,
        loc = loc,
    )
}

wrap_json :: proc(
    err: json.Error,
    msg := "",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    if err == .None do return nil
    return message(
        "{}json.Error: {}",
        msg,
        err,
        allocator = allocator,
        loc = loc,
    )
}

wrap_ok :: proc(
    ok: bool,
    msg := "not ok",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    if ok do return nil
    return message(msg, allocator = allocator, loc = loc)
}

wrap_allocator :: proc(
    err: runtime.Allocator_Error,
    msg := "",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    if err == .None do return nil
    return message(
        "{}Allocator_Error: {}",
        msg,
        err,
        allocator = allocator,
        loc = loc,
    )
}

wrap_errno :: proc(
    err: os.Error,
    msg := "",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    if err == 0 do return nil
    return message("{}{}", msg, err, allocator = allocator, loc = loc)
}

wrap_union :: proc(
    err: any,
    msg := "",
    allocator := error_allocator,
    loc := #caller_location,
) -> Error {
    ti := type_info_of(err.id)
    if reflect.is_union(ti) {
        var := reflect.get_union_variant(err)
        if var == nil do return nil

        switch v in var {
        case io.Error:
            return wrap_io(v, msg, allocator, loc)
        case json.Error:
            return wrap_json(v, msg, allocator, loc)
        case bool:
            return wrap_ok(v, msg, allocator, loc)
        case runtime.Allocator_Error:
            return wrap_allocator(v, msg, allocator, loc)
        case os.Error:
            return wrap_errno(v, msg, allocator, loc)
        case Error:
            return v
        }
    }

    return message("{}{}", msg, err, allocator = allocator, loc = loc)
}

wrap :: proc {
    wrap_io,
    wrap_json,
    wrap_ok,
    wrap_allocator,
    wrap_errno,
    wrap_union,
}

assert :: wrap_ok

