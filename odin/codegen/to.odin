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
package odin_codegen

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:path/slashpath"
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

@(private)
AddLibs :: struct {
    plat: runic.Platform,
    libs: []string,
}

@(private = "file")
ImportGroup :: struct {
    imports:       []string,
    cross_indices: [dynamic]int,
    plats:         [dynamic]runic.Platform,
}

@(private = "file")
RunestoneWriter :: struct {
    wd:        Maybe(io.Writer),
    file_path: string,
}

generate_bindings :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    platforms: []runic.Platform,
    wd: io.Writer,
    file_path: string,
) -> union {
        errors.Error,
        io.Error,
    } {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)


    // Handle Imports
    // Only write out imports that are actually needed
    // If imports differ per runestone write the runestones into separate files

    // 1. First construct a list for every runestone that contains all the imports that this runestone uses
    runestone_imports := make(
        [dynamic][dynamic]string,
        len = len(rc.cross),
        cap = len(rc.cross),
        allocator = arena_alloc,
    )

    for rs, idx in rc.cross {
        rs_imps := &runestone_imports[idx]
        rs_imps^ = make(
            [dynamic]string,
            len = 0,
            cap = len(rn.extern.sources),
            allocator = arena_alloc,
        )

        // Loop over the types
        for entry in rs.types.data {
            type := entry.value

            #partial switch spec in type.spec {
            case runic.ExternType:
                extern_source, source_found :=
                    runic.source_of_extern_type_from_runecross(spec, rc)
                if source_found &&
                   !slice.contains(rs_imps^[:], extern_source) {
                    append(rs_imps, extern_source)
                }
            case runic.Struct:
                for m in spec.members {
                    #partial switch mt in m.type.spec {
                    case runic.ExternType:
                        extern_source, source_found :=
                            runic.source_of_extern_type_from_runecross(mt, rc)
                        if source_found &&
                           !slice.contains(rs_imps^[:], extern_source) {
                            append(rs_imps, extern_source)
                        }
                    }
                }
            case runic.Union:
                for m in spec.members {
                    #partial switch mt in m.type.spec {
                    case runic.ExternType:
                        extern_source, source_found :=
                            runic.source_of_extern_type_from_runecross(mt, rc)
                        if source_found &&
                           !slice.contains(rs_imps^[:], extern_source) {
                            append(rs_imps, extern_source)
                        }
                    }
                }
            case runic.FunctionPointer:
                for p in spec.parameters {
                    #partial switch pt in p.type.spec {
                    case runic.ExternType:
                        extern_source, source_found :=
                            runic.source_of_extern_type_from_runecross(pt, rc)
                        if source_found &&
                           !slice.contains(rs_imps^[:], extern_source) {
                            append(rs_imps, extern_source)
                        }
                    }
                }

                #partial switch pt in spec.return_type.spec {
                case runic.ExternType:
                    extern_source, source_found :=
                        runic.source_of_extern_type_from_runecross(pt, rc)
                    if source_found &&
                       !slice.contains(rs_imps^[:], extern_source) {
                        append(rs_imps, extern_source)
                    }
                }
            }
        }

        // Loop over the symbols
        for entry in rs.symbols.data {
            symbol := entry.value

            switch sym in symbol.value {
            case runic.Type:
                #partial switch spec in sym.spec {
                case runic.ExternType:
                    extern_source, source_found :=
                        runic.source_of_extern_type_from_runecross(spec, rc)
                    if source_found &&
                       !slice.contains(rs_imps^[:], extern_source) {
                        append(rs_imps, extern_source)
                    }
                case runic.Struct:
                    for m in spec.members {
                        #partial switch mt in m.type.spec {
                        case runic.ExternType:
                            extern_source, source_found :=
                                runic.source_of_extern_type_from_runecross(
                                    mt,
                                    rc,
                                )
                            if source_found &&
                               !slice.contains(rs_imps^[:], extern_source) {
                                append(rs_imps, extern_source)
                            }
                        }
                    }
                case runic.Union:
                    for m in spec.members {
                        #partial switch mt in m.type.spec {
                        case runic.ExternType:
                            extern_source, source_found :=
                                runic.source_of_extern_type_from_runecross(
                                    mt,
                                    rc,
                                )
                            if source_found &&
                               !slice.contains(rs_imps^[:], extern_source) {
                                append(rs_imps, extern_source)
                            }
                        }
                    }
                case runic.FunctionPointer:
                    for p in spec.parameters {
                        #partial switch pt in p.type.spec {
                        case runic.ExternType:
                            extern_source, source_found :=
                                runic.source_of_extern_type_from_runecross(
                                    pt,
                                    rc,
                                )
                            if source_found &&
                               !slice.contains(rs_imps^[:], extern_source) {
                                append(rs_imps, extern_source)
                            }
                        }
                    }

                    #partial switch pt in spec.return_type.spec {
                    case runic.ExternType:
                        extern_source, source_found :=
                            runic.source_of_extern_type_from_runecross(pt, rc)
                        if source_found &&
                           !slice.contains(rs_imps^[:], extern_source) {
                            append(rs_imps, extern_source)
                        }
                    }
                }
            case runic.Function:
                for p in sym.parameters {
                    #partial switch pt in p.type.spec {
                    case runic.ExternType:
                        extern_source, source_found :=
                            runic.source_of_extern_type_from_runecross(pt, rc)
                        if source_found &&
                           !slice.contains(rs_imps^[:], extern_source) {
                            append(rs_imps, extern_source)
                        }
                    }
                }

                #partial switch pt in sym.return_type.spec {
                case runic.ExternType:
                    extern_source, source_found :=
                        runic.source_of_extern_type_from_runecross(pt, rc)
                    if source_found &&
                       !slice.contains(rs_imps^[:], extern_source) {
                        append(rs_imps, extern_source)
                    }
                }
            }
        }
    }

    // 2. Group matching import lists. Two import lists can be grouped together if
    //          1. The imports lists match exactly or
    //          2. The import list comes from a more common runestone and the import list is contained in the other one
    grouped_imports := make(
        [dynamic]ImportGroup,
        len = 0,
        cap = len(rc.cross),
        allocator = arena_alloc,
    )

    group_imports_loop: for rs_imps, rs_idx in runestone_imports {
        rs := rc.cross[rs_idx]

        for &imp_group in grouped_imports {
            // Does it match?

            // 1. The import group matches exactly
            if len(rs_imps) == len(imp_group.imports) {
                matches_exactly := true
                for rs_imp in rs_imps {
                    if !slice.contains(imp_group.imports, rs_imp) {
                        matches_exactly = false
                        break
                    }
                }

                if matches_exactly {
                    append(&imp_group.cross_indices, rs_idx)
                    for plat in rs.plats {
                        if !slice.contains(imp_group.plats[:], plat) {
                            append(&imp_group.plats, plat)
                        }
                    }
                    continue group_imports_loop
                }
            }

            // 2. Check if more common and stuff
            has_more_common_rs := false
            for imp_group_idx in imp_group.cross_indices {
                imp_group_rs := rc.cross[imp_group_idx]
                if runic.multiple_platforms_match(
                    imp_group_rs.plats,
                    rs.plats,
                ) {
                    has_more_common_rs = true
                    break
                }
            }

            if has_more_common_rs {
                imports_are_contained := true
                for rs_imp in rs_imps {
                    if !slice.contains(imp_group.imports, rs_imp) {
                        imports_are_contained = false
                        break
                    }
                }

                if imports_are_contained {
                    append(&imp_group.cross_indices, rs_idx)
                    for plat in rs.plats {
                        if !slice.contains(imp_group.plats[:], plat) {
                            append(&imp_group.plats, plat)
                        }
                    }
                    continue group_imports_loop
                }
            }
        }

        // If nothing matches create a new entry
        imp_group := ImportGroup {
            imports       = rs_imps[:],
            cross_indices = make(
                [dynamic]int,
                len = 1,
                cap = len(rc.cross),
                allocator = arena_alloc,
            ),
            plats         = make(
                [dynamic]runic.Platform,
                len = 0,
                cap = len(platforms),
                allocator = arena_alloc,
            ),
        }
        imp_group.cross_indices[0] = rs_idx
        append(&imp_group.plats, ..rs.plats)

        append(&grouped_imports, imp_group)
    }

    when ODIN_DEBUG {
        for imp_group in grouped_imports {
            fmt.println("debug: ---- Import Group ----")
            fmt.println("debug: Plats: ", imp_group.plats)
            fmt.print("debug: Imports:")
            for imp in imp_group.imports {
                fmt.print(" ", imp)
            }
            fmt.println()
            fmt.println("debug: ----------------------")
        }
    }

    // 3. Create file names for the different import groups
    runestone_writers := make(
        [dynamic]RunestoneWriter,
        len = 0,
        cap = len(grouped_imports),
        allocator = arena_alloc,
    )
    opened_handles := make(
        [dynamic]os.Handle,
        len = 0,
        cap = len(grouped_imports),
        allocator = arena_alloc,
    )
    defer for hd in opened_handles do os.close(hd)

    for imp_group in grouped_imports {
        // If it's any any, use the current writer
        is_any_any := slice.contains(
            imp_group.plats[:],
            runic.Platform{.Any, .Any},
        )

        if is_any_any {
            append(
                &runestone_writers,
                RunestoneWriter{wd = wd, file_path = file_path},
            )
        } else {
            mini_plats := runic.minimize_platforms(
                platforms,
                imp_group.plats[:],
                rn.ignore_arch,
            )
            defer delete(mini_plats)

            imp_file_name := runic.multiple_platforms_file_name(
                file_path,
                mini_plats[:],
            )
            defer delete(imp_file_name)

            imp_wd: Maybe(io.Writer)
            imp_file, imp_file_err := os.open(
                imp_file_name,
                os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
                0o666,
            )
            if imp_file_err != nil {
                when ODIN_DEBUG {
                    fmt.eprintfln(
                        "debug: failed to create file for different platforms {}",
                        mini_plats,
                    )
                }
            } else {
                imp_wd = os.stream_from_handle(imp_file)
                append(&opened_handles, imp_file)
            }

            append(
                &runestone_writers,
                RunestoneWriter {
                    wd = imp_wd,
                    file_path = strings.clone(imp_file_name, arena_alloc),
                },
            )
        }
    }

    // 4. Loop over all the runestone writers, create the list of imports and write to the file
    for rs_writer, imp_idx in runestone_writers {
        if rs_writer.wd == nil do continue

        rs_wd := rs_writer.wd.?
        rs_file_path := rs_writer.file_path
        imp_group := grouped_imports[imp_idx]

        write_build_tag: if !rn.no_build_tag {
            // Construct a list of all platforms that need to be part of the build tag
            build_tag_plats := make(
                [dynamic]runic.Platform,
                len = 0,
                cap = len(platforms),
            )
            defer delete(build_tag_plats)

            for plat in imp_group.plats {
                for rn_plat in platforms {
                    if runic.platform_matches(plat, rn_plat) {
                        append(&build_tag_plats, rn_plat)
                    }
                }
            }

            unique_plats := make(
                [dynamic]runic.Platform,
                len = 0,
                cap = len(build_tag_plats),
            )
            defer delete(unique_plats)

            for plat in build_tag_plats {
                tag_plat := plat
                if rn.ignore_arch {
                    tag_plat.arch = .Any
                }
                if !slice.contains(unique_plats[:], tag_plat) {
                    append(&unique_plats, tag_plat)
                }
            }

            if len(unique_plats) == 0 do break write_build_tag

            slice.sort_by(unique_plats[:], runic.platform_less)

            for plat, plat_idx in unique_plats {
                if plat_idx == 0 {
                    io.write_string(rs_wd, "#+build ") or_return
                }

                os_names: []string = ---

                switch plat.os {
                case .Any:
                    os_names = []string{}
                case .Linux:
                    os_names = []string{"linux"}
                case .Windows:
                    os_names = []string{"windows"}
                case .Macos:
                    os_names = []string{"darwin"}
                case .BSD:
                    os_names = []string{"freebsd", "openbsd", "netbsd"}
                }

                if len(os_names) != 0 {
                    for os, os_idx in os_names {
                        io.write_string(rs_wd, os) or_return
                        if plat.arch != .Any {
                            io.write_rune(rs_wd, ' ') or_return
                            switch plat.arch {
                            case .Any:
                            case .x86_64:
                                io.write_string(rs_wd, "amd64") or_return
                            case .arm64:
                                io.write_string(rs_wd, "arm64") or_return
                            case .x86:
                                io.write_string(rs_wd, "i386") or_return
                            case .arm32:
                                io.write_string(rs_wd, "arm32") or_return
                            }
                        }

                        if os_idx != len(os_names) - 1 {
                            io.write_string(rs_wd, ", ") or_return
                        }
                    }
                } else {
                    switch plat.arch {
                    case .Any:
                    case .x86_64:
                        io.write_string(rs_wd, "amd64") or_return
                    case .arm64:
                        io.write_string(rs_wd, "arm64") or_return
                    case .x86:
                        io.write_string(rs_wd, "i386") or_return
                    case .arm32:
                        io.write_string(rs_wd, "arm32") or_return
                    }
                }

                if plat_idx == len(unique_plats) - 1 {
                    io.write_rune(rs_wd, '\n') or_return
                } else {
                    io.write_string(rs_wd, ", ") or_return
                }
            }
        }

        io.write_string(rs_wd, "package ") or_return

        // Make sure that package name is not invalid
        package_name := rn.package_name
        ODIN_PACKAGE_INVALID :: [?]string{" ", "-", "?", "&", "|", "/", "\\"} // NOTE: more are invalid, but let's stop here
        for str in ODIN_PACKAGE_INVALID {
            package_name, _ = strings.replace(
                package_name,
                str,
                "_",
                -1,
                arena_alloc,
            )
        }
        if slice.contains(ODIN_RESERVED, package_name) {
            package_name = strings.concatenate(
                {package_name, "_"},
                arena_alloc,
            )
        }

        io.write_string(rs_wd, package_name) or_return
        io.write_string(rs_wd, "\n\n") or_return


        // Write all imports for the extern types
        imports := make(
            [dynamic][2]string,
            allocator = arena_alloc,
            len = 0,
            cap = len(imp_group.imports),
        )

        for imp in imp_group.imports {
            imp_name, imp_name_ok := runic.map_glob(rn.extern.sources, imp)
            if !imp_name_ok do continue

            import_name_overwrite, import_path_name := import_path(imp_name)
            import_source := [2]string{import_name_overwrite, import_path_name}
            if !slice.contains(imports[:], import_source) {
                append(&imports, import_source)
            }
        }

        slice.sort_by(imports[:], proc(i, j: [2]string) -> bool {
            name_i := i[0] if len(i[0]) != 0 else i[1]
            name_j := j[0] if len(j[0]) != 0 else j[1]

            return name_i < name_j
        })

        for importy in imports {
            import_name_overwrite, import_path_name := importy[0], importy[1]
            io.write_string(rs_wd, "import ") or_return
            if len(import_name_overwrite) != 0 {
                io.write_string(rs_wd, import_name_overwrite) or_return
                io.write_rune(rs_wd, ' ') or_return
            }
            io.write_rune(rs_wd, '"') or_return
            io.write_string(rs_wd, import_path_name) or_return
            io.write_string(rs_wd, "\"\n") or_return
        }
        if len(imports) != 0 do io.write_rune(rs_wd, '\n') or_return

        // Loop over all runestones of the import group
        write_when := false
        for cross_idx, idx in imp_group.cross_indices {
            rs := rc.cross[cross_idx]

            rs_builder: strings.Builder
            defer strings.builder_destroy(&rs_builder)
            // Determine which add libs fit this specific runestone
            add_libs_static := add_libs_for_runestone(
                rs.plats,
                rn.add_libs_static,
            )
            add_libs_shared := add_libs_for_runestone(
                rs.plats,
                rn.add_libs_shared,
            )
            defer delete(add_libs_static)
            defer delete(add_libs_shared)

            errors.wrap(
                generate_bindings_from_runestone(
                    rs,
                    rn,
                    strings.to_stream(&rs_builder),
                    rs_file_path,
                    package_name,
                    add_libs_static,
                    add_libs_shared,
                ),
            ) or_return

            rs_str := strings.to_string(rs_builder)
            if len(rs_str) != 0 {
                if len(imp_group.cross_indices) != 1 {
                    if rn.use_when_else &&
                       idx == len(imp_group.cross_indices) - 1 &&
                       write_when {
                        io.write_string(rs_wd, "{\n\n") or_return
                    } else {
                        write_when = when_plats(
                            rs_wd,
                            platforms,
                            rs.plats,
                            rn.ignore_arch,
                        ) or_return
                    }
                }

                io.write_string(rs_wd, rs_str) or_return

                if len(imp_group.cross_indices) != 1 && write_when {
                    io.write_rune(rs_wd, '}') or_return
                    if rn.use_when_else &&
                       idx != len(imp_group.cross_indices) - 1 {
                        io.write_string(rs_wd, " else ") or_return
                    } else {
                        io.write_string(rs_wd, "\n\n") or_return
                    }
                }
            }
        }

        // Generate all foreign import statements relevant for the file

        // 1. Only generate them if we have symbols
        have_symbols := false
        for cross_idx in imp_group.cross_indices {
            rs := rc.cross[cross_idx]
            if om.length(rs.symbols) != 0 {
                have_symbols = true
                break
            }
        }

        if have_symbols {
            // 2. Get list of all runestones that are relevant for the file and have libraries
            relevant_runestones := make(
                [dynamic]int,
                len = 0,
                cap = len(rc.cross),
                allocator = arena_alloc,
            )

            for rs, rs_idx in rc.cross {
                if (rs.lib.shared != nil || rs.lib.static != nil) &&
                   runic.multiple_platforms_any_match(
                       imp_group.plats[:],
                       rs.plats,
                   ) {
                    append(&relevant_runestones, rs_idx)
                }
            }

            // 3. Loop over them and generate when statements and foreign import statements
            write_when = false
            for rs_idx, idx in relevant_runestones {
                rs := rc.cross[rs_idx]

                if len(imp_group.cross_indices) != 1 {
                    if rn.use_when_else &&
                       idx == len(relevant_runestones) - 1 &&
                       write_when {
                        io.write_string(rs_wd, "{\n\n") or_return
                    } else {
                        write_when = when_plats(
                            rs_wd,
                            platforms,
                            rs.plats,
                            rn.ignore_arch,
                        ) or_return
                    }
                }

                // Determine which add libs fit this specific runestone
                add_libs_static := add_libs_for_runestone(
                    rs.plats,
                    rn.add_libs_static,
                )
                add_libs_shared := add_libs_for_runestone(
                    rs.plats,
                    rn.add_libs_shared,
                )
                defer delete(add_libs_static)
                defer delete(add_libs_shared)


                write_complete_foreign_import(
                    rs_wd,
                    rs_file_path,
                    rs.plats,
                    rs.lib,
                    package_name,
                    rn.static_switch,
                    add_libs_static,
                    add_libs_shared,
                    rn.ignore_arch,
                ) or_return

                if len(imp_group.cross_indices) != 1 && write_when {
                    io.write_rune(rs_wd, '}') or_return
                    if rn.use_when_else &&
                       idx != len(relevant_runestones) - 1 {
                        io.write_string(rs_wd, " else ") or_return
                    } else {
                        io.write_string(rs_wd, "\n\n") or_return
                    }
                }
            }
        }
    }

    return .None
}

