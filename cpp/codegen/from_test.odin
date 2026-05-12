#+feature dynamic-literals
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
    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libbuiltin.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/builtin.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    rs, err := generate_runestone({.Linux, .arm64}, RUNESTONE_TEST_PATH, rf)
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 34)
    testing.expect_value(t, om.length(rs.symbols), 9)

    rab := om.get(rs.symbols, "rab")
    rab_type := rab.value.(runic.Type)
    testing.expect_value(
        t,
        rab_type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(t, rab_type.pointer_info.count, 2)

    zab := om.get(rs.symbols, "zab")
    zab_type := zab.value.(runic.Type)
    testing.expect_value(
        t,
        zab_type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(t, zab.value.(runic.Type).pointer_info.count, 1)
    testing.expect_value(t, zab.value.(runic.Type).array_info[0].size.(u64), 2)

    not_string := om.get(rs.types, "not_string")
    testing.expect_value(
        t,
        not_string.spec.(runic.Builtin),
        runic.Builtin.SInt8,
    )
    testing.expect_value(t, not_string.pointer_info.count, 1)

    is_a_string := om.get(rs.types, "is_a_string")
    testing.expect_value(
        t,
        is_a_string.spec.(runic.Builtin),
        runic.Builtin.String,
    )
    testing.expect_value(t, is_a_string.pointer_info.count, 0)

    l := om.get(rs.types, "l")
    testing.expect_value(t, l.spec.(runic.Builtin), runic.Builtin.SInt32)
    m := om.get(rs.types, "m")
    testing.expect_value(t, m.spec.(runic.Builtin), runic.Builtin.SInt32)
}

@(test)
test_cpp_pointer :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.symbols), 9)

    arr := om.get(rs.symbols, "arr")
    arr_type := arr.value.(runic.Type)

    testing.expect_value(
        t,
        arr_type.spec.(runic.Builtin),
        runic.Builtin.String,
    )
    testing.expect_value(t, arr_type.read_only, true)
    testing.expect_value(t, arr_type.pointer_info.count, 1)
    testing.expect_value(t, arr_type.pointer_info.read_only, true)
}

@(test)
test_cpp_array :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.symbols), 5)

    ptr := om.get(rs.symbols, "ptr")
    ptr_type := ptr.value.(runic.Type)

    testing.expect_value(
        t,
        ptr_type.spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    testing.expect_value(t, len(ptr_type.array_info), 1)
    testing.expect_value(t, ptr_type.array_info[0].size.(u64), 12)

    c := om.get(rs.symbols, "c")
    c_type := c.value.(runic.Type)

    testing.expect_value(t, len(c_type.array_info), 3)
    testing.expect_value(t, c_type.array_info[0].size.(u64), 1)
    testing.expect_value(t, c_type.array_info[1].size.(u64), 2)
    testing.expect_value(t, c_type.array_info[2].size.(u64), 3)
}

