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
import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"

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
@(private)
OS_MIN :: OS.Linux
@(private)
OS_MAX :: OS.BSD

Architecture :: enum {
    Any,
    x86_64,
    arm64,
    x86,
    arm32,
}
@(private)
Architecture_MIN :: Architecture.x86_64
@(private)
Architecture_MAX :: Architecture.arm32

MIN_OS :: OS.Linux
MAX_OS :: OS.BSD
MIN_ARCH :: Architecture.x86_64
MAX_ARCH :: Architecture.arm32

host_os :: proc() -> OS {
    switch OS.Linux {
    case .Linux, .Windows, .Macos, .BSD, .Any:
    // Just a reminder
    }

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
    switch Architecture.Any {
    case .x86_64, .arm64, .x86, .arm32, .Any:
    // Just a reminder
    }

    when ODIN_ARCH == .amd64 {
        arch := Architecture.x86_64
    } else when ODIN_ARCH == .arm64 {
        arch := Architecture.arm64
    } else when ODIN_ARCH == .i386 {
        arch := Architecture.x86
    } else {
        #panic("Architecture is not supported")
    }
    return arch
}

platform_from_host :: proc() -> Platform {
    return Platform{os = host_os(), arch = host_arch()}
}

platform_from_strings :: proc(
    os, arch: Maybe(string),
) -> (
    plat: Platform,
    ok: bool,
) #optional_ok {
    if os != nil {
        switch plat.os {
        case .Linux, .Windows, .Macos, .BSD, .Any:
        // A reminder to implement more platforms
        }

        os_lower := strings.to_lower(os.?)
        defer delete(os_lower)

        switch os_lower {
        case "linux":
            plat.os = .Linux
        case "windows":
            plat.os = .Windows
        case "macos":
            plat.os = .Macos
        case "bsd":
            plat.os = .BSD
        case "any":
            plat.os = .Any
        case:
            ok = false
            return
        }
    }

    if arch != nil {
        switch plat.arch {
        case .x86_64, .arm64, .Any, .x86, .arm32:
        // A reminder to implement more platforms
        }

        arch_lower := strings.to_lower(arch.?)
        defer delete(arch_lower)

        switch arch_lower {
        case "x86_64":
            plat.arch = .x86_64
        case "arm64":
            plat.arch = .arm64
        case "x86":
            plat.arch = .x86
        case "arm32":
            plat.arch = .arm32
        case "any":
            plat.arch = .Any
        case:
            ok = false
            return
        }
    }

    ok = true
    return
}

platform_value_get :: proc(
    $T: typeid,
    v: PlatformValue(T),
    plat: Platform,
) -> (
    T,
    bool,
) #optional_ok {
    ok: bool = ---
    plat_v: T = ---

    if plat_v, ok = v.d[plat]; ok {
        return plat_v, true
    } else if plat_v, ok = v.d[Platform{os = plat.os, arch = .Any}]; ok {
        return plat_v, true
    } else if plat_v, ok = v.d[Platform{os = .Any, arch = .Any}]; ok {
        return plat_v, true
    }

    return T{}, false
}

set_library :: proc(plat: Platform, rs: ^Runestone, from: From) {
    rs_arena_alloc := runtime.arena_allocator(&rs.arena)

    if static_name, ok := platform_value_get(string, from.static, plat); ok {
        rs.lib.static = strings.clone(static_name, rs_arena_alloc)
    }
    if shared_name, ok := platform_value_get(string, from.shared, plat); ok {
        rs.lib.shared = strings.clone(shared_name, rs_arena_alloc)
    }
}

make_platform_value :: #force_inline proc(
    $T: typeid,
    allocator := context.allocator,
    #any_int cap: int = 1 << runtime.MAP_MIN_LOG2_CAPACITY,
) -> (
    pv: PlatformValue(T),
    err: runtime.Allocator_Error,
) #optional_allocator_error {
    pv.d, err = make(map[Platform]T, cap, allocator = allocator)
    return
}

platform_file_name :: proc(
    file_name: string,
    plat: Platform,
    allocator := context.allocator,
) -> string {
    dir := filepath.dir(file_name, allocator)
    stem := filepath.stem(file_name)
    ext := filepath.ext(file_name)

    // BONUS TODO: Do this without an allocation
    os_str, arch_str: string = ---, ---
    if plat.os != .Any {
        os_str = fmt.aprint(plat.os, allocator = allocator)
    } else {
        os_str = ""
    }
    if plat.arch != .Any {
        arch_str = fmt.aprint(plat.arch, allocator = allocator)
    } else {
        arch_str = ""
    }

    bd: strings.Builder
    strings.builder_init(
        &bd,
        len = 0,
        cap = len(file_name) + 1 + 1 + len(os_str) + len(arch_str),
        allocator = allocator,
    )

    strings.write_string(&bd, dir)
    strings.write_rune(&bd, filepath.SEPARATOR)
    strings.write_string(&bd, stem)
    if plat.os != .Any || plat.arch != .Any {
        strings.write_rune(&bd, '-')
        if plat.os != .Any {
            strings.write_string(&bd, os_str)
            if plat.arch != .Any {
                strings.write_rune(&bd, '_')
            }
        }
        if plat.arch != .Any {
            strings.write_string(&bd, arch_str)
        }
    }
    strings.write_string(&bd, ext)

    return strings.to_string(bd)
}

