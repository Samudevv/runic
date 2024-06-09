/*
This file is part of runic.

Runic is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2
as published by the Free Software Foundation.

Runic is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with runic.  If not, see <http://www.gnu.org/licenses/>.

*/

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
    Macos,
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
    } else when ODIN_OS == .Darwin {
        os := OS.Macos
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
    all, linux, windows, macos: T,
) -> T {
    switch plat.os {
    case .Linux:
        if len(linux) != 0 do return linux
    case .Windows:
        if len(windows) != 0 do return windows
    case .Macos:
        if len(macos) != 0 do return macos
    }
    return all
}

set_library :: proc(plat: Platform, rs: ^Runestone, from: From) {
    static_name := platform_value(
        string,
        plat,
        all = from.static,
        linux = from.static_linux,
        windows = from.static_windows,
        macos = from.static_macos,
    )
    shared_name := platform_value(
        string,
        plat,
        all = from.shared,
        linux = from.shared_linux,
        windows = from.shared_windows,
        macos = from.shared_macos,
    )

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)
    if len(shared_name) != 0 do rs.lib_shared = strings.clone(shared_name, rs_arena_alloc)
    if len(static_name) != 0 do rs.lib_static = strings.clone(static_name, rs_arena_alloc)
}
