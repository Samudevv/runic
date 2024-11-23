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
import "core:path/filepath"
import "core:path/slashpath"
import "core:slice"
import "core:strings"
import "root:errors"
import om "root:ordered_map"
import "root:runic"

generate_bindings :: proc(
    rc: runic.Runecross,
    rn: runic.To,
    wd: io.Writer,
    file_path: string,
) -> union {
        errors.Error,
        io.Error,
    } {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    if !rn.no_build_tag {
        for entry, cross_idx in rc.cross {
            if cross_idx == 0 {
                io.write_string(wd, "#+build ") or_return
            }

            plats := entry.plats

            for plat, plat_idx in plats {
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

                for os, os_idx in os_names {
                    io.write_string(wd, os) or_return
                    if !rn.ignore_arch {
                        io.write_rune(wd, ' ') or_return
                        switch plat.arch {
                        case .Any:
                        case .x86_64:
                            io.write_string(wd, "amd64") or_return
                        case .arm64:
                            io.write_string(wd, "arm64") or_return
                        case .x86:
                            io.write_string(wd, "i386") or_return
                        case .arm32:
                            io.write_string(wd, "arm32") or_return
                        }
                    }
                    if os_idx != len(os_names) - 1 {
                        io.write_string(wd, ", ") or_return
                    }
                }

                if plat_idx == len(plats) - 1 &&
                   cross_idx == len(rc.cross) - 1 {
                    io.write_rune(wd, '\n') or_return
                } else {
                    io.write_string(wd, ", ") or_return
                }
            }
        }
    }

    io.write_string(wd, "package ") or_return

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
        package_name = strings.concatenate({package_name, "_"}, arena_alloc)
    }


    io.write_string(wd, package_name) or_return
    io.write_string(wd, "\n\n") or_return

    // Write all imports for the extern types
    imports := make(
        [dynamic][2]string,
        allocator = arena_alloc,
        len = 0,
        cap = len(rn.extern.sources),
    )
    for _, source in rn.extern.sources {
        import_name_overwrite, import_path_name := import_path(source)
        if !slice.contains(
            imports[:],
            [2]string{import_name_overwrite, import_path_name},
        ) {
            append(
                &imports,
                [2]string{import_name_overwrite, import_path_name},
            )
        }
    }

    slice.sort_by(imports[:], proc(i, j: [2]string) -> bool {
        name_i := i[0] if len(i[0]) != 0 else i[1]
        name_j := j[0] if len(j[0]) != 0 else j[1]

        return name_i < name_j
    })

    for importy in imports {
        import_name_overwrite, import_path_name := importy[0], importy[1]
        io.write_string(wd, "import ") or_return
        if len(import_name_overwrite) != 0 {
            io.write_string(wd, import_name_overwrite) or_return
            io.write_rune(wd, ' ') or_return
        }
        io.write_rune(wd, '"') or_return
        io.write_string(wd, import_path_name) or_return
        io.write_string(wd, "\"\n") or_return
    }
    if len(imports) != 0 do io.write_rune(wd, '\n') or_return

    write_when := false

    for entry, idx in rc.cross {
        plats := entry.plats
        if !runic.runecross_is_simple(rc) {
            if rn.use_when_else && idx == len(rc.cross) - 1 && write_when {
                io.write_string(wd, "{\n\n") or_return
            } else {
                write_when = when_plats(wd, plats, rn.ignore_arch) or_return
            }
        }

        errors.wrap(
            generate_bindings_from_runestone(
                entry,
                rn,
                wd,
                file_path,
                package_name,
            ),
        ) or_return

        if !runic.runecross_is_simple(rc) && write_when {
            io.write_rune(wd, '}') or_return
            if rn.use_when_else && idx != len(rc.cross) - 1 {
                io.write_string(wd, " else ") or_return
            } else {
                io.write_string(wd, "\n\n") or_return
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
) -> union {
        errors.Error,
        io.Error,
    } {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

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
                io.write_rune(wd, '`') or_return
                io.write_string(wd, value) or_return
                io.write_rune(wd, '`') or_return
            }
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

    if rs.lib.shared != nil || rs.lib.static != nil {
        if rs.lib.shared != nil && rs.lib.static != nil {
            static := rs.lib.static.?
            shared := rs.lib.shared.?

            static_switch := rn.static_switch
            if len(static_switch) == 0 {
                static_switch = strings.concatenate(
                    {strings.to_upper(package_name, arena_alloc), "_STATIC"},
                    arena_alloc,
                )
            }

            io.write_string(wd, "when #config(") or_return
            io.write_string(wd, static_switch) or_return
            io.write_string(wd, ", false) {\n    ") or_return


            rel_static: string
            defer delete(rel_static)
            static_is_abs := filepath.is_abs(static)
            macos_count := 0

            if static_is_abs {
                dir_name := filepath.dir(file_path)
                defer delete(dir_name)
                err: filepath.Relative_Error = ---
                rel_static, err = filepath.rel(dir_name, static)
                if err == .None && len(rel_static) < len(static) {
                    static = rel_static
                }
            } else {
                macos_count = slice.count_proc(
                    rs.plats,
                    proc(plat: runic.Platform) -> bool {
                        return plat.os == .Macos
                    },
                )
                if macos_count != 0 {
                    if strings.has_prefix(static, "lib") &&
                       strings.has_suffix(static, ".a") {
                        macos_static := strings.trim_prefix(static, "lib")
                        macos_static = strings.trim_suffix(macos_static, ".a")

                        io.write_string(
                            wd,
                            "when ODIN_OS == .Darwin {\n",
                        ) or_return
                        io.write_string(wd, "    foreign import ") or_return
                        io.write_string(wd, package_name) or_return
                        io.write_string(wd, "_runic \"system:") or_return
                        io.write_string(wd, macos_static) or_return
                        io.write_string(wd, "\"\n} else {\n") or_return
                    }
                }
            }

            if macos_count != 0 {
                io.write_string(wd, "    ") or_return
            }
            io.write_string(wd, "foreign import ") or_return
            io.write_string(wd, package_name) or_return
            io.write_string(wd, "_runic \"") or_return

            if !static_is_abs {
                io.write_string(wd, "system:") or_return
            }

            static_was_alloc: bool = ---
            static, static_was_alloc = strings.replace_all(static, "\\", "/")
            defer if static_was_alloc do delete(static)
            io.write_string(wd, static) or_return
            io.write_string(wd, "\"\n") or_return

            if macos_count != 0 {
                io.write_string(wd, "}\n") or_return
            }

            io.write_string(wd, "} else {\n    foreign import ") or_return
            io.write_string(wd, package_name) or_return
            io.write_string(wd, "_runic \"") or_return

            rel_shared: string
            defer delete(rel_shared)
            if filepath.is_abs(shared) {
                dir_name := filepath.dir(file_path)
                defer delete(dir_name)
                err: filepath.Relative_Error = ---
                rel_shared, err = filepath.rel(dir_name, shared)
                if err == .None && len(rel_shared) < len(shared) {
                    shared = rel_shared
                }
            } else {
                if strings.has_prefix(shared, "lib") &&
                   (strings.has_suffix(shared, ".so") ||
                           strings.has_suffix(shared, ".dylib")) {
                    shared = strings.trim_prefix(shared, "lib")
                    shared = strings.trim_suffix(shared, ".so")
                    shared = strings.trim_suffix(shared, ".dylib")
                }

                io.write_string(wd, "system:") or_return
            }

            shared_was_alloc: bool = ---
            shared, shared_was_alloc = strings.replace_all(shared, "\\", "/")
            defer if shared_was_alloc do delete(shared)
            io.write_string(wd, shared) or_return

            io.write_string(wd, "\"\n}\n\n") or_return
        } else {
            lib_name: string = ---
            is_shared: bool = ---

            if shared, ok := rs.lib.shared.?; ok {
                is_shared = true
                lib_name = shared
            } else {
                is_shared = false
                lib_name = rs.lib.static.?
            }

            rel_lib: string
            defer delete(rel_lib)
            macos_count := 0
            lib_is_abs := filepath.is_abs(lib_name)

            if lib_is_abs {
                dir_name := filepath.dir(file_path)
                defer delete(dir_name)
                err: filepath.Relative_Error = ---
                rel_lib, err = filepath.rel(dir_name, lib_name)
                if err == .None && len(rel_lib) < len(lib_name) {
                    lib_name = rel_lib
                }
            } else {
                if is_shared {
                    if strings.has_prefix(lib_name, "lib") &&
                       (strings.has_suffix(lib_name, ".so") ||
                               strings.has_suffix(lib_name, ".dylib")) {
                        lib_name = strings.trim_prefix(lib_name, "lib")
                        lib_name = strings.trim_suffix(lib_name, ".so")
                        lib_name = strings.trim_suffix(lib_name, ".dylib")
                    }
                } else {
                    macos_count = slice.count_proc(
                        rs.plats,
                        proc(plat: runic.Platform) -> bool {
                            return plat.os == .Macos
                        },
                    )
                    if macos_count != 0 {
                        if strings.has_prefix(lib_name, "lib") &&
                           strings.has_suffix(lib_name, ".a") {
                            macos_lib := strings.trim_prefix(lib_name, "lib")
                            macos_lib = strings.trim_suffix(macos_lib, ".a")

                            io.write_string(
                                wd,
                                "when ODIN_OS == .Darwin {\n",
                            ) or_return
                            io.write_string(
                                wd,
                                "    foreign import ",
                            ) or_return
                            io.write_string(wd, package_name) or_return
                            io.write_string(wd, "_runic \"system:") or_return
                            io.write_string(wd, macos_lib) or_return
                            io.write_string(wd, "\"\n} else {\n") or_return
                        }
                    }
                }
            }

            if macos_count != 0 {
                io.write_string(wd, "    ") or_return
            }
            io.write_string(wd, "foreign import ") or_return
            io.write_string(wd, package_name) or_return
            io.write_string(wd, "_runic \"") or_return

            if !lib_is_abs {
                io.write_string(wd, "system:") or_return
            }

            was_alloc: bool = ---
            lib_name, was_alloc = strings.replace_all(lib_name, "\\", "\\\\")
            io.write_string(wd, lib_name) or_return
            if was_alloc do delete(lib_name)

            io.write_string(wd, "\"\n") or_return
            if macos_count != 0 {
                io.write_string(wd, "}\n\n") or_return
            } else {
                io.write_rune(wd, '\n') or_return
            }
        }
    }

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
                           b_ok && b == .Void {
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

    if b, ok := fc.return_type.spec.(runic.Builtin); ok && b == .Void {
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
        if pointer_count >= 1 &&
           len(var_name) > 1 &&
           strings.has_suffix(var_name, "s") {
            is_multi_pointer = true
            pointer_count -= 1
        }
    }

    #reverse for a in ty.array_info {
        pointer, pointer_err := strings.repeat("^", int(ty.pointer_info.count))
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

    if is_multi_pointer {
        io.write_string(wd, "[^]") or_return
    }

    switch spec in ty.spec {
    case runic.Builtin:
        write_builtin_type(wd, spec) or_return
    case runic.Struct:
        io.write_string(wd, "struct {\n") or_return
        for m in spec.members {
            io.write_string(wd, "    ") or_return

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

            io.write_string(wd, m.name) or_return
            io.write_string(wd, ": ") or_return
            io.write_string(wd, strings.to_string(type_bd)) or_return
            io.write_string(wd, ",\n") or_return
        }
        io.write_rune(wd, '}') or_return
    case runic.Enum:
        io.write_string(wd, "enum ") or_return
        write_builtin_type(wd, spec.type) or_return
        io.write_string(wd, " {") or_return
        for e in spec.entries {
            // TODO: add new lines between enum values
            io.write_string(wd, e.name) or_return
            io.write_string(wd, " = ") or_return
            fmt.wprintf(wd, "{}, ", e.value)
        }
        io.write_rune(wd, '}') or_return
    case runic.Union:
        io.write_string(wd, "struct #raw_union {") or_return
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

            io.write_string(wd, m.name) or_return
            io.write_string(wd, ": ") or_return
            io.write_string(wd, strings.to_string(type_bd)) or_return
            io.write_string(wd, ", ") or_return
        }
        io.write_rune(wd, '}') or_return
    case string:
        io.write_string(wd, spec) or_return
    case runic.Unknown:
        io.write_string(wd, "rawptr") or_return
    case runic.FunctionPointer:
        io.write_string(wd, "#type ") or_return
        write_procedure(wd, spec^, rn, externs) or_return
    case runic.ExternType:
        if extern, ok := om.get(externs, string(spec)); ok {
            import_name, import_ok := runic.map_glob(
                rn.extern.sources,
                extern.source,
            )

            if !import_ok {
                io.write_string(wd, string(spec)) or_return
            } else {
                prefix := import_prefix(import_name)
                type_name :=
                    rn.extern.remaps[string(spec)] or_else string(spec)

                io.write_string(wd, prefix) or_return
                io.write_rune(wd, '.') or_return
                io.write_string(wd, type_name) or_return
            }
        } else {
            err = errors.Error(
                errors.message(
                    "extern type \"{}\" has not been defined in the extern section",
                    spec,
                ),
            )
            return
        }
    }

    return
}

write_builtin_type :: proc(wd: io.Writer, ty: runic.Builtin) -> io.Error {
    switch ty {
    case .Untyped:
        io.write_string(wd, "ThisTypeIsUntyped") or_return
    case .Void:
        io.write_string(wd, "ThisTypeIsVoid") or_return
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
    plats: []runic.Platform,
    ignore_arch: bool,
) -> (
    write_when: bool,
    err: io.Error,
) {
    if len(plats) == 0 {
        return false, .None
    }

    b: strings.Builder

    for p in plats {
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