multiple_platforms_file_name :: proc(
    file_name: string,
    plats: []Platform,
    allocator := context.allocator,
) -> string {
    dir := filepath.dir(file_name, allocator)
    stem := filepath.stem(file_name)
    ext := filepath.ext(file_name)

    defer delete(dir, allocator)

    bd: strings.Builder
    strings.builder_init(
        &bd,
        len = 0,
        cap = len(file_name) + len(plats) * 2,
        allocator = allocator,
    )

    strings.write_string(&bd, dir)
    strings.write_rune(&bd, filepath.SEPARATOR)
    strings.write_string(&bd, stem)

    for plat in plats {
        if plat.os == .Any && plat.arch == .Any do continue

        strings.write_rune(&bd, '-')

        if plat.os != .Any {
            os_str := fmt.aprint(plat.os, allocator = allocator)
            strings.write_string(&bd, os_str)
            delete(os_str, allocator)
            if plat.arch != .Any {
                strings.write_rune(&bd, '_')
            }
        }

        if plat.arch != .Any {
            arch_str := fmt.aprint(plat.arch, allocator = allocator)
            strings.write_string(&bd, arch_str)
            delete(arch_str, allocator)
        }
    }

    strings.write_string(&bd, ext)

    return strings.to_string(bd)

}

platform_matches :: #force_inline proc(
    p1, p2: Platform,
    ignore_arch := false,
) -> bool {
    return(
        (p1.os == .Any || p2.os == .Any || p1.os == p2.os) &&
        (ignore_arch ||
                p1.arch == .Any ||
                p2.arch == .Any ||
                p1.arch == p2.arch) \
    )
}

minimize_platforms :: proc(
    rune_platforms: []Platform,
    stone_plats: []Platform,
    ignore_arch: bool,
    allocator := context.allocator,
) -> [dynamic]Platform {
    unique_plats := make(
        [dynamic]Platform,
        len = 0,
        cap = len(stone_plats),
        allocator = allocator,
    )
    any_plats := make([dynamic]Platform, len = 0, cap = len(stone_plats))
    oses := make([dynamic]OS, len = 0, cap = len(rune_platforms))
    arches := make([dynamic]Architecture, len = 0, cap = len(rune_platforms))
    defer delete(any_plats)
    defer delete(oses)
    defer delete(arches)

    // Try to minimize the number of platform entries

    // 1. Count how many oses and arches we have specified in the rune.platforms
    for p in rune_platforms {
        if !slice.contains(oses[:], p.os) do append(&oses, p.os)
        if !slice.contains(arches[:], p.arch) do append(&arches, p.arch)
    }

    append(&unique_plats, ..stone_plats)

    // 2. Construct a list of all platforms where all oses or arches are present
    for p, idx in unique_plats {
        if p.os == .Any || p.arch == .Any {
            if !slice.contains(any_plats[:], p) {
                append(&any_plats, p)
            }
            continue
        }

        p_oses := make([dynamic]OS, len = 1, cap = len(oses))
        p_arches := make([dynamic]Architecture, len = 1, cap = len(arches))
        defer delete(p_oses)
        defer delete(p_arches)

        p_oses[0] = p.os
        p_arches[0] = p.arch

        // Count how often the os or arch appears
        for b, idy in unique_plats {
            if idx == idy do continue

            if b.os == p.os {
                if !slice.contains(p_arches[:], b.arch) {
                    append(&p_arches, b.arch)
                }
            }
            if b.arch == p.arch {
                if !slice.contains(p_oses[:], b.os) {
                    append(&p_oses, b.os)
                }
            }
        }

        // If the count is as high as the total count add the plat to the list
        if len(p_oses) == len(oses) || len(p_arches) == len(arches) {
            any_plat := Platform {
                .Any if len(p_oses) == len(oses) else p.os,
                .Any if len(p_arches) == len(arches) else p.arch,
            }
            if !slice.contains(any_plats[:], any_plat) {
                append(&any_plats, any_plat)
            }
        }
    }

    // 3. Remove all platforms that are covered by the any plats
    for any_plat in any_plats {
        for idx := 0; idx < len(unique_plats); idx += 1 {
            if platform_matches(unique_plats[idx], any_plat) {
                ordered_remove(&unique_plats, idx)
                idx -= 1
            }
        }
    }

    // 4. Add the any plats to the list
    for any_plat in any_plats {
        append(&unique_plats, any_plat)
    }

    // 5. Sort the list
    slice.sort_by(unique_plats[:], platform_less)

    return unique_plats
}

platform_less :: proc(i, j: Platform) -> bool {
    if i.os == j.os do return i.arch < j.arch
    return i.os < j.os
}

platform_greater :: proc(i, j: Platform) -> bool {
    if i.os == j.os do return i.arch > j.arch
    return i.os > j.os
}

multiple_platforms_match :: proc(p1s, p2s: []Platform) -> bool {
    for p1 in p1s {
        for p2 in p2s {
            if !platform_matches(p1, p2) do return false
        }
    }

    return true
}

