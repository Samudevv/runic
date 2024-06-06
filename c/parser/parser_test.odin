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

import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:os"
import "core:testing"
import om "root:ordered_map"

@(test)
test_builtin :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/builtin.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(variables), 11) do return
    if !expect_value(t, len(typedefs), 35) do return

    expect_value(t, typedefs[0].(Var).type.(BuiltinType), BuiltinType.void)

    expect_value(t, variables[0].(Var).name.?, "foo")
    expect_value(t, variables[1].(Var).name.?, "bar")
    expect_value(t, variables[2].(Var).name.?, "baz")
    expect_value(t, variables[0].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[1].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[2].(Var).type.(BuiltinType), BuiltinType.int)

    expect_value(t, variables[3].(Var).name.?, "oof")
    expect_value(t, variables[4].(Var).name.?, "rab")
    expect_value(t, variables[5].(Var).name.?, "zab")
    expect_value(t, variables[3].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[4].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[5].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[3].(Var).pointer_info.count, 0)
    expect_value(t, variables[4].(Var).pointer_info.count, 2)
    expect_value(t, variables[5].(Var).pointer_info.count, 1)
    expect_value(t, len(variables[3].(Var).array_info), 0)
    expect_value(t, len(variables[4].(Var).array_info), 0)
    expect_value(t, variables[5].(Var).array_info[0].(i64), 2)

    expect_value(t, variables[6].(Var).name.?, "value")
    expect_value(t, variables[7].(Var).name.?, "m1")
    expect_value(t, variables[8].(Var).name.?, "m2")
    expect_value(t, variables[9].(Var).name.?, "m3")

    expect_value(t, variables[10].(Var).name.?, "names")
    expect_value(t, variables[10].(Var).array_info[0], nil)
}

@(test)
test_struct :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/struct.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    expect_value(t, len(variables), 0)
    expect_value(t, len(typedefs), 3)

    for td in typedefs {
        _, ok := td.(Var).type.(Struct)
        expect(t, ok)
    }
}

@(test)
test_enum :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/enum.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(variables), 1) {
        return
    }
    if !expect_value(t, len(typedefs), 4) {
        return
    }

    for td in typedefs[:3] {
        _, ok := td.(Var).type.(Enum)
        expect(t, ok)
    }

    e0 := typedefs[0].(Var).type.(Enum)
    e0Name := typedefs[0].(Var).name

    expect_value(t, len(e0.values), 3)
    expect_value(t, e0Name.?, "abc_enum")
    expect_value(t, e0.values[0].name, "A")
    expect_value(t, e0.values[1].name, "B")
    expect_value(t, e0.values[2].name, "C")
    expect_value(t, e0.values[0].value, nil)
    expect_value(t, e0.values[1].value, nil)
    expect_value(t, e0.values[2].value, nil)

    e1 := typedefs[1].(Var).type.(Enum)
    e1Name := e1.name

    expect_value(t, len(e1.values), 3)
    expect_value(t, e1Name.?, "cba_enum")
    expect_value(t, e1.values[0].name, "C")
    expect_value(t, e1.values[1].name, "B")
    expect_value(t, e1.values[2].name, "A")
    expect_value(t, e1.values[0].value, nil)
    expect_value(t, e1.values[1].value, nil)
    expect_value(t, e1.values[2].value, nil)

    e2 := typedefs[2].(Var).type.(Enum)
    e2Name := e2.name

    expect_value(t, len(e2.values), 7)
    expect_value(t, e2Name.?, "constants")
    expect_value(t, e2.values[0].name, "X")
    expect_value(t, e2.values[1].name, "Y")
    expect_value(t, e2.values[2].name, "Z")
    expect_value(t, e2.values[3].name, "W")
    expect_value(t, e2.values[4].name, "Apple")
    expect_value(t, e2.values[5].name, "Banana")
    expect_value(t, e2.values[6].name, "Calculate")
    expect_value(t, e2.values[0].value.?.(i64), 1)
    expect_value(t, e2.values[1].value.?.(i64), 5)
    expect_value(t, e2.values[2].value.?.(i64), 8)
    expect_value(t, e2.values[3].value.?.(i64), -7)
    expect_value(t, e2.values[4].value.?.(i64), 789)
    expect_value(t, e2.values[5].value.?.(string), "90.8")
    expect_value(t, e2.values[6].value.?.(i64), 6)

    v0 := variables[0].(Var).type.(Enum)
    v0Name := variables[0].(Var).name

    expect_value(t, len(v0.values), 2)
    expect_value(t, v0Name.?, "banana")

    s0 := typedefs[3].(Var).type.(Struct)
    s0e := s0.members[1].(Var).type.(Enum)
    expect_value(t, len(s0e.values), 2)
}

