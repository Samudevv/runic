package cpp_codegen

import "core:testing"
import om "root:ordered_map"
import "root:runic"

when ODIN_OS == .Windows {
    RUNESTONE_TEST_PATH :: "C:\\inline"
} else {
    RUNESTONE_TEST_PATH :: "/inline"
}

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

    rs, err := generate_runestone({.Linux, .arm64}, RUNESTONE_TEST_PATH, rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 34)
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

    not_string := om.get(rs.types, "not_string")
    expect_value(t, not_string.spec.(runic.Builtin), runic.Builtin.SInt8)
    expect_value(t, not_string.pointer_info.count, 1)

    is_a_string := om.get(rs.types, "is_a_string")
    expect_value(t, is_a_string.spec.(runic.Builtin), runic.Builtin.String)
    expect_value(t, is_a_string.pointer_info.count, 0)

    l := om.get(rs.types, "l")
    expect_value(t, l.spec.(runic.Builtin), runic.Builtin.SInt32)
    m := om.get(rs.types, "m")
    expect_value(t, m.spec.(runic.Builtin), runic.Builtin.SInt32)
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

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
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

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
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

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 14)

    abc_t := om.get(rs.types, "abc_t")
    abc_struct := abc_t.spec.(runic.Struct)

    expect_value(t, len(abc_struct.members), 4)
    expect_value(t, abc_struct.members[0].name, "a")
    expect_value(t, abc_struct.members[1].name, "b")
    expect_value(t, abc_struct.members[2].name, "c")
    expect_value(t, abc_struct.members[3].name, "yzg")

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

    wl_output := om.get(rs.types, "wl_output")
    expect_value(t, wl_output.spec.(runic.Builtin), runic.Builtin.RawPtr)
    expect_value(
        t,
        om.get(rs.types, "mega_type").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    expect_value(
        t,
        om.get(rs.types, "non_exist").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    expect_value(
        t,
        om.get(rs.types, "super_union").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    expect_value(t, om.get(rs.types, "super_type").spec.(string), "mega_type")
    expect_value(
        t,
        om.get(rs.types, "tippy_toes").spec.(runic.Struct).members[0].type.spec.(string),
        "non_exist",
    )

    my_struct := om.get(rs.types, "my_struct")
    expect_value(t, my_struct.spec.(runic.Builtin), runic.Builtin.Untyped)

    byte_array := om.get(rs.types, "byte_array").spec.(runic.Struct)
    expect_value(t, len(byte_array.members), 3)
    ba_x := byte_array.members[0]
    ba_y := byte_array.members[1]
    ba_b := byte_array.members[2]
    expect_value(t, ba_x.type.spec.(runic.Builtin), runic.Builtin.UInt8)
    expect_value(t, ba_y.type.spec.(runic.Builtin), runic.Builtin.UInt8)
    expect_value(t, ba_b.type.spec.(runic.Builtin), runic.Builtin.UInt8)
    expect_value(t, ba_x.type.array_info[0].size.(u64), 1)
    expect_value(t, ba_y.type.array_info[0].size.(u64), 2)
    expect_value(t, ba_b.type.array_info[0].size.(u64), 3)
}

@(test)
test_cpp_enum :: proc(t: ^testing.T) {
    using testing

    host := runic.platform_from_host()

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libenum.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/enum.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
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
    if host.os == .Windows {
        expect_value(t, abc_enum.type, runic.Builtin.SInt32)
    } else {
        expect_value(t, abc_enum.type, runic.Builtin.UInt32)
    }

    expect_value(t, abc_enum.entries[0].value.(i64), 0)
    expect_value(t, abc_enum.entries[1].value.(i64), 1)
    expect_value(t, abc_enum.entries[2].value.(i64), 2)

    cba := om.get(rs.types, "cba_enum")
    cba_enum := cba.spec.(runic.Enum)

    expect_value(t, len(cba_enum.entries), 3)
    expect_value(t, cba_enum.entries[0].name, "M")
    expect_value(t, cba_enum.entries[1].name, "H")
    expect_value(t, cba_enum.entries[2].name, "N")
    if host.os == .Windows {
        expect_value(t, cba_enum.type, runic.Builtin.SInt32)
    } else {
        expect_value(t, cba_enum.type, runic.Builtin.UInt32)
    }

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

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
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
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/gnu_attribute.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
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

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    runic.from_postprocess_runestone(&rs, rf)

    rf.load_all_includes = runic.make_platform_value(bool)
    defer delete(rf.load_all_includes.d)
    rf.load_all_includes.d[{.Any, .Any}] = true

    rs_all, err_all := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err_all, nil) do return
    defer runic.runestone_destroy(&rs_all)

    runic.from_postprocess_runestone(&rs_all, rf)

    expect_value(t, om.length(rs.types), 4)
    expect_value(t, om.length(rs.symbols), 0)
    expect_value(t, om.length(rs.constants), 0)

    if callbacker_type, ok := om.get(rs.types, "callbacker"); expect(t, ok) {
        if callbacker, spec_ok := callbacker_type.spec.(runic.Struct);
           expect(t, spec_ok) {
            if expect_value(t, len(callbacker.members), 1) {
                if cb, cb_ok := callbacker.members[0].type.spec.(string);
                   expect(t, cb_ok) {
                    expect_value(t, cb, "callback_proc")
                }
            }
        }
    }

    if callback_proc_type, ok := om.get(rs.types, "callback_proc");
       expect(t, ok) {
        if callback_proc, spec_ok := callback_proc_type.spec.(runic.FunctionPointer);
           expect(t, spec_ok) {
            expect_value(t, len(callback_proc.parameters), 2)
        }
    }

    expect(t, om.contains(rs.types, "lower_t"))
    expect(t, om.contains(rs.types, "below_t"))

    expect_value(t, om.length(rs_all.types), 4)
    expect_value(t, om.length(rs_all.symbols), 3)
    expect_value(t, om.length(rs_all.constants), 1)

    expect(t, om.contains(rs_all.symbols, "a"))
    expect(t, om.contains(rs_all.symbols, "b"))
    expect(t, om.contains(rs_all.symbols, "xyz"))
    expect(t, om.contains(rs_all.types, "callback_proc"))
    expect(t, om.contains(rs_all.types, "callbacker"))
    expect(t, om.contains(rs_all.types, "lower_t"))
    expect(t, om.contains(rs_all.types, "below_t"))

    expect_value(t, om.get(rs_all.types, "lower_t").spec.(string), "below_t")
    expect_value(
        t,
        om.get(rs_all.types, "below_t").spec.(runic.Struct).members[0].name,
        "a",
    )

    consta := om.get(rs_all.constants, "INCLUDE_CHILD")
    expect_value(t, consta.value.(i64), 15)


}

@(test)
test_cpp_system_include :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libsystem_include.so"}},
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/system_include.h"}},
        },
        flags = {
            d = {
                runic.Platform{.Any, .Any} = {
                    "-Itest_data/the_system",
                    "-Itest_data/third_party",
                    "-Itest_data/other_system",
                },
            },
        },
        extern = {
            "test_data/the_system/my_system.h",
            "test_data/third_party/third_party.h",
            "test_data/other_system/also_my_system.h",
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)
    defer delete(rf.flags.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)
    runic.from_postprocess_runestone(&rs, rf)

    expect_value(t, om.length(rs.types), 3)
    expect_value(t, om.length(rs.externs), 6)
    expect_value(t, om.length(rs.symbols), 4)

    expect_value(
        t,
        om.get(rs.types, "from_main").spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    expect_value(
        t,
        om.get(rs.types, "main_struct").spec.(runic.Struct).members[0].type.spec.(runic.ExternType),
        "from_system",
    )
    expect_value(
        t,
        om.get(rs.types, "from_other_system").spec.(runic.ExternType),
        "sysi",
    )
    expect(t, !om.contains(rs.types, "feature_t"))

    expect_value(
        t,
        om.get(rs.externs, "from_system").spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    expect_value(
        t,
        om.get(rs.externs, "ant").spec.(runic.Builtin),
        runic.Builtin.Float32,
    )
    expect_value(
        t,
        om.get(rs.externs, "sysi").spec.(runic.Builtin),
        runic.Builtin.Float64,
    )
    expect(t, !om.contains(rs.externs, "also_from_system"))
    expect(t, om.contains(rs.externs, "feature_t"))
    expect_value(
        t,
        om.get(rs.externs, "donkey_t").spec.(runic.Struct).members[1].name,
        "oink",
    )
    expect_value(
        t,
        om.get(rs.externs, "donkey_t").spec.(runic.Struct).members[1].type.spec.(runic.ExternType),
        "oink_func_ptr_anon_0",
    )
    oink := om.get(rs.externs, "oink_func_ptr_anon_0").spec.(runic.FunctionPointer)
    expect_value(t, len(oink.parameters), 2)
    expect_value(t, oink.parameters[0].name, "volume")
    expect_value(t, oink.parameters[1].name, "speed")

    expect_value(
        t,
        om.get(rs.symbols, "part").value.(runic.Function).parameters[1].type.spec.(runic.ExternType),
        "ant",
    )
    expect_value(
        t,
        om.get(rs.symbols, "make_feature").value.(runic.Function).parameters[0].type.spec.(runic.ExternType),
        "feature_t",
    )
    expect_value(
        t,
        om.get(rs.symbols, "new_donkey").value.(runic.Function).return_type.spec.(runic.ExternType),
        "donkey_t",
    )
}

@(test)
test_cpp_elaborated :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libelaborated.so"}},
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/elaborated.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)
    runic.from_postprocess_runestone(&rs, rf)

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
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/function.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 1)
    expect_value(t, om.length(rs.symbols), 9)

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

    variadic := om.get(rs.symbols, "variadic_func").value.(runic.Function)
    expect_value(t, len(variadic.parameters), 1)
    expect_value(t, variadic.variadic, true)
}