generate_bindings_from_runestone :: proc(
    rs: runic.PlatformRunestone,
    rn: runic.To,
    wd: io.Writer,
    file_path: string,
    package_name: string,
    add_libs_static: [dynamic]AddLibs,
    add_libs_shared: [dynamic]AddLibs,
) -> union {
        errors.Error,
        io.Error,
    } {
    for entry in rs.constants.data {
        name, const := entry.key, entry.value

        io.write_string(wd, name) or_return
        io.write_string(wd, " :: ") or_return
        switch value in const.value {
        case i64:
            io.write_i64(wd, value) or_return
        case f64:
            io.write_f64(wd, value) or_return
        case string:
            if len(value) == 0 {
                io.write_string(wd, "\"\"")
            } else {
                if b, b_ok := const.type.spec.(runic.Builtin);
                   b_ok && b == .String {
                    io.write_rune(wd, '"') or_return
                    io.write_string(wd, value) or_return
                    io.write_rune(wd, '"') or_return
                } else {
                    io.write_rune(wd, '`') or_return
                    io.write_string(wd, value) or_return
                    io.write_rune(wd, '`') or_return
                }
            }
        case:
            io.write_rune(wd, '0') or_return
        }
        io.write_rune(wd, '\n') or_return
    }

    if om.length(rs.constants) != 0 do io.write_rune(wd, '\n') or_return

    for entry in rs.externs.data {
        name, extern := entry.key, entry.value

        if _, ok := runic.map_glob(rn.extern.sources, extern.source); !ok {
            if b, b_ok := extern.spec.(runic.Builtin); b_ok && b == .Untyped {
                return errors.Error(
                    errors.message(
                        "extern type \"{}\" differs by platform and does not have a source defined. Please define a source for \"{}\" under to.extern.sources",
                        name,
                        extern.source,
                    ),
                )
            }

            type_build: strings.Builder
            defer strings.builder_destroy(&type_build)
            ts := strings.to_stream(&type_build)

            io.write_string(ts, name) or_return
            io.write_string(ts, " :: ") or_return
            type_err := write_type(ts, name, extern, rn, rs.externs)
            if type_err != nil {
                fmt.eprintfln("{}: {}", name, type_err)
                continue
            }
            io.write_string(wd, strings.to_string(type_build)) or_return
            io.write_string(wd, "\n") or_return
        }
    }

    for entry in rs.types.data {
        name, ty := entry.key, entry.value

        type_build: strings.Builder
        defer strings.builder_destroy(&type_build)
        ts := strings.to_stream(&type_build)

        io.write_string(ts, name) or_return
        io.write_string(ts, " :: ") or_return
        type_err := write_type(ts, name, ty, rn, rs.externs)
        if type_err != nil {
            fmt.eprintfln("{}: {}", name, type_err)
            continue
        }
        io.write_string(wd, strings.to_string(type_build)) or_return
        io.write_string(wd, "\n") or_return
    }

    if om.length(rs.types) != 0 do io.write_rune(wd, '\n') or_return

    if om.length(rs.symbols) != 0 {
        io.write_string(
            wd,
            "@(default_calling_convention = \"c\")\n",
        ) or_return
        fmt.wprintf(wd, "foreign {}_runic {{\n", package_name)

        for entry in rs.symbols.data {
            name, sym := entry.key, entry.value
            fmt.wprintf(
                wd,
                "    @(link_name = \"{}\")\n",
                sym.remap.? or_else name,
            )
            io.write_string(wd, "    ") or_return

            switch value in sym.value {
            case runic.Type:
                type_bd: strings.Builder
                strings.builder_init(&type_bd)
                defer strings.builder_destroy(&type_bd)

                type_err := write_type(
                    strings.to_stream(&type_bd),
                    name,
                    value,
                    rn,
                    rs.externs,
                )
                if type_err != nil {
                    fmt.eprintfln("{}: {}", name, type_err)
                    io.write_string(wd, name) or_return
                    io.write_string(wd, ": rawptr\n\n") or_return
                    continue
                }

                io.write_string(wd, name) or_return
                io.write_string(wd, ": ") or_return
                io.write_string(wd, strings.to_string(type_bd)) or_return
            case runic.Function:
                io.write_string(wd, name) or_return
                io.write_string(wd, " :: ") or_return
                proc_err := write_procedure(wd, value, rn, rs.externs, nil)
                if proc_err != nil {
                    fmt.eprintfln("{}: {}", name, proc_err)
                    io.write_string(
                        wd,
                        "proc (invalid_procedure: ^^^rawptr, error_while_generating_procedure: ^^^^rawptr) ---\n\n",
                    ) or_return
                    continue
                }
                io.write_string(wd, " ---") or_return
            }
            io.write_string(wd, "\n\n") or_return
        }

        io.write_string(wd, "}\n\n") or_return

        for entry in rs.symbols.data {
            name, sym := entry.key, entry.value

            for alias in sym.aliases {
                switch sym_value in sym.value {
                case runic.Type:
                    io.write_string(wd, alias) or_return
                    if func_ptr, ok := recursive_get_pure_func_ptr(
                        sym_value,
                        rs.types,
                    ); ok {
                        io.write_string(wd, " :: #force_inline ")
                        proc_err := write_procedure(
                            wd,
                            func_ptr^,
                            rn,
                            rs.externs,
                            "contextless",
                        )
                        if proc_err != nil {
                            fmt.eprintfln("{} ({}): {}", alias, name, proc_err)
                            io.write_string(
                                wd,
                                "proc \"contextless\" () {}\n\n",
                            )
                            continue
                        }
                        io.write_string(wd, " {\n") or_return

                        if b, b_ok := func_ptr.return_type.spec.(runic.Builtin);
                           b_ok && b == .Untyped {
                            io.write_string(wd, "    ") or_return
                        } else {
                            io.write_string(wd, "    return ") or_return
                        }

                        io.write_string(wd, name) or_return
                        io.write_rune(wd, '(') or_return
                        for p, p_idx in func_ptr.parameters {
                            io.write_string(wd, p.name) or_return
                            if p_idx != len(func_ptr.parameters) - 1 {
                                io.write_string(wd, ", ") or_return
                            }
                        }
                        io.write_string(wd, ")\n}") or_return
                    } else {
                        sym_build: strings.Builder
                        defer strings.builder_destroy(&sym_build)
                        ss := strings.to_stream(&sym_build)

                        io.write_string(
                            ss,
                            " :: #force_inline proc \"contextless\" () -> ",
                        ) or_return
                        type_err := write_type(
                            ss,
                            name,
                            sym_value,
                            rn,
                            rs.externs,
                        )
                        if type_err != nil {
                            fmt.eprintfln("{}: {}", name, type_err)
                            io.write_string(
                                wd,
                                "string { return \"failed to write return type\" }\n\n",
                            ) or_return
                            continue
                        }
                        io.write_string(ss, " {\n    return ") or_return
                        io.write_string(ss, name) or_return
                        io.write_string(ss, "\n}") or_return
                        io.write_string(
                            wd,
                            strings.to_string(sym_build),
                        ) or_return
                    }
                case runic.Function:
                    io.write_string(wd, alias) or_return
                    io.write_string(wd, " :: ") or_return
                    io.write_string(wd, name) or_return
                }
                io.write_string(wd, "\n\n") or_return
            }
        }
    }

    return .None
}

