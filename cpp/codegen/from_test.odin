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