@(test)
test_cpp_function_pointer :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libfunction_pointer.so"}},
        headers = {
            d = {
                runic.Platform{.Any, .Any} = {"test_data/function_pointer.h"},
            },
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 8)
    expect_value(t, om.length(rs.symbols), 6)

    hello := om.get(rs.symbols, "hello")
    hell := hello.value.(runic.Type).spec.(runic.FunctionPointer)

    expect_value(t, len(hell.parameters), 0)
    expect_value(t, hell.return_type.spec.(runic.Builtin), runic.Builtin.Void)

    bye := om.get(rs.symbols, "bye")
    by := bye.value.(runic.Type).spec.(runic.FunctionPointer)

    expect_value(t, len(by.parameters), 4)
    expect_value(t, by.parameters[3].type.spec.(string), "s_struct_anon_0")

    consty := om.get(rs.types, "consty")
    coy := consty.spec.(runic.FunctionPointer)
    expect_value(t, consty.read_only, true)
    expect_value(t, len(coy.parameters), 2)
    expect_value(t, coy.parameters[0].name, "a")
    expect_value(t, coy.parameters[1].name, "b")

    signal_func := om.get(rs.symbols, "signal")
    signal_rt_name, signal_rt_is_fp := signal_func.value.(runic.Function).return_type.spec.(string)
    expect(t, signal_rt_is_fp)

    signal_rt := om.get(rs.types, signal_rt_name)
    _, signal_rt_is_fp = signal_rt.spec.(runic.FunctionPointer)
    expect(t, signal_rt_is_fp)

    signal_rt_name, signal_rt_is_fp =
    signal_func.value.(runic.Function).parameters[1].type.spec.(string)
    expect(t, signal_rt_is_fp)

    signal_rt = om.get(rs.types, signal_rt_name)
    _, signal_rt_is_fp = signal_rt.spec.(runic.FunctionPointer)
    expect(t, signal_rt_is_fp)

    create_window_t := om.get(rs.types, "create_window")
    create_window := create_window_t.spec.(runic.FunctionPointer)

    expect_value(t, len(create_window.parameters), 3)
    expect_value(t, create_window.parameters[0].name, "name")
    expect_value(t, create_window.parameters[1].name, "width")
    expect_value(t, create_window.parameters[2].name, "height")

    variadic := om.get(rs.types, "variadic_func").spec.(runic.FunctionPointer)
    expect_value(t, len(variadic.parameters), 1)
    expect_value(t, variadic.variadic, true)
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

    plat := runic.Platform{.Windows, .x86_64}

    rs, err := generate_runestone(plat, RUNESTONE_TEST_PATH, rf)
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    if !expect_value(t, om.length(rs.constants), 10) do return

    A := om.get(rs.constants, "A")
    expect_value(t, A.value.(i64), 1)
    B := om.get(rs.constants, "B")
    expect_value(t, B.value.(i64), 2)
    C := om.get(rs.constants, "C")
    expect_value(t, C.value.(i64), 3)

    expect(t, !om.contains(rs.constants, "glCreateProgram"))

    slashy := om.get(rs.constants, "SLASHY")
    expect_value(t, slashy.value.(string), "COUNT 1 2 3 4")

    plat_macro := om.get(rs.constants, "PLAT")
    expect_value(t, plat_macro.value.(string), "windows")
}