@(test)
test_cpp_struct :: proc(t: ^testing.T) {


    rf := runic.From {
        language          = "c",
        shared            = {{{} = "libstruct.so"}},
        headers           = {{{} = {"test_data/struct.h"}}},
        forward_decl_type = {{{} = {spec = runic.Builtin.RawPtr}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)
    defer delete(rf.forward_decl_type.d)

    rs, err := generate_runestone(
        runic.platform_from_host(),
        RUNESTONE_TEST_PATH,
        rf,
    )
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 14)

    abc_t := om.get(rs.types, "abc_t")
    abc_struct := abc_t.spec.(runic.Struct)

    testing.expect_value(t, len(abc_struct.members), 4)
    testing.expect_value(t, abc_struct.members[0].name, "a")
    testing.expect_value(t, abc_struct.members[1].name, "b")
    testing.expect_value(t, abc_struct.members[2].name, "c")
    testing.expect_value(t, abc_struct.members[3].name, "yzg")

    ss_t := om.get(rs.types, "_sszu_")
    ss_t_struct := ss_t.spec.(runic.Struct)

    testing.expect_value(t, len(ss_t_struct.members), 1)
    testing.expect_value(t, ss_t_struct.members[0].name, "x")

    sszu := om.get(rs.types, "ss_t")
    testing.expect_value(t, sszu.spec.(string), "_sszu_")

    w_ctx, ok := om.get(rs.types, "wl_context")
    testing.expect(t, ok)

    w_ctx_s := w_ctx.spec.(runic.Struct)
    testing.expect_value(t, len(w_ctx_s.members), 1)
    testing.expect_value(t, w_ctx_s.members[0].name, "window")

    window := w_ctx_s.members[0].type.spec.(string)
    testing.expect_value(t, window, "window_struct_anon_1")

    window_struct := om.get(rs.types, "window_struct_anon_1")
    window_s := window_struct.spec.(runic.Struct)

    x := window_s.members[2].type.spec.(string)
    testing.expect_value(t, x, "x_struct_anon_0")

    wl_output := om.get(rs.types, "wl_output")
    testing.expect_value(
        t,
        wl_output.spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    testing.expect_value(
        t,
        om.get(rs.types, "mega_type").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    testing.expect_value(
        t,
        om.get(rs.types, "non_exist").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    testing.expect_value(
        t,
        om.get(rs.types, "super_union").spec.(runic.Builtin),
        runic.Builtin.RawPtr,
    )
    testing.expect_value(
        t,
        om.get(rs.types, "super_type").spec.(string),
        "mega_type",
    )
    testing.expect_value(
        t,
        om.get(rs.types, "tippy_toes").spec.(runic.Struct).members[0].type.spec.(string),
        "non_exist",
    )

    my_struct := om.get(rs.types, "my_struct")
    testing.expect_value(
        t,
        my_struct.spec.(runic.Builtin),
        runic.Builtin.Untyped,
    )

    byte_array := om.get(rs.types, "byte_array").spec.(runic.Struct)
    testing.expect_value(t, len(byte_array.members), 3)
    ba_x := byte_array.members[0]
    ba_y := byte_array.members[1]
    ba_b := byte_array.members[2]
    testing.expect_value(
        t,
        ba_x.type.spec.(runic.Builtin),
        runic.Builtin.UInt8,
    )
    testing.expect_value(
        t,
        ba_y.type.spec.(runic.Builtin),
        runic.Builtin.UInt8,
    )
    testing.expect_value(
        t,
        ba_b.type.spec.(runic.Builtin),
        runic.Builtin.UInt8,
    )
    testing.expect_value(t, ba_x.type.array_info[0].size.(u64), 1)
    testing.expect_value(t, ba_y.type.array_info[0].size.(u64), 2)
    testing.expect_value(t, ba_b.type.array_info[0].size.(u64), 3)
}

@(test)
test_cpp_enum :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 7)
    testing.expect_value(t, om.length(rs.symbols), 1)

    abc := om.get(rs.types, "abc_enum")
    abc_enum := abc.spec.(runic.Enum)

    testing.expect_value(t, len(abc_enum.entries), 3)
    testing.expect_value(t, abc_enum.entries[0].name, "A")
    testing.expect_value(t, abc_enum.entries[1].name, "B")
    testing.expect_value(t, abc_enum.entries[2].name, "C")
    testing.expect_value(t, abc_enum.type, runic.Builtin.UInt32)

    testing.expect_value(t, abc_enum.entries[0].value.(i64), 0)
    testing.expect_value(t, abc_enum.entries[1].value.(i64), 1)
    testing.expect_value(t, abc_enum.entries[2].value.(i64), 2)

    cba := om.get(rs.types, "cba_enum")
    cba_enum := cba.spec.(runic.Enum)

    testing.expect_value(t, len(cba_enum.entries), 3)
    testing.expect_value(t, cba_enum.entries[0].name, "M")
    testing.expect_value(t, cba_enum.entries[1].name, "H")
    testing.expect_value(t, cba_enum.entries[2].name, "N")
    testing.expect_value(t, cba_enum.type, runic.Builtin.UInt32)

    testing.expect_value(t, cba_enum.entries[0].value.(i64), 0)
    testing.expect_value(t, cba_enum.entries[1].value.(i64), 1)
    testing.expect_value(t, cba_enum.entries[2].value.(i64), 2)


    constis := om.get(rs.types, "constants")
    con_enum := constis.spec.(runic.Enum)

    testing.expect_value(t, len(con_enum.entries), 7)
    testing.expect_value(t, con_enum.entries[0].name, "X")
    testing.expect_value(t, con_enum.entries[1].name, "Y")
    testing.expect_value(t, con_enum.entries[2].name, "Z")
    testing.expect_value(t, con_enum.entries[3].name, "W")
    testing.expect_value(t, con_enum.entries[4].name, "Apple")
    testing.expect_value(t, con_enum.entries[5].name, "Banana")
    testing.expect_value(t, con_enum.entries[6].name, "Calculate")
    testing.expect_value(t, con_enum.type, runic.Builtin.SInt32)

    testing.expect_value(t, con_enum.entries[0].value.(i64), 1)
    testing.expect_value(t, con_enum.entries[1].value.(i64), 5)
    testing.expect_value(t, con_enum.entries[2].value.(i64), 8)
    testing.expect_value(t, con_enum.entries[3].value.(i64), -7)
    testing.expect_value(t, con_enum.entries[4].value.(i64), 789)
    testing.expect_value(t, con_enum.entries[5].value.(i64), 90)
    testing.expect_value(
        t,
        con_enum.entries[6].value.(i64),
        (70 * 4 + 9) / 6 % 7,
    )

    adv := om.get(rs.types, "advanced").spec.(runic.Enum)

    testing.expect_value(t, len(adv.entries), 3)
    testing.expect_value(t, adv.type, runic.Builtin.SInt64)
}

@(test)
test_cpp_union :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 3)

    my_union := om.get(rs.types, "my_union")
    my := my_union.spec.(runic.Union)

    testing.expect_value(t, len(my.members), 2)
    testing.expect_value(t, my.members[0].name, "zuz")
    testing.expect_value(t, my.members[1].name, "uzu")

    other_union := om.get(rs.types, "other_union")
    other := other_union.spec.(runic.Union)

    testing.expect_value(t, len(other.members), 2)
    testing.expect_value(t, other.members[0].name, "floaties")
    testing.expect_value(t, other.members[1].name, "inties")

    floaties := other.members[0].type.spec.(string)
    testing.expect_value(t, floaties, "floaties_struct_anon_0")
}