write_procedure :: proc(
    wd: io.Writer,
    fc: runic.Function,
    rn: runic.To,
    externs: om.OrderedMap(string, runic.Extern),
    calling_convention: Maybe(string) = "c",
) -> union {
        io.Error,
        errors.Error,
    } {
    proc_build: strings.Builder
    defer strings.builder_destroy(&proc_build)
    ps := strings.to_stream(&proc_build)

    io.write_string(ps, "proc") or_return
    if cc, ok := calling_convention.?; ok {
        io.write_string(ps, " \"") or_return
        io.write_string(ps, cc) or_return
        io.write_string(ps, "\" ") or_return
    }
    io.write_string(ps, "(") or_return

    for p, idx in fc.parameters {
        type_bd: strings.Builder
        strings.builder_init(&type_bd)
        defer strings.builder_destroy(&type_bd)

        write_type(
            strings.to_stream(&type_bd),
            p.name,
            p.type,
            rn,
            externs,
        ) or_return

        io.write_string(ps, p.name) or_return
        io.write_string(ps, ": ") or_return
        io.write_string(ps, strings.to_string(type_bd)) or_return

        if idx != len(fc.parameters) - 1 || fc.variadic {
            io.write_string(ps, ", ") or_return
        }
    }

    if fc.variadic {
        io.write_string(ps, "#c_vararg var_args: ..any") or_return
    }

    io.write_rune(ps, ')') or_return

    if b, ok := fc.return_type.spec.(runic.Builtin); ok && b == .Untyped {
        io.write_string(wd, strings.to_string(proc_build)) or_return
        return nil
    }

    io.write_string(ps, " -> ") or_return
    write_type(ps, "", fc.return_type, rn, externs) or_return

    io.write_string(wd, strings.to_string(proc_build)) or_return

    return nil
}