@(test)
test_union :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/union.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(variables), 0) {
        return
    }
    if !expect_value(t, len(typedefs), 2) {
        return
    }

    my_union := typedefs[0].(Var).type.(Union)

    expect_value(t, typedefs[0].(Var).name.?, "my_union")
    expect_value(t, len(my_union.members), 2)
}

@(test)
test_function :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/function.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(typedefs), 0) {
        return
    }
    if !expect_value(t, len(variables), 1) {
        return
    }
    if !expect_value(t, len(functions), 9) {
        return
    }

    f0 := functions[0]
    expect_value(t, f0.name.?, "hello_world")
    expect_value(t, f0.return_type.(Var).type.(BuiltinType), BuiltinType.void)
    expect_value(t, len(f0.parameters), 0)

    f1 := functions[1]
    expect_value(t, f1.name.?, "foo")
    expect_value(t, f1.return_type.(Var).type.(BuiltinType), BuiltinType.void)
    expect_value(t, len(f1.parameters), 3)

    f2 := functions[2]
    expect_value(t, f2.name.?, "bar")

    f3 := functions[3]
    expect_value(t, f3.name.?, "baz")

    f4 := functions[4]
    expect_value(t, f4.name.?, "strcpy")
    expect_value(t, f4.return_type.(Var).pointer_info.count, 1)
    expect_value(t, f4.return_type.(Var).qualifiers[0], TypeQualifier.const)
    expect_value(t, len(f4.parameters), 1)
    expect_value(t, f4.parameters[0].(Var).pointer_info.count, 1)

    b := functions[6]
    expect_value(t, b.name.?, "b")

    af := functions[7]
    expect_value(t, af.name.?, "asm_func")

    a := variables[0]
    expect_value(t, a.(Var).name.?, "a")

    eof := functions[8]
    expect_value(t, eof.name.?, "eof")
}

@(test)
test_function_pointer :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/function_pointer.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(functions), 0) {
        return
    }
    if !expect_value(t, len(typedefs), 1) {
        return
    }
    if !expect_value(t, len(variables), 5) {
        return
    }

    hello := variables[0].(Function)
    expect_value(t, hello.name.?, "hello")
    expect_value(t, len(hello.parameters), 0)
    expect_value(
        t,
        hello.return_type.(Var).type.(BuiltinType),
        BuiltinType.void,
    )

    bye := variables[1].(Function)
    expect_value(t, bye.name.?, "bye")
    expect_value(t, len(bye.parameters), 4)
    expect_value(t, len(bye.parameters[3].(Var).type.(Struct).members), 2)

    cb := typedefs[0].(Function)
    expect_value(t, cb.name.?, "callback")
    expect_value(t, len(cb.parameters), 5)
    expect_value(t, cb.return_type.(Var).type.(BuiltinType), BuiltinType.void)

    pa := variables[2].(Function)
    expect_value(t, pa.name.?, "get_proc_address")
    expect_value(t, len(pa.parameters), 1)
    expect_value(t, pa.return_type.(Var).pointer_info.count, 1)

    hw := variables[3].(Function)
    expect_value(t, hw.name.?, "hello_world")
    expect_value(t, hw.pointer_info.count, 1)

    foo := variables[4].(Function)
    expect_value(t, foo.name.?, "foo")
    expect_value(t, foo.pointer_info.count, 3)
    expect_value(t, foo.pointer_info.const, true)
}

