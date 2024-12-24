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
import om "root:ordered_map"

Runestone :: struct {
    version:   uint,
    platform:  Platform,
    lib:       Library,
    symbols:   om.OrderedMap(string, Symbol),
    externs:   om.OrderedMap(string, Extern),
    types:     om.OrderedMap(string, Type),
    constants: om.OrderedMap(string, Constant),
    arena:     runtime.Arena,
}

Builtin :: enum {
    Untyped,
    RawPtr,
    SInt8,
    SInt16,
    SInt32,
    SInt64,
    SInt128,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    UInt128,
    Float32,
    Float64,
    Float128,
    String,
    Bool8,
    Bool16,
    Bool32,
    Bool64,
    Opaque,
}

Member :: struct {
    name: string,
    type: Type,
}

Struct :: struct {
    members: [dynamic]Member,
}

Union :: struct {
    members: [dynamic]Member,
}

EnumEntry :: struct {
    name:  string,
    value: EnumConstant,
}

Enum :: struct {
    type:    Builtin,
    entries: [dynamic]EnumEntry,
}

Unknown :: distinct string

PointerInfo :: struct {
    count:      uint,
    read_only:  bool,
    write_only: bool,
}

Type :: struct {
    spec:         TypeSpecifier,
    read_only:    bool,
    write_only:   bool,
    pointer_info: PointerInfo,
    array_info:   [dynamic]Array,
}

Array :: struct {
    pointer_info: PointerInfo,
    read_only:    bool,
    write_only:   bool,
    size:         ArraySize,
}

MethodInfo :: struct {
    type: string,
    name: string,
}

Function :: struct {
    return_type: Type,
    parameters:  [dynamic]Member,
    variadic:    bool,
    method_info: Maybe(MethodInfo),
}

FunctionPointer :: ^Function

Constant :: struct {
    value: union {
        i64,
        f64,
        string,
    },
    type:  Type,
}

Symbol :: struct {
    value:   union {
        Type,
        Function,
    },
    remap:   Maybe(string),
    aliases: [dynamic]string,
}

Library :: struct {
    shared: Maybe(string),
    static: Maybe(string),
}

Extern :: struct {
    using type: Type,
    source:     string,
}

ExternType :: distinct string

TypeSpecifier :: union {
    Builtin,
    Struct,
    Enum,
    Union,
    string,
    Unknown,
    FunctionPointer,
    ExternType,
}

EnumConstant :: union {
    i64,
    string,
}

ArraySize :: union {
    u64,
    string,
}