write_type :: proc(
    wd: io.Writer,
    var_name: string,
    ty: runic.Type,
    rn: runic.To,
    externs: om.OrderedMap(string, runic.Extern),
) -> (
    err: union {
        io.Error,
        errors.Error,
    },
) {
    pointer_count := int(ty.pointer_info.count)

    if u, ok := ty.spec.(runic.Unknown); ok {
        if pointer_count >= 1 {
            pointer_count -= 1
        } else {
            return errors.Error(errors.message("type \"{}\" is unknown", u))
        }
    }

    is_multi_pointer: bool

    switch rn.detect.multi_pointer {
    case "auto":
        is_array_and_pointer :=
            len(ty.array_info) != 0 &&
            ty.array_info[len(ty.array_info) - 1].pointer_info.count != 0

        if (is_array_and_pointer ||
               (len(ty.array_info) == 0 && pointer_count >= 1)) &&
           len(var_name) > 1 &&
           strings.has_suffix(var_name, "s") {
            is_multi_pointer = true
            if is_array_and_pointer {
                ty.array_info[len(ty.array_info) - 1].pointer_info.count -= 1
            } else {
                pointer_count -= 1
            }
        }
    }

    if is_multi_pointer {
        io.write_string(wd, "[^]") or_return
    }

    #reverse for a in ty.array_info {
        pointer, pointer_err := strings.repeat("^", int(a.pointer_info.count))
        if pointer_err != .None {
            return errors.Error(
                errors.message("failed to create pointer string for array"),
            )
        }
        if len(pointer) != 0 {
            io.write_string(wd, pointer) or_return
            delete(pointer)
        }

        io.write_rune(wd, '[') or_return
        if a.size == nil {
            io.write_rune(wd, '^') or_return
        } else {
            fmt.wprint(wd, a.size)
        }
        io.write_rune(wd, ']') or_return
    }

    pointer, pointer_err := strings.repeat("^", pointer_count)
    if pointer_err != .None do return errors.Error(errors.message("failed to create pointer string"))

    if len(pointer) != 0 {
        io.write_string(wd, pointer) or_return
        delete(pointer)
    }

    switch spec in ty.spec {
    case runic.Builtin:
        write_builtin_type(wd, spec) or_return
    case runic.Struct:
        if len(spec.members) == 0 {
            io.write_string(wd, "struct {}") or_return
        } else {
            io.write_string(wd, "struct {\n") or_return
            for m in spec.members {

                type_bd: strings.Builder
                strings.builder_init(&type_bd)
                defer strings.builder_destroy(&type_bd)

                write_type(
                    strings.to_stream(&type_bd),
                    m.name,
                    m.type,
                    rn,
                    externs,
                ) or_return

                io.write_string(wd, "    ") or_return
                io.write_string(wd, m.name) or_return
                io.write_string(wd, ": ") or_return
                io.write_string(wd, strings.to_string(type_bd)) or_return
                io.write_string(wd, ",\n") or_return
            }
            io.write_rune(wd, '}') or_return
        }
    case runic.Enum:
        io.write_string(wd, "enum ") or_return
        write_builtin_type(wd, spec.type) or_return
        io.write_string(wd, " {") or_return
        for e, idx in spec.entries {
            // TODO: add new lines between enum values
            io.write_string(wd, e.name) or_return
            io.write_string(wd, " = ") or_return

            switch v in e.value {
            case i64:
                io.write_i64(wd, v) or_return
            case string:
                io.write_string(wd, v) or_return
            case:
                io.write_string(wd, "nil") or_return
            }

            if idx < len(spec.entries) - 1 {
                io.write_rune(wd, ',') or_return
            }
            io.write_rune(wd, ' ') or_return
        }
        io.write_rune(wd, '}') or_return
    case runic.Union:
        if len(spec.members) == 0 {
            io.write_string(wd, "struct #raw_union {}") or_return
        } else {
            io.write_string(wd, "struct #raw_union {\n") or_return
            for m in spec.members {
                type_bd: strings.Builder
                strings.builder_init(&type_bd)
                defer strings.builder_destroy(&type_bd)

                write_type(
                    strings.to_stream(&type_bd),
                    m.name,
                    m.type,
                    rn,
                    externs,
                ) or_return

                io.write_string(wd, "    ") or_return
                io.write_string(wd, m.name) or_return
                io.write_string(wd, ": ") or_return
                io.write_string(wd, strings.to_string(type_bd)) or_return
                io.write_string(wd, ",\n") or_return
            }
            io.write_rune(wd, '}') or_return
        }
    case string:
        io.write_string(wd, spec) or_return
    case runic.Unknown:
        io.write_string(wd, "rawptr") or_return
    case runic.FunctionPointer:
        io.write_string(wd, "#type ") or_return
        write_procedure(wd, spec^, rn, externs) or_return
    case runic.ExternType:
        type_name := rn.extern.remaps[string(spec)] or_else string(spec)

        if extern, ok := om.get(externs, string(spec)); ok {
            import_name, import_ok := runic.map_glob(
                rn.extern.sources,
                extern.source,
            )

            if !import_ok {
                io.write_string(wd, type_name) or_return
            } else {
                prefix := import_prefix(import_name)
                io.write_string(wd, prefix) or_return
                io.write_rune(wd, '.') or_return
                io.write_string(wd, type_name) or_return
            }
        } else {
            io.write_string(wd, type_name) or_return

            when ODIN_DEBUG {
                fmt.eprintfln(
                    "debug: extern type \"{}\" has not been defined in the extern section",
                    spec,
                )
            }
        }
    }

    return
}

