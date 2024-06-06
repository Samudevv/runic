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

import "base:runtime"
import "core:bytes"
import "core:encoding/json"
import "core:io"
import "core:path/filepath"
import "core:slice"
import "core:strings"

From :: struct {
    language:               string,
    static:                 string,
    static_linux:           string `json:"static.linux"`,
    static_windows:         string `json:"static.windows"`,
    shared:                 string,
    shared_linux:           string `json:"shared.linux"`,
    shared_windows:         string `json:"shared.windows"`,
    // General
    ignore:                 IgnoreSet,
    // C
    headers:                [dynamic]string,
    headers_linux:          [dynamic]string `json:"headers.linux"`,
    headers_windows:        [dynamic]string `json:"headers.windows"`,
    headers_macosx:         [dynamic]string `json:"headers.macosx"`,
    headers_macosx_aarch64: [dynamic]string `json:"headers.macosx.aarch64"`,
    includedirs:            [dynamic]string,
    includedirs_linux:      [dynamic]string `json:"includedirs.linux"`,
    includedirs_windows:    [dynamic]string `json:"includedirs.windows"`,
    defines:                map[string]json.Value,
    defines_linux:          map[string]json.Value `json:"defines.linux"`,
    defines_windows:        map[string]json.Value `json:"defines.windows"`,
    preprocessor:           SingleList,
    // Odin
    packages:               [dynamic]string,
}

TrimSet :: struct {
    functions: SingleList,
    variables: SingleList,
    types:     SingleList,
    constants: SingleList,
}

AddSet :: struct {
    functions: string,
    variables: string,
    types:     string,
    constants: string,
}

IgnoreSet :: struct {
    macros:    SingleList,
    functions: SingleList,
    variables: SingleList,
    types:     SingleList,
}

Trim :: union {
    string,
    [dynamic]string,
    TrimSet,
}

Add :: union {
    string,
    AddSet,
}

OdinDetect :: struct {
    multi_pointer: string,
}

To :: struct {
    language:      string,
    // General
    static_switch: string,
    out:           string,
    trim_prefix:   Trim,
    trim_suffix:   Trim,
    add_prefix:    Add,
    add_suffix:    Add,
    // Odin
    package_name:  string `json:"package"`,
    detect:        OdinDetect,
}

Rune :: struct {
    version: uint,
    from:    union {
        From,
        string,
        [dynamic]string,
    },
    to:      union {
        To,
        string,
    },
    arena:   runtime.Arena,
}

SingleList :: union {
    string,
    [dynamic]string,
}

parse_rune :: proc(rd: io.Reader) -> (rn: Rune, err: union {
        io.Error,
        json.Unmarshal_Error,
    }) {
    buf: bytes.Buffer
    bytes.buffer_init_allocator(&buf, 0, 0)
    defer bytes.buffer_destroy(&buf)

    io.copy(bytes.buffer_to_stream(&buf), rd) or_return

    data := bytes.buffer_to_bytes(&buf)

    json.unmarshal(
        data,
        &rn,
        allocator = runtime.arena_allocator(&rn.arena),
    ) or_return

    if to, ok := rn.to.(To); ok {
        to.trim_prefix = trim_to_trim_set(to.trim_prefix)
        to.trim_suffix = trim_to_trim_set(to.trim_suffix)
        to.add_prefix = add_to_add_set(to.add_prefix)
        to.add_suffix = add_to_add_set(to.add_suffix)

        if to.detect.multi_pointer == "" {
            to.detect.multi_pointer = "auto"
        }

        rn.to = to
    }

    return
}

rune_destroy :: proc(rn: ^Rune) {
    runtime.arena_destroy(&rn.arena)
}

@(private = "file")
single_list_trim_prefix :: #force_inline proc(
    ident: string,
    list: SingleList,
) -> string {
    switch l in list {
    case string:
        return strings.trim_prefix(ident, l)
    case [dynamic]string:
        str := ident
        for v in l {
            str = strings.trim_prefix(str, v)
        }
        return str
    }

    return ident
}

@(private = "file")
single_list_trim_suffix :: #force_inline proc(
    ident: string,
    list: SingleList,
) -> string {
    switch l in list {
    case string:
        return strings.trim_suffix(ident, l)
    case [dynamic]string:
        str := ident
        for v in l {
            str = strings.trim_suffix(str, v)
        }
    }

    return ident
}

@(private = "file")
add_prefix :: #force_inline proc(
    ident: string,
    prefix: string,
    allocator := context.allocator,
) -> string {
    return strings.concatenate({prefix, ident}, allocator)
}