@(test)
test_pointer :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/pointer.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(functions), 0) {
        return
    }
    if !expect_value(t, len(typedefs), 0) {
        return
    }
    if !expect_value(t, len(variables), 8) {
        return
    }

    a := variables[0].(Var)
    expect_value(t, a.name.?, "a")
    expect_value(t, a.pointer_info.count, 1)
    expect_value(t, a.pointer_info.const, false)

    b := variables[1].(Var)
    expect_value(t, b.name.?, "b")
    expect_value(t, b.pointer_info.count, 3)
    expect_value(t, b.pointer_info.const, false)

    c := variables[2].(Var)
    expect_value(t, c.name.?, "c")
    expect_value(t, c.pointer_info.count, 2)
    expect_value(t, c.pointer_info.const, true)

    str := variables[3].(Var)
    expect_value(t, str.name.?, "str")
    expect_value(t, str.pointer_info.count, 1)
    expect_value(t, str.pointer_info.const, false)
    expect_value(t, str.qualifiers[0], TypeQualifier.const)

    c1 := variables[4].(Var)
    expect_value(t, c1.name.?, "c1")
    expect_value(t, c1.pointer_info.count, 2)
    expect_value(t, c1.pointer_info.const, true)
    expect_value(t, c1.qualifiers[0], TypeQualifier.const)

    c1 = variables[5].(Var)
    expect_value(t, c1.name.?, "xyz")
    expect_value(t, c1.pointer_info.count, 2)
    expect_value(t, c1.pointer_info.const, false)
    expect_value(t, c1.pointer_info.restrict, true)

    arr := variables[6].(Var)
    expect_value(t, arr.name.?, "arr")
    expect_value(t, arr.pointer_info.count, 1)
    expect_value(t, arr.pointer_info.const, true)
    expect_value(t, arr.pointer_info.child.count, 1)
    expect_value(t, arr.pointer_info.child.const, false)

    arr = variables[7].(Var)
    expect_value(t, arr.name.?, "arr1")
    expect_value(t, arr.pointer_info.count, 1)
    expect_value(t, arr.pointer_info.const, true)
    expect_value(t, arr.pointer_info.child.count, 1)
    expect_value(t, arr.pointer_info.child.const, true)
    expect_value(t, arr.pointer_info.child.child.count, 2)
    expect_value(t, arr.pointer_info.child.child.const, false)
}

@(test)
test_array :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/array.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(functions), 0) {
        return
    }
    if !expect_value(t, len(typedefs), 0) {
        return
    }
    if !expect_value(t, len(variables), 5) {
        return
    }

    a := variables[0].(Var)
    expect_value(t, a.name.?, "a")
    expect_value(t, len(a.array_info), 1)
    expect_value(t, a.array_info[0].(i64), 5)
    expect_value(t, a.type.(BuiltinType), BuiltinType.int)

    b := variables[1].(Var)
    expect_value(t, b.name.?, "b")
    expect_value(t, len(b.array_info), 2)
    expect_value(t, b.array_info[0].(i64), 2)
    expect_value(t, b.array_info[1].(i64), 1)
    expect_value(t, b.type.(BuiltinType), BuiltinType.int)

    c := variables[2].(Var)
    expect_value(t, c.name.?, "c")
    expect_value(t, len(c.array_info), 3)
    expect_value(t, c.array_info[0].(i64), 3)
    expect_value(t, c.array_info[1].(i64), 2)
    expect_value(t, c.array_info[2].(i64), 1)
    expect_value(t, c.type.(BuiltinType), BuiltinType.int)

    v := variables[3].(Var)
    expect_value(t, v.name.?, "v")
    expect_value(t, len(v.array_info), 1)
    expect_value(t, v.array_info[0], nil)
    expect_value(t, v.pointer_info.count, 1)

    ptr := variables[4].(Var)
    expect_value(t, ptr.name.?, "ptr")
    expect_value(t, len(ptr.array_info), 1)
    expect_value(t, ptr.array_info[0].(i64), 12)
    expect_value(t, ptr.pointer_info.count, 1)
}

