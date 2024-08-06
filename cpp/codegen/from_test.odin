package cpp_codegen

// import "core:fmt"
// import "core:slice"
import "core:testing"
import om "root:ordered_map"
import "root:runic"

@(test)
test_cpp_builtin :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libbuiltin.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/builtin.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 32)
    expect_value(t, om.length(rs.symbols), 9)

    rab := om.get(rs.symbols, "rab")
    rab_type := rab.value.(runic.Type)
    expect_value(t, rab_type.spec.(runic.Builtin), runic.Builtin.SInt32)
    expect_value(t, rab_type.pointer_info.count, 2)

    zab := om.get(rs.symbols, "zab")
    zab_type := zab.value.(runic.Type)
    expect_value(t, zab_type.spec.(runic.Builtin), runic.Builtin.SInt32)
    expect_value(t, zab.value.(runic.Type).pointer_info.count, 1)
    expect_value(t, zab.value.(runic.Type).array_info[0].size.(u64), 2)
}

@(test)
test_cpp_pointer :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libpointer.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/pointer.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.symbols), 9)

    arr := om.get(rs.symbols, "arr")
    arr_type := arr.value.(runic.Type)

    expect_value(t, arr_type.spec.(runic.Builtin), runic.Builtin.String)
    expect_value(t, arr_type.read_only, true)
    expect_value(t, arr_type.pointer_info.count, 1)
    expect_value(t, arr_type.pointer_info.read_only, true)
}

@(test)
test_cpp_array :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libarray.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/array.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.symbols), 5)

    ptr := om.get(rs.symbols, "ptr")
    ptr_type := ptr.value.(runic.Type)

    expect_value(t, ptr_type.spec.(runic.Builtin), runic.Builtin.RawPtr)
    expect_value(t, len(ptr_type.array_info), 1)
    expect_value(t, ptr_type.array_info[0].size.(u64), 12)

    c := om.get(rs.symbols, "c")
    c_type := c.value.(runic.Type)

    expect_value(t, len(c_type.array_info), 3)
    expect_value(t, c_type.array_info[0].size.(u64), 1)
    expect_value(t, c_type.array_info[1].size.(u64), 2)
    expect_value(t, c_type.array_info[2].size.(u64), 3)
}

@(test)
test_cpp_struct :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libstruct.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/struct.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 7)

    abc_t := om.get(rs.types, "abc_t")
    abc_struct := abc_t.spec.(runic.Struct)

    expect_value(t, len(abc_struct.members), 4)
    expect_value(t, abc_struct.members[0].name, "a")
    expect_value(t, abc_struct.members[1].name, "b")
    expect_value(t, abc_struct.members[2].name, "c")
    expect_value(t, abc_struct.members[3].name, "yzg")

    my_struct := om.get(rs.types, "my_struct")
    my_struct_s := my_struct.spec.(runic.Struct)

    expect_value(t, len(my_struct_s.members), 2)
    expect_value(t, my_struct_s.members[0].name, "x")
    expect_value(t, my_struct_s.members[1].name, "y")

    ss_t := om.get(rs.types, "_sszu_")
    ss_t_struct := ss_t.spec.(runic.Struct)

    expect_value(t, len(ss_t_struct.members), 1)
    expect_value(t, ss_t_struct.members[0].name, "x")

    sszu := om.get(rs.types, "ss_t")
    expect_value(t, sszu.spec.(string), "_sszu_")

    w_ctx, ok := om.get(rs.types, "wl_context")
    expect(t, ok)

    w_ctx_s := w_ctx.spec.(runic.Struct)
    expect_value(t, len(w_ctx_s.members), 1)
    expect_value(t, w_ctx_s.members[0].name, "window")

    window := w_ctx_s.members[0].type.spec.(string)
    expect_value(t, window, "window_struct_anon_1")

    window_struct := om.get(rs.types, "window_struct_anon_1")
    window_s := window_struct.spec.(runic.Struct)

    x := window_s.members[2].type.spec.(string)
    expect_value(t, x, "x_struct_anon_0")
}