@(private = "file")
add_suffix :: #force_inline proc(
    ident: string,
    suffix: string,
    allocator := context.allocator,
) -> string {
    return strings.concatenate({ident, suffix}, allocator)
}

@(private = "file")
is_valid_identifier :: proc(ident: string) -> bool {
    if len(ident) == 0 do return false

    for r, idx in ident {
        if idx == 0 {
            switch r {
            case '0' ..= '9':
                return false
            }
        }

        switch r {
        case 0 ..= '/', ':' ..= '@', '[' ..= '`', '{' ..= 127:
            return false
        }

        break
    }


    return true
}

@(private = "file")
process_identifier :: #force_inline proc(
    ident: string,
    trim_prefix, trim_suffix: SingleList,
    add_pf, add_sf: string,
    reserved: []string,
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    if !valid_ident(ident) do return ident

    ident1 := single_list_trim_prefix(ident, trim_prefix)
    if !valid_ident(ident1) do return ident

    ident2 := single_list_trim_suffix(ident1, trim_suffix)
    if !valid_ident(ident2) do return ident1

    ident3 := add_prefix(ident2, add_pf, allocator)
    if !valid_ident(ident3) do return ident2

    ident4 := add_suffix(ident3, add_sf, allocator)
    if !valid_ident(ident4) {
        delete(ident4, allocator)
        return ident3
    }
    delete(ident3, allocator)

    if slice.contains(reserved, ident4) {
        ident5 := strings.concatenate({ident4, "_"}, allocator)
        delete(ident4, allocator)
        ident4 = ident5
    }

    return ident4
}

@(private = "file")
trim_to_trim_set :: #force_inline proc(t: Trim) -> TrimSet {
    if t == nil do return {}

    switch trim in t {
    case string:
        return {trim, trim, trim, trim}
    case [dynamic]string:
        return {trim, trim, trim, trim}
    case TrimSet:
        return trim
    }

    return {}
}

@(private = "file")
add_to_add_set :: #force_inline proc(a: Add) -> AddSet {
    if a == nil do return {}

    switch add in a {
    case string:
        return {add, add, add, add}
    case AddSet:
        return add
    }

    return {}
}

process_function_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        (rn.trim_prefix.(TrimSet) or_else {}).functions,
        (rn.trim_suffix.(TrimSet) or_else {}).functions,
        (rn.add_prefix.(AddSet) or_else {}).functions,
        (rn.add_suffix.(AddSet) or_else {}).functions,
        reserved,
        valid_ident,
        allocator,
    )
}

process_variable_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        (rn.trim_prefix.(TrimSet) or_else {}).variables,
        (rn.trim_suffix.(TrimSet) or_else {}).variables,
        (rn.add_prefix.(AddSet) or_else {}).variables,
        (rn.add_suffix.(AddSet) or_else {}).variables,
        reserved,
        valid_ident,
        allocator,
    )
}

process_type_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        (rn.trim_prefix.(TrimSet) or_else {}).types,
        (rn.trim_suffix.(TrimSet) or_else {}).types,
        (rn.add_prefix.(AddSet) or_else {}).types,
        (rn.add_suffix.(AddSet) or_else {}).types,
        reserved,
        valid_ident,
        allocator,
    )
}

process_constant_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        (rn.trim_prefix.(TrimSet) or_else {}).constants,
        (rn.trim_suffix.(TrimSet) or_else {}).constants,
        (rn.add_prefix.(AddSet) or_else {}).constants,
        (rn.add_suffix.(AddSet) or_else {}).constants,
        reserved,
        valid_ident,
        allocator,
    )
}

relative_to_file :: proc(
    rune_file_name, file_name: string,
    allocator := context.allocator,
) -> (
    string,
    bool,
) #optional_ok {
    if filepath.is_abs(file_name) do return strings.clone(file_name, allocator), true

    rune_dir := filepath.dir(rune_file_name, allocator)
    defer delete(rune_dir, allocator)

    rel_path := filepath.join({rune_dir, file_name}, allocator)
    return rel_path, true
}

single_list_contains :: proc(list: SingleList, value: string) -> bool {
    switch l in list {
    case string:
        return value == l
    case [dynamic]string:
        return slice.contains(l[:], value)
    }

    return false
}

single_list_glob :: proc(list: SingleList, value: string) -> bool {
    switch l in list {
    case string:
        ok, _ := filepath.match(l, value)
        return ok
    case [dynamic]string:
        for p in l {
            ok, _ := filepath.match(p, value)
            if ok do return true
        }
    }

    return false
}

contains :: proc {
    single_list_contains,
}