@(test)
test_gnu_attribute :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/gnu_attribute.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser


    if !expect_value(t, len(functions), 0) {
        return
    }
    if !expect_value(t, len(typedefs), 4) {
        return
    }
    if !expect_value(t, len(variables), 2) {
        return
    }

    expect_value(t, typedefs[0].(Var).type.(Enum).name.?, "a")
    expect_value(t, typedefs[1].(Var).type.(Struct).name.?, "s")
    expect_value(t, typedefs[2].(Var).type.(Enum).name.?, "e")
    expect_value(t, typedefs[3].(Var).name.?, "register_t")
    expect_value(t, variables[0].(Var).type.(BuiltinType), BuiltinType.int)
    expect_value(t, variables[0].(Var).name.?, "i")
    expect_value(t, variables[1].(Var).name.?, "a")
}

@(test)
test_macros :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/macros.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(functions), 3) {
        return
    }
    if !expect_value(t, len(typedefs), 0) {
        return
    }
    if !expect_value(t, len(variables), 0) {
        return
    }
    if !expect_value(t, om.length(macros), 19) {
        return
    }

    expect_value(t, om.get(macros, "A").(MacroVar).name, "A")
    expect_value(t, om.get(macros, "B").(MacroVar).name, "B")
    expect_value(t, om.get(macros, "C").(MacroVar).name, "C")
    expect_value(t, om.get(macros, "PLAT").(MacroVar).name, "PLAT")
    expect_value(t, om.get(macros, "A").(MacroVar).value.?, "1")
    expect_value(t, om.get(macros, "B").(MacroVar).value.?, "2")
    expect_value(t, om.get(macros, "C").(MacroVar).value.?, "3")
    expect_value(t, om.get(macros, "PLAT").(MacroVar).value.?, "posix")

    expect_value(
        t,
        om.get(macros, "GLEW_GET_FUNC").(MacroFunc).name,
        "GLEW_GET_FUNC",
    )
    expect_value(
        t,
        len(om.get(macros, "GLEW_GET_FUNC").(MacroFunc).parameters),
        1,
    )
    expect_value(
        t,
        om.get(macros, "GLEW_GET_FUNC").(MacroFunc).parameters[0],
        "x",
    )
    expect_value(t, len(om.get(macros, "GLEW_GET_FUNC").(MacroFunc).body), 1)
    expect_value(
        t,
        om.get(macros, "GLEW_GET_FUNC").(MacroFunc).body[0].(MacroInsertion).parameter,
        0,
    )

    expect_value(
        t,
        om.get(macros, "glClearColor").(MacroVar).name,
        "glClearColor",
    )
    expect_value(
        t,
        om.get(macros, "glClearColor").(MacroVar).value.?,
        "__glewClearColor",
    )

    expect_value(
        t,
        om.get(macros, "SUPER_FUNC").(MacroFunc).name,
        "SUPER_FUNC",
    )
    expect_value(
        t,
        len(om.get(macros, "SUPER_FUNC").(MacroFunc).parameters),
        3,
    )
    expect_value(
        t,
        om.get(macros, "SUPER_FUNC").(MacroFunc).parameters[0],
        "x",
    )
    expect_value(
        t,
        om.get(macros, "SUPER_FUNC").(MacroFunc).parameters[1],
        "y",
    )
    expect_value(
        t,
        om.get(macros, "SUPER_FUNC").(MacroFunc).parameters[2],
        "z",
    )
    expect_value(t, len(om.get(macros, "SUPER_FUNC").(MacroFunc).body), 10)

    exe_call := MacroFuncCall {
        macro_func = om.get(macros, "SUPER_FUNC").(MacroFunc),
        args       = [dynamic]string{"\"Value0\"", "\"Value1\"", "\"Value2\""},
    }
    defer delete(exe_call.args)

    exe: string = ---
    exe, err = evaluate_macro_func_call(
        exe_call,
        macros,
        includes[:],
        runtime.arena_allocator(&parser.arena),
    )
    if !expect_value(t, err, nil) do return

    expect_value(
        t,
        exe,
        `printf("x=%s y=%s z=%s\n", "Value0", "Value1", "Value2")`,
    )

    cp := om.get(macros, "glCreateProgram").(MacroVar)
    expect_value(t, cp.name, "glCreateProgram")
    expect_value(t, cp.value.?, "__glewCreateProgram")

    dv := om.get(macros, "DO_VAR").(MacroVar)
    expect_value(t, dv.name, "DO_VAR")
    expect_value(
        t,
        dv.value.?,
        `(ZERO ="Hello", (FIRST = "World", SECOND= "Bye"))`,
    )

    mv := om.get(macros, "MULTI_VAR").(MacroVar)
    expect_value(t, mv.name, "MULTI_VAR")
    expect_value(
        t,
        mv.value.?,
        "printf(x + y, y + x) sprintf(z + x, y + z) PRINT0(x, z) PRINT3(x,u,i)",
    )

    av := om.get(macros, "ALSO_VAR").(MacroVar)
    expect_value(t, av.name, "ALSO_VAR")
    expect_value(t, av.value.?, "printf(a + printf(a, printf(u, i)), b)")

    ry := om.get(macros, "REC_VAR").(MacroVar)
    expect_value(t, ry.name, "REC_VAR")
    expect_value(t, ry.value.?, "(5 + value)")

    rf := om.get(macros, "REC_FUNC").(MacroFunc)
    expect_value(t, len(rf.parameters), 1)
    expect_value(t, rf.parameters[0], "x")
    expect_value(t, len(rf.body), 5)
    expect_value(t, rf.body[3].(MacroInsertion).parameter, 0)

    rc := om.get(macros, "RECY").(MacroVar)
    expect_value(t, rc.value.?, "5")

    expect_value(
        t,
        om.get(macros, "SLASHY").(MacroVar).value.?,
        "COUNT 1 2 3 4",
    )
}