write_builtin_type :: proc(wd: io.Writer, ty: runic.Builtin) -> io.Error {
    switch ty {
    case .Untyped:
        io.write_string(wd, "ThisTypeIsUntyped") or_return
    case .RawPtr:
        io.write_string(wd, "rawptr") or_return
    case .SInt8:
        io.write_string(wd, "i8") or_return
    case .SInt16:
        io.write_string(wd, "i16") or_return
    case .SInt32:
        io.write_string(wd, "i32") or_return
    case .SInt64:
        io.write_string(wd, "i64") or_return
    case .SInt128:
        io.write_string(wd, "i128") or_return
    case .SIntX:
        io.write_string(wd, "int") or_return
    case .UInt8:
        io.write_string(wd, "u8") or_return
    case .UInt16:
        io.write_string(wd, "u16") or_return
    case .UInt32:
        io.write_string(wd, "u32") or_return
    case .UInt64:
        io.write_string(wd, "u64") or_return
    case .UInt128:
        io.write_string(wd, "u128") or_return
    case .UIntX:
        io.write_string(wd, "uint") or_return
    case .Float32:
        io.write_string(wd, "f32") or_return
    case .Float64:
        io.write_string(wd, "f64") or_return
    case .Float128:
        io.write_string(wd, "[16]byte") or_return
    case .String:
        io.write_string(wd, "cstring") or_return
    case .Bool8:
        io.write_string(wd, "b8") or_return
    case .Bool16:
        io.write_string(wd, "b16") or_return
    case .Bool32:
        io.write_string(wd, "b32") or_return
    case .Bool64:
        io.write_string(wd, "b64") or_return
    case .Opaque:
        io.write_string(wd, "struct #packed {}") or_return
    }

    return .None
}