@(test)
test_cpp_enum :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libenum.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/enum.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 6)
    expect_value(t, om.length(rs.symbols), 1)

    abc := om.get(rs.types, "abc_enum")
    abc_enum := abc.spec.(runic.Enum)

    expect_value(t, len(abc_enum.entries), 3)
    expect_value(t, abc_enum.entries[0].name, "A")
    expect_value(t, abc_enum.entries[1].name, "B")
    expect_value(t, abc_enum.entries[2].name, "C")
    expect_value(t, abc_enum.type, runic.Builtin.UInt32)

    expect_value(t, abc_enum.entries[0].value.(i64), 0)
    expect_value(t, abc_enum.entries[1].value.(i64), 1)
    expect_value(t, abc_enum.entries[2].value.(i64), 2)

    cba := om.get(rs.types, "cba_enum")
    cba_enum := cba.spec.(runic.Enum)

    expect_value(t, len(cba_enum.entries), 3)
    expect_value(t, cba_enum.entries[0].name, "M")
    expect_value(t, cba_enum.entries[1].name, "H")
    expect_value(t, cba_enum.entries[2].name, "N")
    expect_value(t, cba_enum.type, runic.Builtin.UInt32)

    expect_value(t, cba_enum.entries[0].value.(i64), 0)
    expect_value(t, cba_enum.entries[1].value.(i64), 1)
    expect_value(t, cba_enum.entries[2].value.(i64), 2)


    constis := om.get(rs.types, "constants")
    con_enum := constis.spec.(runic.Enum)

    expect_value(t, len(con_enum.entries), 7)
    expect_value(t, con_enum.entries[0].name, "X")
    expect_value(t, con_enum.entries[1].name, "Y")
    expect_value(t, con_enum.entries[2].name, "Z")
    expect_value(t, con_enum.entries[3].name, "W")
    expect_value(t, con_enum.entries[4].name, "Apple")
    expect_value(t, con_enum.entries[5].name, "Banana")
    expect_value(t, con_enum.entries[6].name, "Calculate")
    expect_value(t, con_enum.type, runic.Builtin.SInt32)

    expect_value(t, con_enum.entries[0].value.(i64), 1)
    expect_value(t, con_enum.entries[1].value.(i64), 5)
    expect_value(t, con_enum.entries[2].value.(i64), 8)
    expect_value(t, con_enum.entries[3].value.(i64), -7)
    expect_value(t, con_enum.entries[4].value.(i64), 789)
    expect_value(t, con_enum.entries[5].value.(i64), 90)
    expect_value(t, con_enum.entries[6].value.(i64), (70 * 4 + 9) / 6 % 7)
}

@(test)
test_cpp_union :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libunion.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/union.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 3)

    my_union := om.get(rs.types, "my_union")
    my := my_union.spec.(runic.Union)

    expect_value(t, len(my.members), 2)
    expect_value(t, my.members[0].name, "zuz")
    expect_value(t, my.members[1].name, "uzu")

    other_union := om.get(rs.types, "other_union")
    other := other_union.spec.(runic.Union)

    expect_value(t, len(other.members), 2)
    expect_value(t, other.members[0].name, "floaties")
    expect_value(t, other.members[1].name, "inties")

    floaties := other.members[0].type.spec.(string)
    expect_value(t, floaties, "floaties_struct_anon_0")
}

@(test)
test_cpp_attribute :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libattribute.so"}},
        headers =  {
            d = {runic.Platform{.Any, .Any} = {"test_data/gnu_attribute.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 4)
    expect_value(t, om.length(rs.symbols), 2)
}

@(test)
test_cpp_include :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libinclude.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/include.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 0)
    expect_value(t, om.length(rs.symbols), 0)
    expect_value(t, om.length(rs.constants), 0)
}

