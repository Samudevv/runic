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

Rune :: struct {
    version:   uint,
    platforms: []Platform,
    from:      union {
        From,
        string,
        [dynamic]string,
    },
    to:        union {
        To,
        string,
    },
    arena:     runtime.Arena,
}

From :: struct {
    // General
    language:    string,
    static:      PlatformValue(string),
    shared:      PlatformValue(string),
    ignore:      PlatformValue(IgnoreSet),
    overwrite:   PlatformValue(OverwriteSet),
    extern:      []string,
    // C
    headers:     PlatformValue([]string),
    includedirs: PlatformValue([]string),
    defines:     PlatformValue(map[string]string),
    flags:       PlatformValue([]cstring),
    // Odin
    packages:    PlatformValue([]string),
}

To :: struct {
    language:      string,
    // General
    static_switch: string,
    out:           string,
    trim_prefix:   TrimSet,
    trim_suffix:   TrimSet,
    add_prefix:    AddSet,
    add_suffix:    AddSet,
    ignore_arch:   bool,
    extern:        ExternRune,
    // Odin
    package_name:  string,
    detect:        OdinDetect,
    no_build_tag:  bool,
    use_when_else: bool,
}

TrimSet :: struct {
    functions: []string,
    variables: []string,
    types:     []string,
    constants: []string,
}

AddSet :: struct {
    functions: string,
    variables: string,
    types:     string,
    constants: string,
}

IgnoreSet :: struct {
    macros:    []string,
    functions: []string,
    variables: []string,
    types:     []string,
}

Overwrite :: struct {
    name:        string,
    instruction: OverwriteInstruction,
}

OverwriteSet :: struct {
    constants: [dynamic]Overwrite,
    functions: [dynamic]Overwrite,
    variables: [dynamic]Overwrite,
    types:     [dynamic]Overwrite,
}

OverwriteWhole :: distinct string
OverwriteReturnType :: distinct string
OverwriteParameterType :: struct {
    idx:       int,
    overwrite: string,
}
OverwriteParameterName :: struct {
    idx:       int,
    overwrite: string,
}
OverwriteMemberType :: struct {
    idx:       int,
    overwrite: string,
}
OverwriteMemberName :: struct {
    idx:       int,
    overwrite: string,
}

OverwriteInstruction :: union {
    OverwriteWhole,
    OverwriteReturnType,
    OverwriteParameterType,
    OverwriteParameterName,
    OverwriteMemberType,
    OverwriteMemberName,
}

OdinDetect :: struct {
    multi_pointer: string,
}


PlatformValue :: struct(T: typeid) {
    d: map[Platform]T,
}

ExternRune :: struct {
    sources:     map[string]string,
    remaps:      map[string]string,
    trim_prefix: bool,
    trim_suffix: bool,
    add_prefix:  bool,
    add_suffix:  bool,
}
