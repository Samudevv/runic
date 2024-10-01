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
import ccdg "c/codegen"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import cppcdg "cpp/codegen"
import "errors"
import odincdg "odin/codegen"
import "runic"

DEFAULT_TO_FILE_NAME :: "runic.to"

main :: proc() {
    when ODIN_DEBUG {
        alloc := context.allocator
        tracker, tracker_allocator := track_memory(context.allocator)
        defer free(tracker, alloc)
        defer print_track_results(tracker)
        context.allocator = tracker_allocator
    }

    defer free_all(context.temp_allocator)
    defer free_all(errors.error_allocator)

    rune_file_name := "./rune.yml"
    host_plat := runic.platform_from_host()

    if len(os.args) > 1 {
        rune_file_name = os.args[1]
    }

    if !filepath.is_abs(rune_file_name) {
        cwd := os.get_current_directory()
        defer delete(cwd)
        rune_file_name = filepath.join(
            {cwd, rune_file_name},
            context.temp_allocator,
        )
    }

    rune_file, os_err := os.open(rune_file_name)
    if err := errors.wrap(os_err); err != nil {
        fmt.eprintfln("failed to open rune file: {}", err)
        os.exit(1)
    }
    defer os.close(rune_file)

    err: errors.Error
    rune, rune_err := runic.parse_rune(
        os.stream_from_handle(rune_file),
        rune_file_name,
    )
    err = errors.wrap(rune_err)
    defer runic.rune_destroy(&rune)
    if err != nil {
        fmt.eprintfln("failed to parse rune file: {}", err)
        os.exit(1)
    }

    if rune.version != 0 {
        fmt.eprintfln("rune version {} is not supported", rune.version)
        os.exit(1)
    }

    plats: []runic.Platform = ---
    if len(rune.platforms) != 0 {
        plats = rune.platforms
    } else {
        platties := make([dynamic]runic.Platform, context.temp_allocator)
        append(&platties, host_plat)
        plats = platties[:]
    }

    from_rc: runic.Runecross
    from_rc.cross = make(
        [dynamic]runic.PlatformRunestone,
        context.temp_allocator,
    )
    defer delete(from_rc.arenas)
    defer for &arena in from_rc.arenas {
        runtime.arena_destroy(&arena)
    }

    switch from in rune.from {
    case runic.From:
        stones: [dynamic]runic.Runestone
        defer delete(stones)
        file_paths: [dynamic]string
        defer delete(file_paths)

        for plat in plats {
            rs: runic.Runestone = ---

            switch from.language {
            case "c", "cpp", "cxx", "c++":
                rs, err = cppcdg.generate_runestone(plat, rune_file_name, from)
            case "odin":
                when ODIN_OS == .FreeBSD {
                    fmt.eprintfln("from odin is not supported on FreeBSD")
                    os.exit(1)
                } else {
                    rs, err = odincdg.generate_runestone(
                        plat,
                        rune_file_name,
                        from,
                    )
                }
            case:
                fmt.eprintfln(
                    "from language {} is not supported",
                    from.language,
                )
                os.exit(1)
            }

            if err != nil {
                fmt.eprintfln(
                    "\"{}\" Runestone {}.{} Failed: {}",
                    from.language,
                    plat.os,
                    plat.arch,
                    err,
                )
                continue
            }

            append(&stones, rs)
            append(&file_paths, "")

            fmt.eprintfln(
                "\"{}\" Runestone {}.{} Success",
                from.language,
                plat.os,
                plat.arch,
            )
        }

        fmt.eprintln("Crossing the Runes ...")

        from_rc, err = runic.cross_the_runes(file_paths[:], stones[:])
        if err != nil {
            fmt.eprintfln("failed to cross the runes: {}", err)
            os.exit(1)
        }
    case string:
        rs_file: os.Handle = ---
        rs_file_name: string = ---
        if from == "stdin" {
            rs_file = os.stdin
            rs_file_name = "/stdin"
        } else {
            rs_file_name = runic.relative_to_file(
                rune_file_name,
                from,
                context.temp_allocator,
            )

            rs_file, os_err = os.open(rs_file_name)
            if err = errors.wrap(os_err); err != nil {
                fmt.eprintfln("failed to open runestone file: {}", err)
                os.exit(1)
            }
        }
        defer if from != "stdin" do os.close(rs_file)

        rs: runic.Runestone = ---
        rs, err = runic.parse_runestone(
            os.stream_from_handle(rs_file),
            rs_file_name,
        )
        if err != nil {
            fmt.eprintfln("failed to parse runestone: {}", err)
            os.exit(1)
        }

        fmt.eprintfln("Successfully parsed runestone ({})", from)

        append(
            &from_rc.cross,
            runic.PlatformRunestone {
                plats = {rs.platform},
                runestone = {file_path = rs_file_name, stone = rs},
            },
        )
        append(&from_rc.arenas, rs.arena)
    case [dynamic]string:
        stones: [dynamic]runic.Runestone
        defer delete(stones)

        for file_path in from {
            rs: runic.Runestone = ---
            rs_file: os.Handle = ---
            rs_file_name := runic.relative_to_file(
                rune_file_name,
                file_path,
                context.temp_allocator,
            )

            rs_file, os_err = os.open(rs_file_name)
            if err = errors.wrap(os_err); err != nil {
                fmt.eprintfln("failed to open runestone file: {}", err)
                os.exit(1)
            }
            defer os.close(rs_file)

            rs, err = runic.parse_runestone(
                os.stream_from_handle(rs_file),
                file_path,
            )
            if err != nil {
                fmt.eprintfln("failed to parse runestone: {}", err)
                os.exit(1)
            }

            fmt.eprintfln("Successfully parsed runestone ({})", file_path)

            append(&stones, rs)
        }

        fmt.eprintln("Crossing the Runes ...")

        from_rc, err = runic.cross_the_runes(from[:], stones[:])
        if err != nil {
            fmt.eprintfln("failed to cross the runes: {}", err)
            os.exit(1)
        }
    }

    switch to in rune.to {
    case runic.To:
        out_file_name: string
        make_out_name: if len(to.out) != 0 {
            abs_out := runic.relative_to_file(
                rune_file_name,
                to.out,
                context.temp_allocator,
            )

            dir := filepath.dir(abs_out)
            defer delete(dir)

            if !os.is_dir(dir) {
                err = errors.wrap(os.make_directory(dir))
                if err != nil {
                    fmt.eprintfln("failed to make output directory: {}", err)
                    os.exit(1)
                }
            }
            out_file_name = abs_out
        } else {
            out_file_name = DEFAULT_TO_FILE_NAME
        }

        out_file, out_err := os.open(
            out_file_name,
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if err = errors.wrap(out_err); err != nil {
            fmt.eprintfln("failed to open to file: {}", err)
            os.exit(1)
        }
        defer os.close(out_file)

        switch to.language {
        case "odin":
            err = errors.wrap(
                odincdg.generate_bindings(
                    from_rc,
                    to,
                    os.stream_from_handle(out_file),
                    out_file_name,
                ),
            )
        case "c":
            // TODO: update for Runecross
            err = errors.wrap(
                ccdg.generate_bindings(
                    from_rc.cross[0].platform,
                    from_rc.cross[0].stone,
                    to,
                    os.stream_from_handle(out_file),
                ),
            )
        case:
            fmt.eprintfln("to language {} is not supported", to.language)
            return
        }

        if err != nil {
            fmt.eprintfln(
                "failed to generate bindings ({}) for \"{}\": {}",
                out_file_name,
                to.language,
                err,
            )
            os.exit(1)
        }

        fmt.eprintfln(
            "Successfully generated bindings for \"{}\" ({})",
            to.language,
            out_file_name,
        )
    case string:
        rs_file: os.Handle = ---
        if to == "stdout" {
            rs_file = os.stdout
        } else {
            rs_file, os_err = os.open(
                runic.relative_to_file(
                    rune_file_name,
                    to,
                    context.temp_allocator,
                ),
                os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
                0o644,
            )
            if err = errors.wrap(os_err); err != nil {
                fmt.eprintfln("failed to open to runestone file: {}", err)
                return
            }
        }
        defer if to != "stdout" do os.close(rs_file)

        if err = errors.wrap(
            runic.write_runestone(
                from_rc.cross[0].stone,
                os.stream_from_handle(rs_file),
                to,
            ),
        ); err != nil {
            fmt.eprintfln("failed to write runestone: {}", err)
            os.exit(1)
        }

        fmt.eprintfln("Successfully generated runestone ({})", to)
    }
}