@(test)
test_cpp_attribute :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 4)
    testing.expect_value(t, om.length(rs.symbols), 2)
}

@(test)
test_cpp_include :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
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
    if !testing.expect_value(t, err_all, nil) do return
    defer runic.runestone_destroy(&rs_all)

    runic.from_postprocess_runestone(&rs_all, rf)

    testing.expect_value(t, om.length(rs.types), 4)
    testing.expect_value(t, om.length(rs.symbols), 0)
    testing.expect_value(t, om.length(rs.constants), 0)

    if callbacker_type, ok := om.get(rs.types, "callbacker");
       testing.expect(t, ok) {
        if callbacker, spec_ok := callbacker_type.spec.(runic.Struct);
           testing.expect(t, spec_ok) {
            if testing.expect_value(t, len(callbacker.members), 1) {
                if cb, cb_ok := callbacker.members[0].type.spec.(string);
                   testing.expect(t, cb_ok) {
                    testing.expect_value(t, cb, "callback_proc")
                }
            }
        }
    }

    if callback_proc_type, ok := om.get(rs.types, "callback_proc");
       testing.expect(t, ok) {
        if callback_proc, spec_ok := callback_proc_type.spec.(runic.FunctionPointer);
           testing.expect(t, spec_ok) {
            testing.expect_value(t, len(callback_proc.parameters), 2)
        }
    }

    testing.expect(t, om.contains(rs.types, "lower_t"))
    testing.expect(t, om.contains(rs.types, "below_t"))

    testing.expect_value(t, om.length(rs_all.types), 4)
    testing.expect_value(t, om.length(rs_all.symbols), 3)
    testing.expect_value(t, om.length(rs_all.constants), 1)

    testing.expect(t, om.contains(rs_all.symbols, "a"))
    testing.expect(t, om.contains(rs_all.symbols, "b"))
    testing.expect(t, om.contains(rs_all.symbols, "xyz"))
    testing.expect(t, om.contains(rs_all.types, "callback_proc"))
    testing.expect(t, om.contains(rs_all.types, "callbacker"))
    testing.expect(t, om.contains(rs_all.types, "lower_t"))
    testing.expect(t, om.contains(rs_all.types, "below_t"))

    testing.expect_value(
        t,
        om.get(rs_all.types, "lower_t").spec.(string),
        "below_t",
    )
    testing.expect_value(
        t,
        om.get(rs_all.types, "below_t").spec.(runic.Struct).members[0].name,
        "a",
    )

    consta := om.get(rs_all.constants, "INCLUDE_CHILD")
    testing.expect_value(t, consta.value.(i64), 15)


}

