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
    language:                   string,
    static:                     string,
    static_linux:               string `json:"static.linux"`,
    static_linux_x86_64:        string `json:"static.linux.x86_64`,
    static_linux_arm64:         string `json:"static.linux.arm64`,
    static_windows:             string `json:"static.windows"`,
    static_windows_x86_64:      string `json:"static.windows.x86_64"`,
    static_windows_arm64:       string `json:"static.windows.arm64"`,
    static_macos:               string `json:"static.macos"`,
    static_macos_x86_64:        string `json:"static.macos.x86_64"`,
    static_macos_arm64:         string `json:"static.macos.arm64"`,
    static_bsd:                 string `json:"static.bsd"`,
    static_bsd_x86_64:          string `json:"static.bsd.x86_64"`,
    static_bsd_arm64:           string `json:"static.bsd.arm64"`,
    shared:                     string,
    shared_linux:               string `json:"shared.linux"`,
    shared_linux_x86_64:        string `json:"shared.linux.x86_64"`,
    shared_linux_arm64:         string `json:"shared.linux.arm64"`,
    shared_windows:             string `json:"shared.windows"`,
    shared_windows_x86_64:      string `json:"shared.windows.x86_64"`,
    shared_windows_arm64:       string `json:"shared.windows.arm64"`,
    shared_macos:               string `json:"shared.macos"`,
    shared_macos_x86_64:        string `json:"shared.macos.x86_64"`,
    shared_macos_arm64:         string `json:"shared.macos.arm64"`,
    shared_bsd:                 string `json:"shared.bsd"`,
    shared_bsd_x86_64:          string `json:"shared.bsd.x86_64"`,
    shared_bsd_arm64:           string `json:"shared.bsd.arm64"`,
    // General
    ignore:                     IgnoreSet,
    // C
    headers:                    [dynamic]string,
    headers_linux:              [dynamic]string `json:"headers.linux"`,
    headers_linux_x86_64:       [dynamic]string `json:"headers.linux.x86_64"`,
    headers_linux_arm64:        [dynamic]string `json:"headers.linux.arm64"`,
    headers_windows:            [dynamic]string `json:"headers.windows"`,
    headers_windows_x86_64:     [dynamic]string `json:"headers.windows.x86_64"`,
    headers_windows_arm64:      [dynamic]string `json:"headers.windows.arm64"`,
    headers_macos:              [dynamic]string `json:"headers.macos"`,
    headers_macos_x86_64:       [dynamic]string `json:"headers.macos.x86_64"`,
    headers_macos_arm64:        [dynamic]string `json:"headers.macos.arm64"`,
    headers_bsd:                [dynamic]string `json:"headers.bsd"`,
    headers_bsd_x86_64:         [dynamic]string `json:"headers.bsd.x86_64"`,
    headers_bsd_arm64:          [dynamic]string `json:"headers.bsd.arm64"`,
    includedirs:                [dynamic]string,
    includedirs_linux:          [dynamic]string `json:"includedirs.linux"`,
    includedirs_linux_x86_64:   [dynamic]string `json:"includedirs.linux.x86_64"`,
    includedirs_linux_arm64:    [dynamic]string `json:"includedirs.linux.arm64"`,
    includedirs_windows:        [dynamic]string `json:"includedirs.windows"`,
    includedirs_windows_x86_64: [dynamic]string `json:"includedirs.windows.x86_64"`,
    includedirs_windows_arm64:  [dynamic]string `json:"includedirs.windows.arm64"`,
    includedirs_macos:          [dynamic]string `json:"includedirs.macos"`,
    includedirs_macos_x86_64:   [dynamic]string `json:"includedirs.macos.x86_64"`,
    includedirs_macos_arm64:    [dynamic]string `json:"includedirs.macos.arm64"`,
    includedirs_bsd:            [dynamic]string `json:"includedirs.bsd"`,
    includedirs_bsd_x86_64:     [dynamic]string `json:"includedirs.bsd.x86_64"`,
    includedirs_bsd_arm64:      [dynamic]string `json:"includedirs.bsd.arm64"`,
    defines:                    map[string]json.Value,
    defines_linux:              map[string]json.Value `json:"defines.linux"`,
    defines_linux_x86_64:       map[string]json.Value `json:"defines.linux.x86_64"`,
    defines_linux_arm64:        map[string]json.Value `json:"defines.linux.arm64"`,
    defines_windows:            map[string]json.Value `json:"defines.windows"`,
    defines_windows_x86_64:     map[string]json.Value `json:"defines.windows.x86_64"`,
    defines_windows_arm64:      map[string]json.Value `json:"defines.windows.arm64"`,
    defines_macos:              map[string]json.Value `json:"defines.macos"`,
    defines_macos_x86_64:       map[string]json.Value `json:"defines.macos.x86_64"`,
    defines_macos_arm64:        map[string]json.Value `json:"defines.macos.arm64"`,
    defines_bsd:                map[string]json.Value `json:"defines.bsd"`,
    defines_bsd_x86_64:         map[string]json.Value `json:"defines.bsd.x86_64"`,
    defines_bsd_arm64:          map[string]json.Value `json:"defines.bsd.arm64"`,
    // Odin
    packages:                   [dynamic]string,
    packages_linux:             [dynamic]string `json:"packages.linux"`,
    packages_linux_x86_64:      [dynamic]string `json:"packages.linux.x86_64"`,
    packages_linux_arm64:       [dynamic]string `json:"packages.linux.arm64"`,
    packages_windows:           [dynamic]string `json:"packages.windows"`,
    packages_windows_x86_64:    [dynamic]string `json:"packages.windows.x86_64"`,
    packages_windows_arm64:     [dynamic]string `json:"packages.windows.arm64"`,
    packages_macos:             [dynamic]string `json:"packages.macos"`,
    packages_macos_x86_64:      [dynamic]string `json:"packages.macos.x86_64"`,
    packages_macos_arm64:       [dynamic]string `json:"packages.macos.arm64"`,
    packages_bsd:               [dynamic]string `json:"packages.bsd"`,
    packages_bsd_x86_64:        [dynamic]string `json:"packages.bsd.x86_64"`,
    packages_bsd_arm64:         [dynamic]string `json:"packages.bsd.arm64"`,
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