write_foreign_import :: proc(
    wd: io.Writer,
    file_path, package_name, lib_name: string,
    add_libs: [dynamic]AddLibs,
    ignore_arch: bool,
    force_lib_a_trim := false,
) -> io.Error {
    if len(add_libs) != 0 {
        when_written: bool
        for add_lib in add_libs {
            if expr, ok := plat_if_expr(add_lib.plat, ignore_arch).?; ok {
                if when_written {
                    io.write_string(wd, "else when ") or_return
                } else {
                    io.write_string(wd, "when ") or_return
                    when_written = true
                }
                io.write_string(wd, expr) or_return
            } else {
                if when_written {
                    io.write_string(wd, "else when true") or_return
                }
            }

            if when_written {
                io.write_string(wd, " {\n    ") or_return
            }

            io.write_string(wd, "foreign import ") or_return
            io.write_string(wd, package_name) or_return
            io.write_string(wd, "_runic ") or_return
            io.write_string(wd, "{ \"") or_return

            write_foreign_lib_name(
                wd,
                file_path,
                lib_name,
                force_lib_a_trim,
            ) or_return

            io.write_string(wd, "\", ") or_return

            for lib, lib_idx in add_lib.libs {
                io.write_rune(wd, '"') or_return
                write_foreign_lib_name(
                    wd,
                    file_path,
                    lib,
                    force_lib_a_trim,
                ) or_return
                io.write_rune(wd, '"') or_return
                if lib_idx != len(add_lib.libs) - 1 {
                    io.write_string(wd, ", ") or_return
                }
            }

            io.write_string(wd, " }") or_return
            if when_written {
                io.write_string(wd, "\n} ") or_return
            }
        }
    } else {
        io.write_string(wd, "foreign import ") or_return
        io.write_string(wd, package_name) or_return
        io.write_string(wd, "_runic ") or_return
        io.write_rune(wd, '"') or_return

        write_foreign_lib_name(wd, file_path, lib_name, force_lib_a_trim)

        io.write_rune(wd, '"') or_return
    }

    return .None
}

