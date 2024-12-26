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

import ccdg "c/codegen"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import cppcdg "cpp/codegen"
import cppwrap "cpp/wrapper"
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
        platties := make(
            [dynamic]runic.Platform,
            allocator = context.temp_allocator,
            len = 0,
            cap = len(rune.platforms),
        )
        append(&platties, host_plat)
        plats = platties[:]
    }

    if wrapper, ok := rune.wrapper.?; ok {
        switch strings.to_lower(wrapper.language, context.temp_allocator) {
        case "c", "cpp", "c++", "cxx":
            from: Maybe(runic.From)
            if rf, rf_ok := rune.from.(runic.From); rf_ok {
                from = rf
            }

            err = errors.wrap(
                cppwrap.generate_wrapper(rune_file_name, plats, wrapper, from),
            )
        case:
            fmt.eprintfln(
                "wrapper language \"{}\" is not supported",
                wrapper.language,
            )
            os.exit(1)
        }

        if err != nil {
            fmt.eprintfln(
                "failed to generate wrapper for language \"{}\": {}",
                wrapper.language,
                err,
            )
            os.exit(1)
        }

        fmt.printfln(
            "Successfully generated wrapper for language \"{}\"",
            wrapper.language,
        )
    }

    runestones := make(
        [dynamic]runic.Runestone,
        allocator = context.temp_allocator,
        len = 0,
        cap = len(rune.platforms),
    )
    file_paths := make(
        [dynamic]string,
        allocator = context.temp_allocator,
        len = 0,
        cap = len(rune.platforms),
    )

    defer for &stone in runestones {
        runic.runestone_destroy(&stone)
    }

    switch from in rune.from {
    case runic.From:
        for plat in plats {
            rs: runic.Runestone = ---

            switch strings.to_lower(from.language, context.temp_allocator) {
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

            runic.from_postprocess_runestone(&rs, from)

            append(&runestones, rs)
            append(&file_paths, "")

            fmt.eprintfln(
                "\"{}\" Runestone {}.{} Success",
                from.language,
                plat.os,
                plat.arch,
            )
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

        append(&runestones, rs)
        append(&file_paths, rs_file_name)
    case [dynamic]string:
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

            append(&runestones, rs)
        }

        file_paths = from
    }

    switch to in rune.to {
    case runic.To:
        reserved_keywords: []string = ---
        switch strings.to_lower(to.language, context.temp_allocator) {
        case "c":
            reserved_keywords = ccdg.C_RESERVED
        case "odin":
            reserved_keywords = odincdg.ODIN_RESERVED
        case:
            fmt.eprintfln("To Language \"{}\" is not supported", to.language)
            os.exit(1)
        }

        for &rs in runestones {
            runic.to_preprocess_runestone(&rs, to, reserved_keywords)
        }

        fmt.eprintln("Crossing the runes ...")
        runecross, rc_err := runic.cross_the_runes(
            file_paths[:],
            runestones[:],
            to.extern.sources,
        )
        if rc_err != nil {
            fmt.eprintfln("failed to cross the runes: {}", rc_err)
            os.exit(1)
        }
        defer runic.runecross_destroy(&runecross, len(runestones) > 1)

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

        fmt.eprintfln("Writing bindings for \"{}\" ...", to.language)

        switch strings.to_lower(to.language, context.temp_allocator) {
        case "odin":
            err = errors.wrap(
                odincdg.generate_bindings(
                    runecross,
                    to,
                    rune.platforms,
                    os.stream_from_handle(out_file),
                    out_file_name,
                ),
            )
        case "c":
            err = errors.wrap(
                ccdg.generate_bindings(
                    runecross,
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
        rs_files := make(
            [dynamic]os.Handle,
            allocator = context.temp_allocator,
            len = 0,
            cap = len(runestones),
        )
        rs_file_paths := make(
            [dynamic]string,
            allocator = context.temp_allocator,
            len = 0,
            cap = len(runestones),
        )

        if to == "stdout" {
            if len(runestones) != 1 {
                fmt.eprintln(
                    "Unable to write multiple runestones to stdout. If you want to output the runestone to stdout you are only able to provide one platform",
                )
                os.exit(1)
            }
            append(&rs_files, os.stdout)
        } else {
            for rs in runestones {
                runestone_file_name := to
                if len(runestones) > 1 {
                    stem := filepath.stem(runestone_file_name)
                    ext := filepath.ext(runestone_file_name)
                    dir := filepath.dir(runestone_file_name)
                    file_name := fmt.aprintf(
                        "{}-{}.{}{}",
                        stem,
                        rs.platform.os,
                        rs.platform.arch,
                        ext,
                        allocator = context.temp_allocator,
                    )
                    runestone_file_name = filepath.join(
                        {dir, file_name},
                        context.temp_allocator,
                    )
                }

                rs_file_path := runic.relative_to_file(
                    rune_file_name,
                    runestone_file_name,
                    context.temp_allocator,
                )

                rs_file: os.Handle = ---
                rs_file, os_err = os.open(
                    rs_file_path,
                    os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
                    0o644,
                )
                if err = errors.wrap(os_err); err != nil {
                    fmt.eprintfln(
                        "failed to open to runestone file \"{}\": {}",
                        rs_file_path,
                        err,
                    )
                    return
                }

                append(&rs_files, rs_file)
                append(&rs_file_paths, rs_file_path)
            }
        }
        defer if to != "stdout" do for rs_file in rs_files {
            os.close(rs_file)
        }

        for rs, idx in runestones {
            if err = errors.wrap(
                runic.write_runestone(
                    rs,
                    os.stream_from_handle(rs_files[idx]),
                    to,
                ),
            ); err != nil {
                fmt.eprintfln(
                    "failed to write runestone {}.{}: {}",
                    rs.platform.os,
                    rs.platform.arch,
                    err,
                )
                os.exit(1)
            }

            fmt.eprintfln(
                "Successfully generated runestone {}.{} \"{}\"",
                rs.platform.os,
                rs.platform.arch,
                rs_file_paths[idx],
            )
        }
    }
}

