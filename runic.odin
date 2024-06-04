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

    rune_file_name := "./rune.json"

    if len(os.args) == 2 {
        rune_file_name = os.args[1]
    } else if len(os.args) != 1 {
        fmt.eprintln("invalid arguments")
        os.exit(1)
    }

    rune_file, os_err := os.open(rune_file_name)
    if err := errors.wrap(os_err); err != nil {
        fmt.eprintfln("failed to open rune file: {}", err)
        os.exit(1)
    }
    defer os.close(rune_file)

    err: errors.Error
    rune, rune_err := runic.parse_rune(os.stream_from_handle(rune_file))
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

    from_rs: runic.Runestone
    defer runic.runestone_destroy(&from_rs)

    switch from in rune.from {
    case runic.From:
        switch from.language {
        case "c":
            from_rs, err = ccdg.generate_runestone(rune_file_name, from)
        case "odin":
            from_rs, err = odincdg.generate_runestone(rune_file_name, from)
        case:
            fmt.eprintfln("from language {} is not supported", from.language)
            os.exit(1)
        }

        if err != nil {
            fmt.eprintfln(
                "failed to generate runestone from language {}: {}",
                from.language,
                err,
            )
            os.exit(1)
        }

        fmt.printfln("Successfully parsed language \"{}\"", from.language)
    case string:
        rs_file: os.Handle = ---
        rs_file_name := runic.relative_to_file(
            rune_file_name,
            from,
            context.temp_allocator,
        )

        rs_file, os_err = os.open(rs_file_name)
        if err = errors.wrap(os_err); err != nil {
            fmt.eprintfln("failed to open runestone file: {}", err)
            os.exit(1)
        }
        defer os.close(rs_file)

        from_rs, err = runic.parse_runestone(os.stream_from_handle(rs_file))
        if err != nil {
            fmt.eprintfln("failed to parse runestone: {}", err)
            os.exit(1)
        }

        fmt.printfln("Successfully parsed runestone ({})", from)
    case [dynamic]string:
        fmt.eprintln("string array in from is not implemented")
        os.exit(1)
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
                    from_rs,
                    to,
                    os.stream_from_handle(out_file),
                ),
            )
        case "c":
            err = errors.wrap(
                ccdg.generate_bindings(
                    from_rs,
                    to,
                    os.stream_from_handle(out_file),
                ),
            )
        case:
            fmt.eprintfln("to language {} is not supported", to.language)
            return
        }

        if err != nil {
            fmt.eprintfln("failed to generate bindings ({}) for \"{}\": {}", out_file_name, to.language, err)
            os.exit(1)
        }

        fmt.printfln("Successfully generated bindings for \"{}\" ({})", to.language, out_file_name)
    case string:
        rs_file: os.Handle = ---
        rs_file, os_err = os.open(
            runic.relative_to_file(rune_file_name, to, context.temp_allocator),
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if err = errors.wrap(os_err); err != nil {
            fmt.eprintfln("failed to open to runestone file: {}", err)
            return
        }
        defer os.close(rs_file)

        if err = errors.wrap(
            runic.write_runestone(from_rs, os.stream_from_handle(rs_file)),
        ); err != nil {
            fmt.eprintfln("failed to write runestone: {}", err)
            os.exit(1)
        }

        fmt.printfln("Successfully generated runestone ({})", to)
    }
}