write_foreign_lib_name :: proc(
    wd: io.Writer,
    file_path, lib_name: string,
    force_lib_a_trim := false,
) -> io.Error {
    if filepath.is_abs(lib_name) {
        dir_name := filepath.dir(file_path)
        defer delete(dir_name)

        out_lib: string = ---
        rel_lib, rel_err := filepath.rel(dir_name, lib_name)
        defer if rel_err == .None do delete(rel_lib)

        if rel_err != .None || len(rel_lib) > len(lib_name) {
            out_lib = lib_name
        } else {
            out_lib = rel_lib
        }

        was_alloc: bool = ---
        out_lib, was_alloc = strings.replace_all(out_lib, "\\", "/")
        defer if was_alloc do delete(out_lib)

        io.write_string(wd, out_lib) or_return
    } else {
        io.write_string(wd, "system:") or_return

        out_lib := lib_name
        if strings.has_prefix(lib_name, "lib") &&
           (strings.has_suffix(lib_name, ".so") ||
                   strings.has_suffix(lib_name, ".dylib") ||
                   force_lib_a_trim) {
            out_lib = strings.trim_prefix(lib_name, "lib")
            out_lib = strings.trim_suffix(out_lib, ".so")
            out_lib = strings.trim_suffix(out_lib, ".a")
            out_lib = strings.trim_suffix(out_lib, ".dylib")
        }

        io.write_string(wd, out_lib) or_return
    }

    return .None
}

// A "pure" function pointer is a variable that is not a pointer to or an array of a function pointer
recursive_get_pure_func_ptr :: proc(
    _type: runic.Type,
    types: om.OrderedMap(string, runic.Type),
) -> (
    func_ptr: runic.FunctionPointer,
    ok: bool,
) {
    type := _type
    for {
        if type.pointer_info.count != 0 || len(type.array_info) != 0 {
            return
        }

        #partial switch s in type.spec {
        case runic.FunctionPointer:
            func_ptr = s
            ok = true
            return
        case string:
            t_ok: bool = ---
            type, t_ok = om.get(types, s)
            if !t_ok do return
        case:
            return
        }
    }

    return
}

ODIN_RESERVED :: []string {
    "int",
    "uint",
    "i8",
    "i16",
    "i32",
    "i64",
    "byte",
    "u8",
    "u16",
    "u32",
    "u64",
    "uintptr",
    "f16",
    "f32",
    "f64",
    "rune",
    "cstring",
    "rawptr",
    "bool",
    "b8",
    "b16",
    "b32",
    "b64",
    "i128",
    "u128",
    "i16le",
    "i32le",
    "i64le",
    "i128le",
    "u16le",
    "u32le",
    "u64le",
    "u128le",
    "i16be",
    "i32be",
    "i64be",
    "i128be",
    "u16be",
    "u32be",
    "u64be",
    "u128be",
    "f16le",
    "f32le",
    "f64le",
    "f16be",
    "f32be",
    "f64be",
    "complex32",
    "complex64",
    "complex128",
    "quaternion64",
    "quaternion128",
    "quaternion256",
    "string",
    "typeid",
    "any",
    "context",
    "struct",
    "enum",
    "union",
    "map",
    "dynamic",
    "bit_set",
    "bit_field",
    "matrix",
    "using",
    "or_else",
    "or_return",
    "package",
    "proc",
    "foreign",
    "nil",
    "for",
    "in",
    "if",
    "switch",
    "defer",
    "when",
    "else",
    "continue",
    "fallthrough",
    "return",
    "break",
    "import",
    "where",
}

plat_if_expr :: proc(
    plat: runic.Platform,
    ignore_arch: bool,
) -> Maybe(string) {
    if plat.os == .Any && plat.arch == .Any do return nil

    b: strings.Builder

    if plat.os != .Any {
        strings.write_string(&b, "(ODIN_OS == ")

        switch plat.os {
        case .Any:
            strings.write_string(&b, "ODIN_OS")
        case .Linux:
            strings.write_string(&b, ".Linux")
        case .Windows:
            strings.write_string(&b, ".Windows")
        case .Macos:
            strings.write_string(&b, ".Darwin")
        case .BSD:
            strings.write_string(
                &b,
                ".FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD",
            )
        }

        strings.write_rune(&b, ')')

        if !ignore_arch && plat.arch != .Any {
            strings.write_string(&b, " && ")
        }
    }

    if !ignore_arch && plat.arch != .Any {
        strings.write_string(&b, "(ODIN_ARCH == ")

        switch plat.arch {
        case .Any:
            strings.write_string(&b, "ODIN_ARCH")
        case .x86_64:
            strings.write_string(&b, ".amd64")
        case .arm64:
            strings.write_string(&b, ".arm64")
        case .x86:
            strings.write_string(&b, ".i386")
        case .arm32:
            strings.write_string(&b, ".arm32")
        }

        strings.write_rune(&b, ')')
    }

    return strings.to_string(b)
}

