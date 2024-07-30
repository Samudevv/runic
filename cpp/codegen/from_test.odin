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