@(test)
test_cpp_elaborated :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libelaborated.so"}},
        headers =  {
            d = {runic.Platform{.Any, .Any} = {"test_data/elaborated.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 9)
    expect_value(t, om.length(rs.symbols), 4)

    pack := om.get(rs.symbols, "pack")
    pack_type := pack.value.(runic.Type).spec.(string)

    expect_value(t, pack_type, "big_package")

    bag := om.get(rs.symbols, "bag")
    bag_type := bag.value.(runic.Type).spec.(string)

    expect_value(t, bag_type, "small_package")

    packer := om.get(rs.symbols, "packer")
    packer_type := packer.value.(runic.Type).spec.(string)

    expect_value(t, packer_type, "packer_struct_anon_1")

    tree := om.get(rs.symbols, "tree")
    tree_type := tree.value.(runic.Type)

    _, ok := tree_type.spec.(string)
    expect(t, ok)

    expect(t, tree_type.read_only)

    small_package := om.get(rs.types, "small_package")
    small := small_package.spec.(runic.Struct)

    expect_value(t, len(small.members), 2)
    expect_value(t, small.members[1].type.spec.(string), "wisdom_t")

    unific := om.get(rs.types, "unific")
    uni := unific.spec.(runic.Union)

    expect_value(t, len(uni.members), 4)
    expect_value(t, uni.members[0].type.spec.(string), "big_package")
    expect_value(t, uni.members[1].type.spec.(string), "small_package")
    expect_value(t, uni.members[2].type.spec.(string), "w_struct_anon_0")
    expect_value(t, uni.members[3].type.spec.(string), "zuz")

    zuz := om.get(rs.types, "zuz")
    zuz_type := zuz.spec.(runic.Struct)

    expect_value(t, len(zuz_type.members), 1)

    wisdom_t := om.get(rs.types, "wisdom_t")
    wisdom := wisdom_t.spec.(runic.Builtin)
    expect_value(t, wisdom, runic.Builtin.SInt64)
}
@(test)
test_cpp_function :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libfunction.so"}},
        headers =  {
            d = {runic.Platform{.Any, .Any} = {"test_data/function.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 1)
    expect_value(t, om.length(rs.symbols), 8)

    hello_world := om.get(rs.symbols, "hello_world")
    hw := hello_world.value.(runic.Function)

    expect_value(t, hw.return_type.spec.(runic.Builtin), runic.Builtin.Void)
    expect_value(t, len(hw.parameters), 0)
    expect(t, !hw.variadic)

    foo := om.get(rs.symbols, "foo")
    fooo := foo.value.(runic.Function)

    expect_value(t, fooo.return_type.spec.(runic.Builtin), runic.Builtin.Void)
    expect_value(t, len(fooo.parameters), 3)
    expect_value(t, fooo.parameters[1].name, "b")

    strcpy := om.get(rs.symbols, "strcpy")
    spy := strcpy.value.(runic.Function)

    expect_value(t, len(spy.parameters), 1)
    expect_value(t, spy.parameters[0].name, "param0")
    expect_value(
        t,
        spy.parameters[0].type.spec.(runic.Builtin),
        runic.Builtin.String,
    )
    expect_value(t, spy.parameters[0].type.read_only, true)

    baz := om.get(rs.symbols, "baz")
    bz := baz.value.(runic.Function)

    expect_value(t, bz.parameters[0].type.spec.(string), "x_struct_anon_0")
}

@(test)
test_cpp_function_pointer :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libfunction_pointer.so"}},
        headers =  {
            d =  {
                runic.Platform{.Any, .Any} = {"test_data/function_pointer.h"},
            },
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 4)
    expect_value(t, om.length(rs.symbols), 6)

    hello := om.get(rs.symbols, "hello")
    hell := hello.value.(runic.Type).spec.(runic.FunctionPointer)

    expect_value(t, len(hell.parameters), 0)
    expect_value(t, hell.return_type.spec.(runic.Builtin), runic.Builtin.Void)

    bye := om.get(rs.symbols, "bye")
    by := bye.value.(runic.Type).spec.(runic.FunctionPointer)

    expect_value(t, len(by.parameters), 4)
    expect_value(t, by.parameters[3].type.spec.(string), "param3_struct_anon_0")

    consty := om.get(rs.types, "consty")
    expect_value(t, consty.read_only, true)
}

@(test)
test_cpp_macros :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libmacros.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/macros.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(runic.platform_from_host(), "/inline", rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    if !expect_value(t, om.length(rs.constants), 12) do return

    A := om.get(rs.constants, "A")
    expect_value(t, A.value.(i64), 1)
    B := om.get(rs.constants, "B")
    expect_value(t, B.value.(i64), 2)
    C := om.get(rs.constants, "C")
    expect_value(t, C.value.(i64), 3)

    glCP := om.get(rs.constants, "glCreateProgram")
    expect_value(t, glCP.value.(string), "__glewCreateProgram")

    slashy := om.get(rs.constants, "SLASHY")
    expect_value(t, slashy.value.(string), "COUNT 1 2 3 4")
}