when_plats :: proc(
    wd: io.Writer,
    rune_platforms: []runic.Platform,
    plats: []runic.Platform,
    ignore_arch: bool,
) -> (
    write_when: bool,
    err: io.Error,
) {
    if len(plats) == 0 {
        return false, .None
    }

    unique_plats := runic.minimize_platforms(
        rune_platforms,
        plats,
        ignore_arch,
    )
    defer delete(unique_plats)

    b: strings.Builder

    for p in unique_plats {
        if if_expr, ok := plat_if_expr(p, ignore_arch).?; ok {
            if strings.builder_len(b) != 0 {
                strings.write_string(&b, " || ")
            }
            strings.write_string(&b, if_expr)
            delete(if_expr)
        }
    }

    if strings.builder_len(b) != 0 {
        io.write_string(wd, "when ") or_return

        io.write_string(wd, strings.to_string(b)) or_return
        strings.builder_destroy(&b)

        io.write_string(wd, " {\n\n") or_return

        return true, .None
    }

    return false, .None
}

@(private)
import_prefix :: proc(import_name: string) -> string {
    work_name := strings.trim_space(import_name)
    if idx := strings.index(work_name, " "); idx != -1 {
        return work_name[:idx]
    }

    path: string = ---
    if idx := strings.index(work_name, ":"); idx == -1 {
        path = work_name
    } else {
        path = work_name[idx + 1:]
    }

    path = strings.trim_right(path, "/")
    return slashpath.base(path)
}

@(private)
import_path :: proc(
    import_name: string,
) -> (
    import_name_overwrite, import_path_name: string,
) {
    start_idx: int = ---
    if start_idx = strings.index(import_name, " "); start_idx == -1 {
        start_idx = 0
    } else {
        import_name_overwrite = strings.trim_left_space(
            import_name[:start_idx],
        )
        start_idx += 1
    }

    import_path_name = strings.trim_space(import_name[start_idx:])
    return
}

@(private = "file")
add_libs_for_runestone :: proc(
    plats: []runic.Platform,
    rn_add_libs: runic.PlatformValue([]string),
) -> [dynamic]AddLibs {
    rs_add_libs := make([dynamic]AddLibs, len = 0, cap = len(rn_add_libs.d))

    for add_lib_plat, add_libs in rn_add_libs.d {
        for rs_plat in plats {
            if runic.platform_matches(add_lib_plat, rs_plat) {
                append(
                    &rs_add_libs,
                    AddLibs{plat = add_lib_plat, libs = add_libs},
                )
            }
        }
    }

    slice.sort_by(rs_add_libs[:], proc(i, j: AddLibs) -> bool {
            if i.plat.os == j.plat.os do return i.plat.arch > j.plat.arch
            return i.plat.os > j.plat.os
        })

    return rs_add_libs
}

@(private)
write_complete_foreign_import :: proc(
    wd: io.Writer,
    file_path: string,
    plats: []runic.Platform,
    lib: runic.Library,
    package_name, rn_static_switch: string,
    add_libs_static: [dynamic]AddLibs,
    add_libs_shared: [dynamic]AddLibs,
    ignore_arch: bool,
) -> io.Error {
    is_also_macos :=
        slice.count_proc(plats, proc(plat: runic.Platform) -> bool {
                return plat.os == .Macos || plat.os == .Any
            }) != 0

    if lib.shared != nil || lib.static != nil {
        if lib.shared != nil && lib.static != nil {
            static := lib.static.?
            shared := lib.shared.?

            io.write_string(wd, "when #config(") or_return
            if len(rn_static_switch) == 0 {
                upper_package_name := strings.to_upper(package_name)
                io.write_string(wd, upper_package_name) or_return
                io.write_string(wd, "_STATIC") or_return
                delete(upper_package_name)
            } else {
                io.write_string(wd, rn_static_switch) or_return
            }
            io.write_string(wd, ", false) {\n    ") or_return

            // NOTE: On macos you can not directly write "system:libfoo.a" (which can be done on linux) you need to change it to "system:foo"
            macos_system_static_fix :=
                is_also_macos &&
                !filepath.is_abs(static) &&
                strings.has_prefix(static, "lib") &&
                strings.has_suffix(static, ".a") // TODO: Also ask wether the add_libs are static system libs

            if macos_system_static_fix {
                io.write_string(
                    wd,
                    "when ODIN_OS == .Darwin {\n        ",
                ) or_return

                write_foreign_import(
                    wd,
                    file_path,
                    package_name,
                    static,
                    add_libs_static,
                    ignore_arch,
                    true,
                ) or_return

                io.write_string(wd, "\n    } else {\n        ") or_return
            }

            write_foreign_import(
                wd,
                file_path,
                package_name,
                static,
                add_libs_static,
                ignore_arch,
            ) or_return
            io.write_rune(wd, '\n') or_return

            if macos_system_static_fix {
                io.write_string(wd, "    }\n") or_return
            }

            io.write_string(wd, "} else {\n    ") or_return

            write_foreign_import(
                wd,
                file_path,
                package_name,
                shared,
                add_libs_shared,
                ignore_arch,
            ) or_return

            io.write_string(wd, "\n}\n\n") or_return
        } else {
            lib_name: string = ---
            is_shared: bool = ---

            if shared, ok := lib.shared.?; ok {
                is_shared = true
                lib_name = shared
            } else {
                is_shared = false
                lib_name = lib.static.?
            }

            macos_system_static_fix :=
                !is_shared &&
                is_also_macos &&
                !filepath.is_abs(lib_name) &&
                strings.has_prefix(lib_name, "lib") &&
                strings.has_suffix(lib_name, ".a")

            if macos_system_static_fix {
                io.write_string(wd, "when ODIN_OS == .Darwin {\n") or_return

                write_foreign_import(
                    wd,
                    file_path,
                    package_name,
                    lib_name,
                    add_libs_static,
                    ignore_arch,
                    true,
                ) or_return

                io.write_string(wd, "\n} else {\n") or_return
            }

            if macos_system_static_fix {
                io.write_string(wd, "    ") or_return
            }

            write_foreign_import(
                wd,
                file_path,
                package_name,
                lib_name,
                add_libs_shared if is_shared else add_libs_static,
                ignore_arch,
            ) or_return

            if macos_system_static_fix {
                io.write_string(wd, "\n}\n\n") or_return
            } else {
                io.write_string(wd, "\n\n") or_return
            }
        }
    }

    return .None
}
