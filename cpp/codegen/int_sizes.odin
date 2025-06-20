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

package cpp_codegen

import "root:runic"

Int_Sizes :: struct {
    char:                uint,
    short:               uint,
    Int:                 uint,
    long:                uint,
    longlong:            uint,
    float:               uint,
    double:              uint,
    long_double:         uint,
    _Bool:               uint,
    float_Complex:       uint,
    double_Complex:      uint,
    long_double_Complex: uint,
    size_t:              uint,
    intptr_t:            uint,
}

int_sizes_from_platform :: proc(plat: runic.Platform) -> (is: Int_Sizes) {
    switch plat.os {
    case .Any:
        panic("not int sizes for any os")
    case .Linux, .Macos, .BSD:
        switch plat.arch {
        case .Any:
            panic("no int sizes for any arch")
        case .x86_64, .arm64:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 8,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 16,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 32,
                    size_t = 8,
                    intptr_t = 8,
                } \
            )
        case .x86, .arm32:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 4,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 12,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 24,
                    size_t = 4,
                    intptr_t = 4,
                } \
            )
        }
    case .Windows:
        switch plat.arch {
        case .Any:
            panic("no int sizes for any arch")
        case .x86_64, .arm64:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 4,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 8,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 16,
                    size_t = 8,
                    intptr_t = 8,
                } \
            )
        case .x86, .arm32:
            return(
                 {
                    char = 1,
                    short = 2,
                    Int = 4,
                    long = 4,
                    longlong = 8,
                    float = 4,
                    double = 8,
                    long_double = 8,
                    _Bool = 1,
                    float_Complex = 8,
                    double_Complex = 16,
                    long_double_Complex = 16,
                    size_t = 4,
                    intptr_t = 4,
                } \
            )
        }
    }
    return
}

int_type :: proc(sz: uint, signed: bool) -> (t: runic.Builtin) {
    switch sz {
    case 1:
        t = .SInt8
    case 2:
        t = .SInt16
    case 4:
        t = .SInt32
    case 8:
        t = .SInt64
    case 16:
        t = .SInt128
    case:
        t = .Untyped
        return
    }

    if !signed {
        val := transmute(int)t
        val += 6
        t = transmute(runic.Builtin)val
    }
    return
}

bool_type :: proc(sz: uint) -> runic.Builtin {
    switch sz {
    case 1:
        return .Bool8
    case 2:
        return .Bool16
    case 4:
        return .Bool32
    case 8:
        return .Bool64
    }
    return .Untyped
}

float_type :: proc(sz: uint) -> runic.Builtin {
    switch sz {
    case 4:
        return .Float32
    case 8:
        return .Float64
    case 16:
        return .Float128
    }
    return .Untyped
}
