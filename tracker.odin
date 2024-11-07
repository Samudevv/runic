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

package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:strings"

track_memory :: proc(
    allocator := context.allocator,
) -> (
    ^mem.Tracking_Allocator,
    runtime.Allocator,
) {
    tracker := new(mem.Tracking_Allocator)
    mem.tracking_allocator_init(tracker, allocator)
    return tracker, mem.tracking_allocator(tracker)
}

print_track_results :: proc(tracker: ^mem.Tracking_Allocator) {
    defer mem.tracking_allocator_destroy(tracker)
    defer free_all(context.temp_allocator)

    if len(tracker.allocation_map) != 0 {
        fmt.eprintfln(
            "\n{}\n{}\n{}",
            "┌─────────┬──────────────Memory─Leaks───────────┬───────────────────────────┐",
            "│ Size    │ Location                            │ Procedure                 │",
            "│─────────┼─────────────────────────────────────┼───────────────────────────┤",
        )

        Leak :: struct {
            size: int,
            row:  string,
        }
        memories := make(
            map[runtime.Source_Code_Location]int,
            allocator = context.temp_allocator,
        )

        for _, entry in tracker.allocation_map {
            sz := entry.size
            if size, ok := memories[entry.location]; ok {
                sz += size
            }
            memories[entry.location] = sz
        }

        leaks := make(
            [dynamic]Leak,
            allocator = context.temp_allocator,
            len = 0,
            cap = len(memories),
        )

        leak_sum: int
        for location, size in memories {
            rel_path := short_path(location.file_path)

            append(
                &leaks,
                Leak {
                    size = size,
                    row = fmt.aprintf(
                        "│ % -7v │ %-35v │ %-25v │",
                        size,
                        fmt.aprintf(
                            "{}:{}:{}",
                            rel_path,
                            location.line,
                            location.column,
                            allocator = context.temp_allocator,
                        ),
                        location.procedure,
                        allocator = context.temp_allocator,
                    ),
                },
            )

            leak_sum += size
        }

        slice.sort_by(leaks[:], proc(i, j: Leak) -> bool {
            return i.size > j.size
        })

        for l in leaks {
            fmt.eprintln(l.row)
        }

        fmt.eprintln(
            "│─────────┼─────────────────────────────────────┼───────────────────────────┤",
        )
        fmt.eprintfln(
            "│ % -7v │ Sum                                 │                           │",
            leak_sum,
        )
        fmt.eprintln(
            "└─────────┴─────────────────────────────────────┴───────────────────────────┘",
        )
    } else {
        fmt.eprintln("\nNo Memory Leaks")
    }

    if len(tracker.bad_free_array) != 0 {
        fmt.eprintln(
            "\n┌──────────────Bad─Frees──────────────┐",
        )

        memories := make(
            map[runtime.Source_Code_Location]bool,
            allocator = context.temp_allocator,
        )
        for bad_free in tracker.bad_free_array {
            memories[bad_free.location] = true
        }

        for bad_free in memories {
            using bad_free

            rel_path := short_path(file_path)
            fmt.eprintfln(
                "│ %-35v │",
                fmt.aprintf(
                    "{}:{}:{}",
                    rel_path,
                    line,
                    column,
                    allocator = context.temp_allocator,
                ),
            )
        }

        fmt.eprintln(
            "└─────────────────────────────────────┘",
        )
    } else {
        fmt.eprintln("\nNo Bad Frees")
    }
}

short_path :: proc(file_path: string) -> string {
    src_loc := proc(
        loc := #caller_location,
    ) -> runtime.Source_Code_Location {return loc}(

    )
    src_dir := filepath.dir(src_loc.file_path, context.temp_allocator)

    rel_path, rel_err := filepath.rel(
        src_dir,
        file_path,
        context.temp_allocator,
    )
    if rel_err != .None {
        rel_path = file_path
    }

    if strings.contains(rel_path, "/core/") {
        elements := make([dynamic]string, context.temp_allocator)

        dir := rel_path
        file: string = ---
        for {
            dir, file = filepath.split(dir)
            append(&elements, file)
            if strings.has_suffix(dir, "core/") {
                append(&elements, "core:")
                break
            }
            dir = dir[:len(dir) - 1]
        }

        rel_str: strings.Builder
        strings.builder_init(&rel_str, context.temp_allocator)
        #reverse for e in elements {
            strings.write_string(&rel_str, e)
            if !strings.has_suffix(e, ".odin") && !strings.has_suffix(e, ":") {
                strings.write_rune(&rel_str, '/')
            }
        }

        rel_path = strings.to_string(rel_str)
    }

    return rel_path
}