@(test)
test_cpp_system_include :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)
    runic.from_postprocess_runestone(&rs, rf)

    testing.expect_value(t, om.length(rs.types), 3)
    testing.expect_value(t, om.length(rs.externs), 6)
    testing.expect_value(t, om.length(rs.symbols), 4)

    testing.expect_value(
        t,
        om.get(rs.types, "from_main").spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(
        t,
        om.get(rs.types, "main_struct").spec.(runic.Struct).members[0].type.spec.(runic.ExternType),
        "from_system",
    )
    testing.expect_value(
        t,
        om.get(rs.types, "from_other_system").spec.(runic.ExternType),
        "sysi",
    )
    testing.expect(t, !om.contains(rs.types, "feature_t"))

    testing.expect_value(
        t,
        om.get(rs.externs, "from_system").spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(
        t,
        om.get(rs.externs, "ant").spec.(runic.Builtin),
        runic.Builtin.Float32,
    )
    testing.expect_value(
        t,
        om.get(rs.externs, "sysi").spec.(runic.Builtin),
        runic.Builtin.Float64,
    )
    testing.expect(t, !om.contains(rs.externs, "also_from_system"))
    testing.expect(t, om.contains(rs.externs, "feature_t"))
    testing.expect_value(
        t,
        om.get(rs.externs, "donkey_t").spec.(runic.Struct).members[1].name,
        "oink",
    )
    testing.expect_value(
        t,
        om.get(rs.externs, "donkey_t").spec.(runic.Struct).members[1].type.spec.(runic.ExternType),
        "oink_func_ptr_anon_0",
    )
    oink := om.get(rs.externs, "oink_func_ptr_anon_0").spec.(runic.FunctionPointer)
    testing.expect_value(t, len(oink.parameters), 2)
    testing.expect_value(t, oink.parameters[0].name, "volume")
    testing.expect_value(t, oink.parameters[1].name, "speed")

    testing.expect_value(
        t,
        om.get(rs.symbols, "part").value.(runic.Function).parameters[1].type.spec.(runic.ExternType),
        "ant",
    )
    testing.expect_value(
        t,
        om.get(rs.symbols, "make_feature").value.(runic.Function).parameters[0].type.spec.(runic.ExternType),
        "feature_t",
    )
    testing.expect_value(
        t,
        om.get(rs.symbols, "new_donkey").value.(runic.Function).return_type.spec.(runic.ExternType),
        "donkey_t",
    )
}

@(test)
test_cpp_elaborated :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)
    runic.from_postprocess_runestone(&rs, rf)

    testing.expect_value(t, om.length(rs.types), 9)
    testing.expect_value(t, om.length(rs.symbols), 4)

    pack := om.get(rs.symbols, "pack")
    pack_type := pack.value.(runic.Type).spec.(string)

    testing.expect_value(t, pack_type, "big_package")

    bag := om.get(rs.symbols, "bag")
    bag_type := bag.value.(runic.Type).spec.(string)

    testing.expect_value(t, bag_type, "small_package")

    packer := om.get(rs.symbols, "packer")
    packer_type := packer.value.(runic.Type).spec.(string)

    testing.expect_value(t, packer_type, "packer_struct_anon_1")

    tree := om.get(rs.symbols, "tree")
    tree_type := tree.value.(runic.Type)

    _, ok := tree_type.spec.(string)
    testing.expect(t, ok)

    testing.expect(t, tree_type.read_only)

    small_package := om.get(rs.types, "small_package")
    small := small_package.spec.(runic.Struct)

    testing.expect_value(t, len(small.members), 2)
    testing.expect_value(t, small.members[1].type.spec.(string), "wisdom_t")

    unific := om.get(rs.types, "unific")
    uni := unific.spec.(runic.Union)

    testing.expect_value(t, len(uni.members), 4)
    testing.expect_value(t, uni.members[0].type.spec.(string), "big_package")
    testing.expect_value(t, uni.members[1].type.spec.(string), "small_package")
    testing.expect_value(
        t,
        uni.members[2].type.spec.(string),
        "w_struct_anon_0",
    )
    testing.expect_value(t, uni.members[3].type.spec.(string), "zuz")

    zuz := om.get(rs.types, "zuz")
    zuz_type := zuz.spec.(runic.Struct)

    testing.expect_value(t, len(zuz_type.members), 1)

    wisdom_t := om.get(rs.types, "wisdom_t")
    wisdom := wisdom_t.spec.(runic.Builtin)
    testing.expect_value(t, wisdom, runic.Builtin.SInt64)
}
@(test)
test_cpp_function :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 1)
    testing.expect_value(t, om.length(rs.symbols), 9)

    hello_world := om.get(rs.symbols, "hello_world")
    hw := hello_world.value.(runic.Function)

    testing.expect_value(
        t,
        hw.return_type.spec.(runic.Builtin),
        runic.Builtin.Untyped,
    )
    testing.expect_value(t, len(hw.parameters), 0)
    testing.expect(t, !hw.variadic)

    foo := om.get(rs.symbols, "foo")
    fooo := foo.value.(runic.Function)

    testing.expect_value(
        t,
        fooo.return_type.spec.(runic.Builtin),
        runic.Builtin.Untyped,
    )
    testing.expect_value(t, len(fooo.parameters), 3)
    testing.expect_value(t, fooo.parameters[1].name, "b")

    strcpy := om.get(rs.symbols, "strcpy")
    spy := strcpy.value.(runic.Function)

    testing.expect_value(t, len(spy.parameters), 1)
    testing.expect_value(t, spy.parameters[0].name, "param0")
    testing.expect_value(
        t,
        spy.parameters[0].type.spec.(runic.Builtin),
        runic.Builtin.String,
    )
    testing.expect_value(t, spy.parameters[0].type.read_only, true)

    baz := om.get(rs.symbols, "baz")
    bz := baz.value.(runic.Function)

    testing.expect_value(
        t,
        bz.parameters[0].type.spec.(string),
        "x_struct_anon_0",
    )

    variadic := om.get(rs.symbols, "variadic_func").value.(runic.Function)
    testing.expect_value(t, len(variadic.parameters), 1)
    testing.expect_value(t, variadic.variadic, true)
}