@(test)
test_cpp_unknown_int :: proc(t: ^testing.T) {
    using testing

    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libunknown_int.so"}},
        headers = {
            d = {runic.Platform{.Any, .Any} = {"test_data/unknown_int.h"}},
        },
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone(
        runic.Platform{.Linux, .x86_64},
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    expect_value(t, om.length(rs.types), 3)
    expect_value(t, om.length(rs.symbols), 1)

    pointy := om.get(rs.types, "pointy")
    expect_value(t, pointy.spec.(runic.Builtin), runic.Builtin.SInt64)

    structy_t := om.get(rs.types, "structy")
    strc := structy_t.spec.(runic.Struct)

    expect_value(t, len(strc.members), 3)
    expect_value(
        t,
        strc.members[0].type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    expect_value(t, strc.members[1].type.spec.(runic.Unknown), "heart_t")
    expect_value(
        t,
        strc.members[2].type.spec.(runic.Builtin),
        runic.Builtin.SInt64,
    )

    funcy := om.get(rs.symbols, "funcy")
    fy := funcy.value.(runic.Function)

    expect_value(t, len(fy.parameters), 3)
    expect_value(
        t,
        fy.parameters[0].type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    expect_value(t, fy.parameters[1].type.spec.(runic.Unknown), "pants_t")
    expect_value(
        t,
        fy.parameters[2].type.spec.(runic.Builtin),
        runic.Builtin.UInt64,
    )
    expect_value(t, fy.return_type.spec.(runic.Unknown), "brown_t")

    f_ptr := om.get(rs.types, "f_ptr")
    fp := f_ptr.spec.(runic.FunctionPointer)

    expect_value(t, len(fp.parameters), 2)
    expect_value(t, fp.parameters[0].type.spec.(runic.Unknown), "pants_t")
    expect_value(
        t,
        fp.parameters[1].type.spec.(runic.Builtin),
        runic.Builtin.SInt8,
    )

    expect_value(t, fp.return_type.spec.(runic.Builtin), runic.Builtin.SInt8)
}

