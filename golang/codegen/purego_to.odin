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
package golang_codegen

import "core:io"
import "root:runic"
import "root:errors"
import "core:strings"
import om "root:ordered_map"

@(private)
purego_template :: #load("./go/purego_template.go", string)

purego_generate_bindings_from_runestone :: proc(
    rs: runic.Runestone,
    rn: runic.To,
    wd: io.Writer,
) -> union {
    io.Error,
    errors.Error,
} {
    return errors.Error(errors.not_implemented())
}

@(private)
purego_generate_package_name :: proc(
    buffer: string,
    rn: runic.To,
) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    strings.write_string(&buf, "package ")
    strings.write_string(&buf, rn.package_name)

    new_buffer, _ := strings.replace(buffer, "package main", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}

@(private)
purego_generate_platforms_and_libraries :: proc(
    buffer: string,
    rc: runic.Runecross,
    rn: runic.To,
) -> string {
    platform_libraries := om.make(runic.Platform, string)
    defer om.delete(platform_libraries)

    for entry in rc.cross {
        for plat in entry.plats {
            if !om.contains(platform_libraries, plat) {
                if shared, ok := entry.lib.shared.?; ok {
                    om.insert(&platform_libraries, plat, shared)
                }
            }
        }
    }

    buf: strings.Builder
    strings.builder_init(&buf)
    defer strings.builder_destroy(&buf)

    for entry, idx in platform_libraries.data {
        plat, lib := entry.key, entry.value

        strings.write_string(&buf, "\t\t{\"")
        strings.write_string(&buf, runic_os_to_goos(plat.os))
        strings.write_string(&buf, "\", \"")
        strings.write_string(&buf, runic_arch_to_goarch(plat.arch))
        strings.write_string(&buf, "\"}: \"")
        strings.write_string(&buf, lib)
        strings.write_string(&buf, "\",")

        if idx != om.length(platform_libraries) - 1 {
            strings.write_rune(&buf, '\n')
        }
    }

    new_buffer, _ := strings.replace(buffer, "\t\t{\"linux\", \"amd64\"}: \"libc.so.6\",", strings.to_string(buf), 1)
    delete(buffer)

    return new_buffer
}
