package runic

import "base:runtime"
import "core:strings"

Platform :: struct {
    os:   OS,
    arch: Architecture,
}

OS :: enum {
    Linux,
    Windows,
}

Architecture :: enum {
    x86_64,
    arm64,
}

host_os :: proc() -> OS {
    when ODIN_OS == .Linux {
        os := OS.Linux
    } else when ODIN_OS == .Windows {
        os := OS.Windows
    } else {
        panic("OS is not supported")
    }
    return os
}

host_arch :: proc() -> Architecture {
    when ODIN_ARCH == .amd64 {
        arch := Architecture.x86_64
    } else when ODIN_ARCH == .arm64 {
        arch := Architecture.arm64
    } else {
        panic("Architecture is not supported")
    }
    return arch
}

platform_from_host :: proc() -> Platform {
    return Platform{os = host_os(), arch = host_arch()}
}

platform_value :: proc(
    $T: typeid,
    plat: Platform,
    all, linux, windows: T,
) -> T {
    switch plat.os {
    case .Linux:
        if len(linux) != 0 do return linux
    case .Windows:
        if len(windows) != 0 do return windows
    }
    return all
}

set_library :: proc(plat: Platform, rs: ^Runestone, from: From) {
    static_name := platform_value(
        string,
        plat,
        from.static,
        from.static_linux,
        from.static_windows,
    )
    shared_name := platform_value(
        string,
        plat,
        from.shared,
        from.shared_linux,
        from.shared_windows,
    )

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)
    if len(shared_name) != 0 do rs.lib_shared = strings.clone(shared_name, rs_arena_alloc)
    if len(static_name) != 0 do rs.lib_static = strings.clone(static_name, rs_arena_alloc)
}