@(test)
test_cpp_function_pointer :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 8)
    testing.expect_value(t, om.length(rs.symbols), 6)

    hello := om.get(rs.symbols, "hello")
    hell := hello.value.(runic.Type).spec.(runic.FunctionPointer)

    testing.expect_value(t, len(hell.parameters), 0)
    testing.expect_value(
        t,
        hell.return_type.spec.(runic.Builtin),
        runic.Builtin.Untyped,
    )

    bye := om.get(rs.symbols, "bye")
    by := bye.value.(runic.Type).spec.(runic.FunctionPointer)

    testing.expect_value(t, len(by.parameters), 4)
    testing.expect_value(
        t,
        by.parameters[3].type.spec.(string),
        "s_struct_anon_0",
    )

    consty := om.get(rs.types, "consty")
    coy := consty.spec.(runic.FunctionPointer)
    testing.expect_value(t, consty.read_only, true)
    testing.expect_value(t, len(coy.parameters), 2)
    testing.expect_value(t, coy.parameters[0].name, "a")
    testing.expect_value(t, coy.parameters[1].name, "b")

    signal_func := om.get(rs.symbols, "signal")
    signal_rt_name, signal_rt_is_fp := signal_func.value.(runic.Function).return_type.spec.(string)
    testing.expect(t, signal_rt_is_fp)

    signal_rt := om.get(rs.types, signal_rt_name)
    _, signal_rt_is_fp = signal_rt.spec.(runic.FunctionPointer)
    testing.expect(t, signal_rt_is_fp)

    signal_rt_name, signal_rt_is_fp = signal_func.value.(runic.Function).parameters[1].type.spec.(string)
    testing.expect(t, signal_rt_is_fp)

    signal_rt = om.get(rs.types, signal_rt_name)
    _, signal_rt_is_fp = signal_rt.spec.(runic.FunctionPointer)
    testing.expect(t, signal_rt_is_fp)

    create_window_t := om.get(rs.types, "create_window")
    create_window := create_window_t.spec.(runic.FunctionPointer)

    testing.expect_value(t, len(create_window.parameters), 3)
    testing.expect_value(t, create_window.parameters[0].name, "name")
    testing.expect_value(t, create_window.parameters[1].name, "width")
    testing.expect_value(t, create_window.parameters[2].name, "height")

    variadic := om.get(rs.types, "variadic_func").spec.(runic.FunctionPointer)
    testing.expect_value(t, len(variadic.parameters), 1)
    testing.expect_value(t, variadic.variadic, true)
}

