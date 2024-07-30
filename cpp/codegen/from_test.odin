package cpp_codegen

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

    expect_value(t, om.length(rs.types), 4)

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

    w_ctx, ok := om.get(rs.types, "wl_context")
    expect(t, ok)

    w_ctx_s := w_ctx.spec.(runic.Struct)
    expect_value(t, len(w_ctx_s.members), 1)
    expect_value(t, w_ctx_s.members[0].name, "window")

    window := w_ctx_s.members[0].type.spec.(runic.Struct)
    expect_value(t, len(window.members), 3)
    expect_value(t, window.members[2].name, "x")

    x := window.members[2].type.spec.(runic.Struct)
    expect_value(t, len(x.members), 1)
    expect_value(t, x.members[0].name, "str")
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

    expect_value(t, om.length(rs.types), 4)
    expect_value(t, om.length(rs.symbols), 1)

    abc := om.get(rs.types, "abc_enum")
    abc_enum := abc.spec.(runic.Enum)

    expect_value(t, len(abc_enum.entries), 3)
    expect_value(t, abc_enum.entries[0].name, "A")
    expect_value(t, abc_enum.entries[1].name, "B")
    expect_value(t, abc_enum.entries[2].name, "C")

    expect_value(t, abc_enum.entries[0].value.(i64), 0)
    expect_value(t, abc_enum.entries[1].value.(i64), 1)
    expect_value(t, abc_enum.entries[2].value.(i64), 2)

    cba := om.get(rs.types, "cba_enum")
    cba_enum := cba.spec.(runic.Enum)

    expect_value(t, len(cba_enum.entries), 3)
    expect_value(t, cba_enum.entries[0].name, "M")
    expect_value(t, cba_enum.entries[1].name, "H")
    expect_value(t, cba_enum.entries[2].name, "N")

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

    expect_value(t, con_enum.entries[0].value.(i64), 1)
    expect_value(t, con_enum.entries[1].value.(i64), 5)
    expect_value(t, con_enum.entries[2].value.(i64), 8)
    expect_value(t, con_enum.entries[3].value.(i64), -7)
    expect_value(t, con_enum.entries[4].value.(i64), 789)
    expect_value(t, con_enum.entries[5].value.(i64), 90)
    expect_value(t, con_enum.entries[6].value.(i64), (70 * 4 + 9) / 6 % 7)
}