@(test)
test_prepreprocess :: proc(t: ^testing.T) {
    using testing

    out_f, os_err := os.open(
        "test_data/macros.ppp.h",
        os.O_CREATE | os.O_WRONLY,
        0o644,
    )
    if !expect_value(t, os_err, 0) {
        return
    }
    defer os.close(out_f)

    err := prepreprocess_file(
        "test_data/macros.h",
        os.stream_from_handle(out_f),
    )
    if !expect_value(t, err, nil) do return
}

when ODIN_OS == .Windows {
    TEST_PREPROCESS_EXPECTED :: "int posix_func(int a, int b);\r\nvoid __glewCreateProgram();\r\nvoid __glewClearColor();\r\n"
} else {
    TEST_PREPROCESS_EXPECTED :: "int posix_func(int a, int b);\nvoid __glewCreateProgram();\nvoid __glewClearColor();\n"
}

@(test)
test_preprocess :: proc(t: ^testing.T) {
    using testing

    out_f, os_err := os.open(
        "test_data/macros.pp.h",
        os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, 0) {
        return
    }
    defer os.close(out_f)

    input: os.Handle = ---
    input, os_err = os.open("test_data/macros.h")
    if !expect_value(t, os_err, 0) do return

    err := preprocess_file(
        os.stream_from_handle(input),
        os.stream_from_handle(out_f),
    )
    if !expect_value(t, err, nil) do return

    data, ok := os.read_entire_file("test_data/macros.pp.h")
    if !expect(t, ok) do return
    defer delete(data)

    if !expect_value(t, string(data), TEST_PREPROCESS_EXPECTED) {
        expect_data := transmute([]byte)string(TEST_PREPROCESS_EXPECTED)
        fmt.eprintfln("REAL    : {}\nEXPECTED: {}", data, expect_data)
    }
}

@(test)
test_ppp_and_pp :: proc(t: ^testing.T) {
    using testing

    ppp_buffer: bytes.Buffer
    defer bytes.buffer_destroy(&ppp_buffer)

    if err := prepreprocess_file("test_data/macros.h", bytes.buffer_to_stream(&ppp_buffer)); !expect_value(t, err, nil) do return

    pp_reader: bytes.Reader
    bytes.reader_init(&pp_reader, bytes.buffer_to_bytes(&ppp_buffer))

    out, os_err := os.open(
        "test_data/macros.ppp-pp.h",
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, 0) do return
    defer os.close(out)

    if err := preprocess_file(bytes.reader_to_stream(&pp_reader), os.stream_from_handle(out)); !expect_value(t, err, nil) do return
}

