package runic

import "base:runtime"
import "core:strings"

platform_value_string :: proc(all, linux, windows: string) -> string {
    when ODIN_OS == .Windows {
        if len(windows) != 0 do return windows
    } else when ODIN_OS == .Linux {
        if len(linux) != 0 do return linux
    }
    return all
}

platform_value_array :: proc(
    all, linux, windows: [dynamic]string,
) -> [dynamic]string {
    when ODIN_OS == .Windows {
        if len(windows) != 0 do return windows
    } else when ODIN_OS == .Linux {
        if len(linux) != 0 do return linux
    }
    return all
}

platform_value :: proc {
    platform_value_string,
    platform_value_array,
}

set_library :: proc(rs: ^Runestone, from: From) {
    static_name := platform_value(
        from.static,
        from.static_linux,
        from.static_windows,
    )
    shared_name := platform_value(
        from.shared,
        from.shared_linux,
        from.shared_windows,
    )

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)
    if len(shared_name) != 0 do rs.lib_shared = strings.clone(shared_name, rs_arena_alloc)
    if len(static_name) != 0 do rs.lib_static = strings.clone(static_name, rs_arena_alloc)
}