parse_rune :: proc(rd: io.Reader, file_path: string) -> (rn: Rune, err: union {
        io.Error,
        json.Unmarshal_Error,
    }) {
    rn_arena_alloc := runtime.arena_allocator(&rn.arena)

    buf: bytes.Buffer
    bytes.buffer_init_allocator(&buf, 0, 0)
    defer bytes.buffer_destroy(&buf)

    io.copy(bytes.buffer_to_stream(&buf), rd) or_return

    data := bytes.buffer_to_bytes(&buf)

    json.unmarshal(data, &rn, allocator = rn_arena_alloc) or_return

    switch &to in rn.to {
    case To:
        to.trim_prefix = trim_to_trim_set(to.trim_prefix)
        to.trim_suffix = trim_to_trim_set(to.trim_suffix)
        to.add_prefix = add_to_add_set(to.add_prefix)
        to.add_suffix = add_to_add_set(to.add_suffix)

        if to.detect.multi_pointer == "" {
            to.detect.multi_pointer = "auto"
        }
    case string:
        if to != "stdout" {
            to = relative_to_file(file_path, to, rn_arena_alloc)
        }
    }

    switch &from in rn.from {
    case From:
        from.static = relative_to_file(
            file_path,
            from.static,
            rn_arena_alloc,
            true,
        )
        from.static_linux = relative_to_file(
            file_path,
            from.static_linux,
            rn_arena_alloc,
            true,
        )
        from.static_linux_x86_64 = relative_to_file(
            file_path,
            from.static_linux_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_linux_arm64 = relative_to_file(
            file_path,
            from.static_linux_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_windows = relative_to_file(
            file_path,
            from.static_windows,
            rn_arena_alloc,
            true,
        )
        from.static_windows_x86_64 = relative_to_file(
            file_path,
            from.static_windows_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_windows_arm64 = relative_to_file(
            file_path,
            from.static_windows_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_macos = relative_to_file(
            file_path,
            from.static_macos,
            rn_arena_alloc,
            true,
        )
        from.static_macos_x86_64 = relative_to_file(
            file_path,
            from.static_macos_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_macos_arm64 = relative_to_file(
            file_path,
            from.static_macos_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_bsd = relative_to_file(
            file_path,
            from.static_bsd,
            rn_arena_alloc,
            true,
        )
        from.static_bsd_x86_64 = relative_to_file(
            file_path,
            from.static_bsd_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_bsd_arm64 = relative_to_file(
            file_path,
            from.static_bsd_arm64,
            rn_arena_alloc,
            true,
        )

        from.shared = relative_to_file(
            file_path,
            from.shared,
            rn_arena_alloc,
            true,
        )
        from.shared_linux = relative_to_file(
            file_path,
            from.shared_linux,
            rn_arena_alloc,
            true,
        )
        from.shared_linux_x86_64 = relative_to_file(
            file_path,
            from.shared_linux_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_linux_arm64 = relative_to_file(
            file_path,
            from.shared_linux_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_windows = relative_to_file(
            file_path,
            from.shared_windows,
            rn_arena_alloc,
            true,
        )
        from.shared_windows_x86_64 = relative_to_file(
            file_path,
            from.shared_windows_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_windows_arm64 = relative_to_file(
            file_path,
            from.shared_windows_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_macos = relative_to_file(
            file_path,
            from.shared_macos,
            rn_arena_alloc,
            true,
        )
        from.shared_macos_x86_64 = relative_to_file(
            file_path,
            from.shared_macos_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_macos_arm64 = relative_to_file(
            file_path,
            from.shared_macos_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd = relative_to_file(
            file_path,
            from.shared_bsd,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd_x86_64 = relative_to_file(
            file_path,
            from.shared_bsd_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd_arm64 = relative_to_file(
            file_path,
            from.shared_bsd_arm64,
            rn_arena_alloc,
            true,
        )

        // TODO: for all platforms
        for &path in from.includedirs {
            path = relative_to_file(file_path, path, rn_arena_alloc)
        }

    case string:
        if from != "stdin" {
            from = relative_to_file(file_path, from, rn_arena_alloc)
        }
    case [dynamic]string:
        for &path in from {
            path = relative_to_file(file_path, path, rn_arena_alloc)
        }
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
    needs_dir := false,
) -> (
    string,
    bool,
) #optional_ok {
    if len(file_name) == 0 do return file_name, true
    if filepath.is_abs(file_name) || (needs_dir && !strings.contains(file_name, "/") && !strings.contains(file_name, "\\")) do return strings.clone(file_name, allocator), true

    rune_dir := filepath.dir(rune_file_name, allocator)
    defer delete(rune_dir, allocator)

    if !filepath.is_abs(rune_dir) {
        abs_rune_dir, ok := filepath.abs(rune_dir, allocator)
        if ok {
            delete(rune_dir, allocator)
            rune_dir = abs_rune_dir
        }
    }

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