@(test)
test_include :: proc(t: ^testing.T) {
    using testing

    parser, err := parse_file("test_data/include.h")
    defer destroy_parser(&parser)
    if !expect_value(t, err, nil) do return

    using parser

    if !expect_value(t, len(variables), 0) {
        return
    }
    if !expect_value(t, len(includes), 1) {
        return
    }
    if !expect_value(t, len(includes[0].variables), 3) {
        return
    }

    expect_value(t, includes[0].variables[0].(Var).name.?, "a")
    expect_value(t, includes[0].variables[1].(Var).name.?, "b")
    expect_value(t, includes[0].variables[2].(Var).name.?, "xyz")
}

@(test)
test_expression_tokenizer :: proc(t: ^testing.T) {
    using testing

    {
        EXPR :: "15"

        n, idx, ok := expr_parse_number_token(EXPR)
        expect_value(t, n, 15)
        expect_value(t, idx, 2)
        expect_value(t, ok, true)
    }

    {
        EXPR :: "(1 + 5) * 55"

        etz := create_expression_tokenizer(EXPR)

        expect_value(t, expr_next_token(&etz), cast(OpenParenthesis)0)
        expect_value(t, expr_next_token(&etz), cast(NumberExpression)1)
        expect_value(t, expr_next_token(&etz), Operator.Add)
        expect_value(t, expr_next_token(&etz), cast(NumberExpression)5)
        expect_value(t, expr_next_token(&etz), ExpressionEnd.Parenthesis)
        expect_value(t, expr_next_token(&etz), Operator.Mul)
        expect_value(t, expr_next_token(&etz), cast(NumberExpression)55)
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }

    {
        EXPR :: "0x1A5F7Bdbf"

        etz := create_expression_tokenizer(EXPR)

        expect_value(
            t,
            expr_next_token(&etz),
            cast(NumberExpression)0x1A5F7Bdbf,
        )
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }

    {
        EXPR :: "-0xff"

        etz := create_expression_tokenizer(EXPR)

        expect_value(t, expr_next_token(&etz), cast(NumberExpression)-0xff)
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }

    {
        EXPR :: "120-100"

        etz := create_expression_tokenizer(EXPR)

        expect_value(t, expr_next_token(&etz), cast(NumberExpression)120)
        expect_value(t, expr_next_token(&etz), Operator.Sub)
        expect_value(t, expr_next_token(&etz), cast(NumberExpression)100)
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }

    {
        EXPR :: "120--100"

        etz := create_expression_tokenizer(EXPR)

        expect_value(t, expr_next_token(&etz), cast(NumberExpression)120)
        expect_value(t, expr_next_token(&etz), Operator.Sub)
        expect_value(t, expr_next_token(&etz), cast(NumberExpression)-100)
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }

    {
        EXPR :: "0b11011000111011101"

        etz := create_expression_tokenizer(EXPR)

        expect_value(
            t,
            expr_next_token(&etz),
            cast(NumberExpression)0b11011000111011101,
        )
        expect_value(t, expr_next_token(&etz), ExpressionEnd.EOF)
    }
}

@(test)
test_const_folding :: proc(t: ^testing.T) {
    using testing

    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

    {
        EXPR :: "3 + 4 * 5"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 23)
    }

    {
        EXPR :: "3 * 4 + 5"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 17)
    }

    {
        EXPR :: "3 * (4 + 5)"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 27)
    }

    {
        EXPR :: "((((3)))) * (4 + 5) + 6 + 7 + 20 / 10 * 8"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 56)
    }

    {
        EXPR :: "20 * 10 / 5"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 40)
    }

    {
        EXPR :: "25 - 10 + 5"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 20)
    }

    {
        EXPR :: "25 - ((10 + 5))"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 10)
    }

    {
        EXPR :: "2500 / 100 / 5"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 5)
    }

    {
        EXPR :: "20 * 10 / 20"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 10)
    }

    {
        EXPR :: "1 << 2"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 4)
    }

    {
        EXPR :: "(1 << 0)|(1 << 1)|(1 << 2)|(1 << 3)"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 0xf)
    }

    {
        EXPR :: "0b000111 ^ 0b010101"

        expr, ok := parse_expression(EXPR)
        if !expect(t, ok) do return

        expect_value(t, evaluate_expression(expr), 0b010010)
    }
}
