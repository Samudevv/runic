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

//import "base:runtime"
//import "core:strings"

Platform :: struct {
    os:   OS,
    arch: Architecture,
}

OS :: enum {
    Any,
    Linux,
    Windows,
    Macos,
    BSD,
}

Architecture :: enum {
    Any,
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
    } else when ODIN_OS ==
        .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD {
        os := OS.BSD
    } else {
        #panic("OS is not supported")
    }
    return os
}

host_arch :: proc() -> Architecture {
    when ODIN_ARCH == .amd64 {
        arch := Architecture.x86_64
    } else when ODIN_ARCH == .arm64 {
        arch := Architecture.arm64
    } else {
        #panic("Architecture is not supported")
    }
    return arch
}

platform_from_host :: proc() -> Platform {
    return Platform{os = host_os(), arch = host_arch()}
}

platform_value :: proc(
    $T: typeid,
    plat: Platform,
    all,
    linux,
    linux_x86_64,
    linux_arm64,
    windows,
    windows_x86_64,
    windows_arm64,
    macos,
    macos_x86_64,
    macos_arm64,
    bsd,
    bsd_x86_64,
    bsd_arm64: T,
) -> T {
    switch plat.os {
    case .Linux:
        switch plat.arch {
        case .x86_64:
            if len(linux_x86_64) != 0 do return linux_x86_64
        case .arm64:
            if len(linux_arm64) != 0 do return linux_arm64
        }
        if len(linux) != 0 do return linux
    case .Windows:
        switch plat.arch {
        case .x86_64:
            if len(windows_x86_64) != 0 do return windows_x86_64
        case .arm64:
            if len(windows_arm64) != 0 do return windows_arm64
        }
        if len(windows) != 0 do return windows
    case .Macos:
        switch plat.arch {
        case .x86_64:
            if len(macos_x86_64) != 0 do return macos_x86_64
        case .arm64:
            if len(macos_arm64) != 0 do return macos_arm64
        }
        if len(macos) != 0 do return macos
    case .BSD:
        switch plat.arch {
        case .x86_64:
            if len(bsd_x86_64) != 0 do return bsd_x86_64
        case .arm64:
            if len(bsd_arm64) != 0 do return bsd_arm64
        }
        if len(bsd) != 0 do return bsd
    }
    return all
}

platform_from_strings :: proc(
    os, arch: Maybe(string),
) -> (
    plat: Platform,
    ok: bool,
) #optional_ok {
    if os != nil {
        switch os.? {
        case "linux":
            plat.os = .Linux
        case "windows":
            plat.os = .Windows
        case "macos":
            plat.os = .Macos
        case "bsd":
            plat.os = .BSD
        case:
            ok = false
            return
        }
    }

    if arch != nil {
        switch arch.? {
        case "x86_64":
            plat.arch = .x86_64
        case "arm64":
            plat.arch = .arm64
        case:
            ok = false
            return
        }
    }

    ok = true
    return
}

/*set_library :: proc(plat: Platform, rs: ^Runestone, from: From) {
    static_name := platform_value(
        string,
        plat,
        all = from.static,
        linux = from.static_linux,
        linux_x86_64 = from.static_linux_x86_64,
        linux_arm64 = from.static_linux_arm64,
        windows = from.static_windows,
        windows_x86_64 = from.static_windows_x86_64,
        windows_arm64 = from.static_windows_arm64,
        macos = from.static_macos,
        macos_x86_64 = from.static_macos_x86_64,
        macos_arm64 = from.static_macos_arm64,
        bsd = from.static_bsd,
        bsd_x86_64 = from.static_bsd_x86_64,
        bsd_arm64 = from.static_bsd_arm64,
    )
    shared_name := platform_value(
        string,
        plat,
        all = from.shared,
        linux = from.shared_linux,
        linux_x86_64 = from.shared_linux_x86_64,
        linux_arm64 = from.shared_linux_arm64,
        windows = from.shared_windows,
        windows_x86_64 = from.shared_windows_x86_64,
        windows_arm64 = from.shared_windows_arm64,
        macos = from.shared_macos,
        macos_x86_64 = from.shared_macos_x86_64,
        macos_arm64 = from.shared_macos_arm64,
        bsd = from.shared_bsd,
        bsd_x86_64 = from.shared_bsd_x86_64,
        bsd_arm64 = from.shared_bsd_arm64,
    )

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)
    if len(shared_name) != 0 do rs.lib.shared = strings.clone(shared_name, rs_arena_alloc)
    if len(static_name) != 0 do rs.lib.static = strings.clone(static_name, rs_arena_alloc)
}*/
