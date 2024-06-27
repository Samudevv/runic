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

// c-spec.pdf p.111
BuiltinType :: enum {
    void,
    char,
    signedchar,
    unsignedchar,
    short, // short, signed short, short int, signed short int
    unsignedshort, // unsigned short int
    int, // signed, signed int
    unsignedint, // unsigned
    long, // signed long, long int, signed long int
    unsignedlong, // unsigned long int
    longlong, // signed long long, long long int, signed long long int
    unsignedlonglong, // unsigned long long int
    float,
    double,
    longdouble,
    _Bool,
    float_Complex,
    double_Complex,
    longdouble_Complex,
}

TypeQualifier :: enum {
    const,
    restrict,
    volatile,
    _Atomic,
    static,
    Inline,
    extern,
    _Noreturn,
}

IncludeType :: enum {
    Relative,
    System,
}

PointerInfo :: struct {
    const:    bool,
    restrict: bool,
    count:    uint,
    child:    ^PointerInfo,
}

ArrayInfo :: [dynamic]ConstantIntegerExpression

Var :: struct {
    name:         Maybe(string),
    type:         Type,
    qualifiers:   [dynamic]TypeQualifier,
    pointer_info: PointerInfo,
    array_info:   ArrayInfo,
}

Struct :: struct {
    name:    Maybe(string),
    members: [dynamic]Variable,
}

Union :: struct {
    name:    Maybe(string),
    members: [dynamic]Variable,
}

EnumConstant :: struct {
    name:  string,
    value: Maybe(ConstantIntegerExpression),
}

Enum :: struct {
    name:   Maybe(string),
    values: [dynamic]EnumConstant,
}

CustomType :: struct {
    name: string,
}

Function :: struct {
    name:         Maybe(string),
    return_type:  ^Variable,
    parameters:   [dynamic]Variable,
    variadic:     bool,
    pointer_info: PointerInfo,
    array_info:   ArrayInfo,
}

FunctionPrototype :: distinct Function

MacroInsertion :: struct {
    parameter: int,
    spaces:    int,
    // MAYBEDO: parameter can also be inserted as string
}

MacroFunc :: struct {
    name:       string,
    parameters: [dynamic]string,
    body:       [dynamic]MacroFuncToken,
}

MacroVar :: struct {
    name:  string,
    value: Maybe(string),
}

Include :: struct {
    type: IncludeType,
    path: string,
}

ConstantIntegerExpression :: union {
    i64,
    string,
}

Variable :: union {
    Var,
    Function,
}

Type :: union {
    BuiltinType,
    Struct,
    Enum,
    Union,
    CustomType,
    FunctionPrototype,
}

MacroFuncToken :: union {
    string,
    MacroInsertion,
}

Macro :: union {
    MacroVar,
    MacroFunc,
}