@(test)
test_cpp_macros :: proc(t: ^testing.T) {


    rf := runic.From {
        language = "c",
        shared = {d = {runic.Platform{.Any, .Any} = "libmacros.so"}},
        headers = {d = {runic.Platform{.Any, .Any} = {"test_data/macros.h"}}},
    }
    defer delete(rf.shared.d)
    defer delete(rf.headers.d)

    plat := runic.Platform{.Windows, .x86_64}

    rs, err := generate_runestone(plat, RUNESTONE_TEST_PATH, rf)
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    if !testing.expect_value(t, om.length(rs.constants), 10) do return
    if !testing.expect_value(t, om.length(rs.types), 4) do return
    if !testing.expect_value(t, om.length(rs.symbols), 5) do return

    A := om.get(rs.constants, "A")
    testing.expect_value(t, A.value.(i64), 1)
    B := om.get(rs.constants, "B")
    testing.expect_value(t, B.value.(i64), 2)
    C := om.get(rs.constants, "C")
    testing.expect_value(t, C.value.(i64), 3)

    slashy := om.get(rs.constants, "SLASHY")
    testing.expect_value(t, slashy.value.(string), "COUNT 1 2 3 4")

    plat_macro := om.get(rs.constants, "PLAT")
    testing.expect_value(t, plat_macro.value.(string), "windows")

    testing.expect(t, !om.contains(rs.constants, "glCreateProgram"))
    testing.expect(t, om.contains(rs.constants, "A"))
    testing.expect(t, om.contains(rs.constants, "B"))
    testing.expect(t, om.contains(rs.constants, "C"))
    testing.expect(t, om.contains(rs.constants, "PLAT"))
    testing.expect(t, !om.contains(rs.constants, "glClearColor"))
    testing.expect(t, om.contains(rs.constants, "DO_VAR"))
    testing.expect(t, om.contains(rs.constants, "MULTI_VAR"))
    testing.expect(t, om.contains(rs.constants, "ALSO_VAR"))
    testing.expect(t, om.contains(rs.constants, "REC_VAR"))
    testing.expect(t, om.contains(rs.constants, "RECY"))
    testing.expect(t, om.contains(rs.constants, "SLASHY"))

    testing.expect(t, om.contains(rs.types, "beans"))
    testing.expect(t, om.contains(rs.types, "_beans"))
    testing.expect(t, om.contains(rs.types, "lingo"))
    testing.expect(t, om.contains(rs.types, "_lingo"))

    testing.expect(t, om.contains(rs.symbols, "__glewCreateProgram"))
    testing.expect(t, om.contains(rs.symbols, "__glewClearColor"))
    testing.expect(t, om.contains(rs.symbols, "init_beans"))
    testing.expect(t, om.contains(rs.symbols, "init_lingo"))
}

@(test)
test_cpp_unknown_int :: proc(t: ^testing.T) {


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
    if !testing.expect_value(t, err, nil) do return
    defer runic.runestone_destroy(&rs)

    testing.expect_value(t, om.length(rs.types), 4)
    testing.expect_value(t, om.length(rs.symbols), 1)

    pointy := om.get(rs.types, "pointy")
    testing.expect_value(t, pointy.spec.(runic.Builtin), runic.Builtin.SIntX)

    structy_t := om.get(rs.types, "structy")
    strc := structy_t.spec.(runic.Struct)

    testing.expect_value(t, len(strc.members), 3)
    testing.expect_value(
        t,
        strc.members[0].type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(
        t,
        strc.members[1].type.spec.(runic.Unknown),
        "heart_t",
    )
    testing.expect_value(
        t,
        strc.members[2].type.spec.(runic.Builtin),
        runic.Builtin.SInt64,
    )

    super_size := om.get(rs.types, "super_size")
    testing.expect_value(
        t,
        super_size.spec.(runic.Builtin),
        runic.Builtin.SIntX,
    )

    funcy := om.get(rs.symbols, "funcy")
    fy := funcy.value.(runic.Function)

    testing.expect_value(t, len(fy.parameters), 3)
    testing.expect_value(
        t,
        fy.parameters[0].type.spec.(runic.Builtin),
        runic.Builtin.SInt32,
    )
    testing.expect_value(
        t,
        fy.parameters[1].type.spec.(runic.Unknown),
        "pants_t",
    )
    testing.expect_value(
        t,
        fy.parameters[2].type.spec.(runic.Builtin),
        runic.Builtin.UInt64,
    )
    testing.expect_value(t, fy.return_type.spec.(runic.Unknown), "brown_t")

    f_ptr := om.get(rs.types, "f_ptr")
    fp := f_ptr.spec.(runic.FunctionPointer)

    testing.expect_value(t, len(fp.parameters), 2)
    testing.expect_value(
        t,
        fp.parameters[0].type.spec.(runic.Unknown),
        "pants_t",
    )
    testing.expect_value(
        t,
        fp.parameters[1].type.spec.(runic.Builtin),
        runic.Builtin.SInt8,
    )

    testing.expect_value(
        t,
        fp.return_type.spec.(runic.Builtin),
        runic.Builtin.SInt8,
    )
}
