package ini

import "core:testing"
import om "root:ordered_map"

@(test)
test_ini :: proc(t: ^testing.T) {
    using testing

    ini_file, err := parse("test_data/ini_test.ini")
    if !expect_value(t, err, nil) do return

    expect_value(t, len(ini_file), 3)
    expect_value(t, om.length(ini_file[""]), 1)
    expect_value(t, om.length(ini_file["first_section"]), 3)
    expect_value(t, om.length(ini_file["second_section"]), 3)

    expect_value(t, om.get(ini_file[""], "version"), "0")

    expect_value(t, om.get(ini_file["first_section"], "foo") , "\"bar\"")
    expect_value(t, om.get(ini_file["first_section"], "pa"), "\"5=6\"")
    expect_value(t, om.get(ini_file["first_section"], "\"funny=sad\""), "zuz")

    expect_value(t, om.get(ini_file["second_section"], "0") , "3")
    expect_value(t, om.get(ini_file["second_section"], "pär"), "pöü")
    expect_value(t, om.get(ini_file["second_section"], "🤣"), "😥")
}
