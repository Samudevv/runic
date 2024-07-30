package cpp_codegen

import "core:testing"
import om "root:ordered_map"
import "root:runic"

@(test)
test_from_cpp_codegen :: proc(t: ^testing.T) {
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

    expect_value(t, om.length(rs.types), 32)
}
