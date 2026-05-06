package ini

import "base:runtime"
import "core:testing"
import om "root:ordered_map"

@(test)
test_ini :: proc(t: ^testing.T) {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    context.allocator = runtime.arena_allocator(&arena)

    ini_file, err := parse("test_data/ini_test.ini")
    if !testing.expect_value(t, err, nil) do return

    testing.expect_value(t, len(ini_file), 3)
    testing.expect_value(t, om.length(ini_file[""]), 1)
    testing.expect_value(t, om.length(ini_file["first_section"]), 3)
    testing.expect_value(t, om.length(ini_file["second_section"]), 3)

    testing.expect_value(t, om.get(ini_file[""], "version"), "0")

    testing.expect_value(t, om.get(ini_file["first_section"], "foo"), "\"bar\"")
    testing.expect_value(t, om.get(ini_file["first_section"], "pa"), "\"5=6\"")
    testing.expect_value(t, om.get(ini_file["first_section"], "\"funny=sad\""), "zuz")

    testing.expect_value(t, om.get(ini_file["second_section"], "0"), "3")
    testing.expect_value(t, om.get(ini_file["second_section"], "pär"), "pöü")
    testing.expect_value(t, om.get(ini_file["second_section"], "🤣"), "😥")
}
