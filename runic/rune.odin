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
import "core:bytes"
import "core:fmt"
import "core:io"
import "core:path/filepath"
import "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "root:errors"
import om "root:ordered_map"
import "shared:yaml"

parse_rune :: proc(
    rd: io.Reader,
    file_path: string,
) -> (
    rn: Rune,
    err: errors.Error,
) {
    rn_arena_alloc := runtime.arena_allocator(&rn.arena)

    buf: bytes.Buffer
    bytes.buffer_init_allocator(&buf, 0, 0)

    _, io_err := io.copy(bytes.buffer_to_stream(&buf), rd)
    errors.wrap(io_err) or_return

    data := bytes.buffer_to_bytes(&buf)

    yaml_data, yaml_err := yaml.decode(data, rn_arena_alloc)
    bytes.buffer_destroy(&buf)
    if yaml_err != nil do return rn, errors.message("Yaml Decode: {}", yaml.error_string(yaml_err, file_path, errors.error_allocator))

    #partial switch y in yaml_data {
    case yaml.Mapping:
        errors.assert("version" in y, "\"version\" is missing") or_return
        errors.assert("from" in y, "\"from\" is missing") or_return
        errors.assert("to" in y, "\"to\" is missing") or_return

        if version, ok := y["version"].(i64); ok {
            rn.version = uint(version)
        } else {
            err = errors.message("\"version\" has invalid type")
            return
        }

        if platforms, ok := y["platforms"]; ok {
            plats: [dynamic]Platform = ---

            #partial switch p in platforms {
            case string:
                plats = make(
                    [dynamic]Platform,
                    allocator = rn_arena_alloc,
                    len = 0,
                    cap = 1,
                )

                name_arch := strings.split(p, " ")
                defer delete(name_arch)

                if len(name_arch) != 2 {
                    err = errors.message("\"platforms\" is invalid: \"{}\"", p)
                    return
                }

                plat, plat_ok := platform_from_strings(
                    name_arch[0],
                    name_arch[1],
                )
                if !plat_ok {
                    err = errors.message(
                        "\"platforms\" is invalid os=\"{}\" arch=\"{}\"",
                        name_arch[0],
                        name_arch[1],
                    )
                    return
                }

                if plat.os == .Any {
                    for os in MIN_OS ..= MAX_OS {
                        if plat.arch == .Any {
                            for arch in MIN_ARCH ..= MAX_ARCH {
                                append(&plats, Platform{os, arch})
                            }
                        } else {
                            append(&plats, Platform{os, plat.arch})
                        }
                    }
                } else if plat.arch == .Any {
                    for arch in MIN_ARCH ..= MAX_ARCH {
                        append(&plats, Platform{plat.os, arch})
                    }
                } else {
                    append(&plats, plat)
                }
            case yaml.Sequence:
                plats = make(
                    [dynamic]Platform,
                    allocator = rn_arena_alloc,
                    len = 0,
                    cap = len(p),
                )

                for value, idx in p {
                    #partial switch v in value {
                    case string:
                        name_arch := strings.split(v, " ")
                        defer delete(name_arch)

                        if len(name_arch) != 2 {
                            err = errors.message(
                                "\"platforms\"[{}] is invalid: \"{}\"",
                                idx,
                                v,
                            )
                            return
                        }

                        plat, plat_ok := platform_from_strings(
                            name_arch[0],
                            name_arch[1],
                        )
                        if !plat_ok {
                            err = errors.message(
                                "\"platforms\"[{}] is invalid os=\"{}\" arch=\"{}\"",
                                idx,
                                name_arch[0],
                                name_arch[1],
                            )
                            return
                        }

                        if plat.os == .Any {
                            for os in MIN_OS ..= MAX_OS {
                                if plat.arch == .Any {
                                    for arch in MIN_ARCH ..= MAX_ARCH {
                                        append(&plats, Platform{os, arch})
                                    }
                                } else {
                                    append(&plats, Platform{os, plat.arch})
                                }
                            }
                        } else if plat.arch == .Any {
                            for arch in MIN_ARCH ..= MAX_ARCH {
                                append(&plats, Platform{plat.os, arch})
                            }
                        } else {
                            append(&plats, plat)
                        }
                    case:
                        err = errors.message(
                            "\"platforms\"[{}] has invalid type",
                            idx,
                        )
                        return
                    }
                }
            case:
                err = errors.message("\"platforms\" has invalid type")
                return
            }

            rn.platforms = plats[:]
        }

        if wrapper_value, wrapper_ok := y["wrapper"]; wrapper_ok {
            wrapper := Wrapper {
                multi_platform     = true,
                add_header_to_from = true,
            }
            {
                using wrapper
                context.allocator = rn_arena_alloc

                from_compiler_flags = make_platform_value(bool)
                defines = make_platform_value(map[string]string)
                include_dirs = make_platform_value([]string)
                flags = make_platform_value([]cstring)
                load_all_includes = make_platform_value(bool)
                extern = make_platform_value([]string)
                in_headers = make_platform_value([]string)

                from_compiler_flags.d[{.Any, .Any}] = true

            }

            #partial switch wrapper_map in wrapper_value {
            case yaml.Mapping:
                for map_name, map_value in wrapper_map {
                    name_plat := strings.split(map_name, ".")
                    defer delete(name_plat)

                    name: string
                    os_str: Maybe(string)
                    arch_str: Maybe(string)

                    #no_bounds_check switch len(name_plat) {
                    case 1:
                        name = name_plat[0]
                    case 2:
                        name = name_plat[0]
                        os_str = name_plat[1]
                    case 3:
                        name = name_plat[0]
                        os_str = name_plat[1]
                        arch_str = name_plat[2]
                    case:
                        err = errors.message(
                            "\"wrapper.{}\" has invalid key",
                            map_name,
                        )
                        return
                    }

                    plat, plat_ok := platform_from_strings(os_str, arch_str)
                    if !plat_ok {
                        err = errors.message(
                            "\"wrapper.{}\" has invalid platform",
                            map_name,
                        )
                        return
                    }

                    switch name {
                    case "language":
                        #partial switch v in map_value {
                        case string:
                            wrapper.language = v
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "from_compiler_flags":
                        #partial switch v in map_value {
                        case bool:
                            wrapper.from_compiler_flags.d[plat] = v
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "defines":
                        #partial switch v in map_value {
                        case yaml.Mapping:
                            arr := make(
                                map[string]string,
                                len(v),
                                allocator = rn_arena_alloc,
                            )

                            for key, value in v {
                                #partial switch vv in value {
                                case string:
                                    arr[key] = vv
                                case:
                                    err = errors.message(
                                        "\"wrapper.{}.{}\" has invalid type",
                                        map_name,
                                        key,
                                    )
                                    return
                                }
                            }

                            wrapper.defines.d[plat] = arr
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "includedirs":
                        #partial switch v in map_value {
                        case string:
                            arr := make(
                                [dynamic]string,
                                len = 1,
                                cap = 1,
                                allocator = rn_arena_alloc,
                            )
                            arr[0] = relative_to_file(
                                file_path,
                                v,
                                rn_arena_alloc,
                            )
                            wrapper.include_dirs.d[plat] = arr[:]
                        case yaml.Sequence:
                            arr := make(
                                [dynamic]string,
                                len = 0,
                                cap = len(v),
                                allocator = rn_arena_alloc,
                            )
                            for value, idx in v {
                                #partial switch vv in value {
                                case string:
                                    append(
                                        &arr,
                                        relative_to_file(
                                            file_path,
                                            vv,
                                            rn_arena_alloc,
                                        ),
                                    )
                                case:
                                    err = errors.message(
                                        "\"wrapper.{}[{}]\" has invalid type",
                                        map_name,
                                        idx,
                                    )
                                    return
                                }
                            }
                            wrapper.include_dirs.d[plat] = arr[:]
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "flags":
                        #partial switch v in map_value {
                        case string:
                            arr := make(
                                [dynamic]cstring,
                                len = 1,
                                cap = 1,
                                allocator = rn_arena_alloc,
                            )
                            arr[0] = strings.clone_to_cstring(
                                v,
                                rn_arena_alloc,
                            )
                            wrapper.flags.d[plat] = arr[:]
                        case yaml.Sequence:
                            arr := make(
                                [dynamic]cstring,
                                len = 0,
                                cap = len(v),
                                allocator = rn_arena_alloc,
                            )
                            for value, idx in v {
                                #partial switch vv in value {
                                case string:
                                    append(
                                        &arr,
                                        strings.clone_to_cstring(
                                            vv,
                                            rn_arena_alloc,
                                        ),
                                    )
                                case:
                                    err = errors.message(
                                        "\"wrapper.{}[{}]\" has invalid type",
                                        map_name,
                                        idx,
                                    )
                                    return
                                }
                            }
                            wrapper.flags.d[plat] = arr[:]
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "load_all_includes":
                        #partial switch v in map_value {
                        case bool:
                            wrapper.load_all_includes.d[plat] = v
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "extern":
                        #partial switch v in map_value {
                        case string:
                            arr := make(
                                [dynamic]string,
                                len = 1,
                                cap = 1,
                                allocator = rn_arena_alloc,
                            )
                            arr[0] = relative_to_file(
                                file_path,
                                v,
                                rn_arena_alloc,
                            )
                            wrapper.extern.d[plat] = arr[:]
                        case yaml.Sequence:
                            arr := make(
                                [dynamic]string,
                                len = 0,
                                cap = len(v),
                                allocator = rn_arena_alloc,
                            )
                            for value, idx in v {
                                #partial switch vv in value {
                                case string:
                                    append(
                                        &arr,
                                        relative_to_file(
                                            file_path,
                                            vv,
                                            rn_arena_alloc,
                                        ),
                                    )
                                case:
                                    err = errors.message(
                                        "\"wrapper.{}[{}]\" has invalid type",
                                        map_name,
                                        idx,
                                    )
                                    return
                                }
                            }
                            wrapper.extern.d[plat] = arr[:]
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "in_headers":
                        #partial switch v in map_value {
                        case string:
                            arr := make(
                                [dynamic]string,
                                len = 1,
                                cap = 1,
                                allocator = rn_arena_alloc,
                            )
                            arr[0] = relative_to_file(
                                file_path,
                                v,
                                rn_arena_alloc,
                            )
                            wrapper.in_headers.d[plat] = arr[:]
                        case yaml.Sequence:
                            arr := make(
                                [dynamic]string,
                                len = 0,
                                cap = len(v),
                                allocator = rn_arena_alloc,
                            )
                            for value, idx in v {
                                #partial switch vv in value {
                                case string:
                                    append(
                                        &arr,
                                        relative_to_file(
                                            file_path,
                                            vv,
                                            rn_arena_alloc,
                                        ),
                                    )
                                case:
                                    err = errors.message(
                                        "\"wrapper.{}[{}]\" has invalid type",
                                        map_name,
                                        idx,
                                    )
                                    return
                                }
                            }
                            wrapper.in_headers.d[plat] = arr[:]
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "out_header":
                        #partial switch v in map_value {
                        case string:
                            wrapper.out_header = relative_to_file(
                                file_path,
                                v,
                                rn_arena_alloc,
                            )
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "out_source":
                        #partial switch v in map_value {
                        case string:
                            wrapper.out_source = relative_to_file(
                                file_path,
                                v,
                                rn_arena_alloc,
                            )
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "add_header_to_from":
                        #partial switch v in map_value {
                        case bool:
                            wrapper.add_header_to_from = v
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    case "multi_platform":
                        #partial switch v in map_value {
                        case bool:
                            wrapper.multi_platform = v
                        case:
                            err = errors.message(
                                "\"wrapper.{}\" has invalid type",
                                map_name,
                            )

                            return
                        }
                    }
                }
            }

            rn.wrapper = wrapper
        }

        #partial switch from in y["from"] {
        case yaml.Mapping:
            f: From

            {
                context.allocator = rn_arena_alloc

                f.static = make_platform_value(string)
                f.shared = make_platform_value(string)
                f.ignore = make_platform_value(IgnoreSet)
                f.overwrite = make_platform_value(OverwriteSet)
                f.headers = make_platform_value([]string)
                f.includedirs = make_platform_value([]string)
                f.defines = make_platform_value(map[string]string)
                f.enable_host_includes = make_platform_value(bool)
                f.disable_system_include_gen = make_platform_value(bool)
                f.disable_stdint_macros = make_platform_value(bool)
                f.flags = make_platform_value([]cstring)
                f.load_all_includes = make_platform_value(bool)
                f.forward_decl_type = make_platform_value(Type)
                f.packages = make_platform_value([]string)
                f.remaps = make(map[string]string)
                f.aliases = make(map[string][]string)

                f.forward_decl_type.d[{.Any, .Any}] = {
                    spec = Builtin.Opaque,
                }
            }

            errors.assert(
                "language" in from,
                "\"from.language\" is missing",
            ) or_return

            for key, value in from {
                splits, alloc_err := strings.split(key, ".")
                errors.wrap(alloc_err) or_return

                name: string = ---
                os, arch: Maybe(string)

                switch len(splits) {
                case 0:
                    err = errors.message("invalid key in \"from\"")
                    return
                case 1:
                    name = splits[0]
                case 2:
                    name = splits[0]
                    os = splits[1]
                case 3:
                    name = splits[0]
                    os = splits[1]
                    arch = splits[2]
                case:
                    err = errors.message("invalid key in \"from\": {}", key)
                    return
                }

                delete(splits)

                plat, plat_ok := platform_from_strings(os, arch)
                if !plat_ok {
                    err = errors.message(
                        "invalid platform for \"from.{}\" os=\"{}\" arch=\"{}\"",
                        name,
                        os,
                        arch,
                    )
                    return
                }

                switch name {
                case "language":
                    v, ok := value.(string)
                    errors.wrap(
                        ok,
                        "\"from.language\" has invalid type",
                    ) or_return
                    f.language = v
                case "static":
                    v, ok := value.(string)
                    errors.wrap(
                        ok,
                        "\"from.static\" has invalid type",
                    ) or_return

                    f.static.d[plat] = relative_to_file(
                        file_path,
                        v,
                        rn_arena_alloc,
                        true,
                    )
                case "shared":
                    v, ok := value.(string)
                    errors.wrap(
                        ok,
                        "\"from.shared\" has invalid type",
                    ) or_return

                    f.shared.d[plat] = relative_to_file(
                        file_path,
                        v,
                        rn_arena_alloc,
                        true,
                    )
                case "ignore":
                    i_set: IgnoreSet
                    if value == nil {
                        f.ignore.d[plat] = i_set
                        break
                    }

                    #partial switch v in value {
                    case string:
                        arr := make(
                            [dynamic]string,
                            allocator = rn_arena_alloc,
                            len = 1,
                            cap = 1,
                        )
                        arr[0] = v

                        i_set.constants = arr[:]
                        i_set.functions = arr[:]
                        i_set.variables = arr[:]
                        i_set.types = arr[:]
                    case yaml.Sequence:
                        arr := make(
                            [dynamic]string,
                            allocator = rn_arena_alloc,
                            len = 0,
                            cap = len(v),
                        )

                        for seq_v, idx in v {
                            #partial switch v_seq in seq_v {
                            case string:
                                append(&arr, v_seq)
                            case:
                                err = errors.message(
                                    "\"from.{}\"[{}] has invalid type %T",
                                    key,
                                    idx,
                                    v_seq,
                                )
                                return
                            }
                        }

                        i_set.constants = arr[:]
                        i_set.functions = arr[:]
                        i_set.variables = arr[:]
                        i_set.types = arr[:]
                    case yaml.Mapping:
                        constants_arr: [dynamic]string
                        functions_arr: [dynamic]string
                        variables_arr: [dynamic]string
                        types_arr: [dynamic]string

                        macros_v, macros_ok := v["macros"]
                        constants_v, constants_ok := v["constants"]

                        if macros_ok {
                            fmt.eprintln(
                                "warning: \"from.ignore.macros\" is deprecated use \"from.ignore.constants\" instead",
                            )

                            if !constants_ok {
                                constants_v = macros_v
                                constants_ok = macros_ok
                            }
                        }

                        if constants_ok {
                            #partial switch c in constants_v {
                            case string:
                                constants_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 1,
                                    cap = 1,
                                )
                                constants_arr[0] = c
                            case yaml.Sequence:
                                constants_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 0,
                                    cap = len(c),
                                )
                                for seq_c, idx in c {
                                    #partial switch c_seq in seq_c {
                                    case string:
                                        append(&constants_arr, c_seq)
                                    case:
                                        err = errors.message(
                                            "\"from.{}.constants\"[{}] has invalid type %T",
                                            key,
                                            idx,
                                            c_seq,
                                        )
                                        return
                                    }
                                }
                            }
                        }

                        if functions, ok := v["functions"]; ok {
                            #partial switch f in functions {
                            case string:
                                functions_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 1,
                                    cap = 1,
                                )
                                functions_arr[0] = f
                            case yaml.Sequence:
                                functions_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 0,
                                    cap = len(f),
                                )
                                for seq_f, idx in f {
                                    #partial switch f_seq in seq_f {
                                    case string:
                                        append(&functions_arr, f_seq)
                                    case:
                                        err = errors.message(
                                            "\"from.{}.functions\"[{}] has invalid type %T",
                                            key,
                                            idx,
                                            f_seq,
                                        )
                                        return
                                    }
                                }
                            }
                        }

                        if variables, ok := v["variables"]; ok {
                            #partial switch var in variables {
                            case string:
                                variables_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 1,
                                    cap = 1,
                                )
                                variables_arr[0] = var
                            case yaml.Sequence:
                                variables_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 0,
                                    cap = len(var),
                                )
                                for seq_var, idx in var {
                                    #partial switch var_seq in seq_var {
                                    case string:
                                        append(&variables_arr, var_seq)
                                    case:
                                        err = errors.message(
                                            "\"from.{}.variables\"[{}] has invalid type %T",
                                            key,
                                            idx,
                                            var_seq,
                                        )
                                        return
                                    }
                                }
                            }
                        }

                        if types, ok := v["types"]; ok {
                            #partial switch t in types {
                            case string:
                                types_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 1,
                                    cap = 1,
                                )
                                types_arr[0] = t
                            case yaml.Sequence:
                                types_arr = make(
                                    [dynamic]string,
                                    allocator = rn_arena_alloc,
                                    len = 0,
                                    cap = len(t),
                                )
                                for seq_t, idx in t {
                                    #partial switch t_seq in seq_t {
                                    case string:
                                        append(&types_arr, t_seq)
                                    case:
                                        err = errors.message(
                                            "\"from.{}.types\"[{}] has invalid type %T",
                                            key,
                                            idx,
                                            t_seq,
                                        )
                                        return
                                    }
                                }
                            }
                        }

                        i_set.constants = constants_arr[:]
                        i_set.functions = functions_arr[:]
                        i_set.variables = variables_arr[:]
                        i_set.types = types_arr[:]
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                    f.ignore.d[plat] = i_set
                case "overwrite":
                    o_set: OverwriteSet

                    o_set.constants = make(
                        [dynamic]Overwrite,
                        allocator = rn_arena_alloc,
                    )
                    o_set.functions = make(
                        [dynamic]Overwrite,
                        allocator = rn_arena_alloc,
                    )
                    o_set.variables = make(
                        [dynamic]Overwrite,
                        allocator = rn_arena_alloc,
                    )
                    o_set.types = make(
                        [dynamic]Overwrite,
                        allocator = rn_arena_alloc,
                    )

                    if value == nil {
                        f.overwrite.d[plat] = o_set
                        break
                    }

                    #partial switch v in value {
                    case yaml.Mapping:
                        if "constants" in v {
                            #partial switch con in v["constants"] {
                            case yaml.Mapping:
                                for con_key, con_value in con {
                                    ow: Overwrite

                                    overwrite_value: string = ---
                                    #partial switch con_v in con_value {
                                    case string:
                                        overwrite_value = con_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.constants.{}\" has invalid type %T",
                                            key,
                                            con_key,
                                            con_v,
                                        )
                                        return
                                    }

                                    split := strings.split(con_key, ".")
                                    defer delete(split)

                                    ow.name = split[0]

                                    switch len(split) {
                                    case 1:
                                        ow.instruction = OverwriteWhole(
                                            overwrite_value,
                                        )
                                    case 2:
                                        switch split[1] {
                                        case "name":
                                            ow.instruction = OverwriteName {
                                                overwrite_value,
                                            }
                                        case:
                                            err = errors.message(
                                                "\"from.{}.constants.{}\" is invalid",
                                                key,
                                                con_key,
                                            )
                                            return
                                        }
                                    case:
                                        err = errors.message(
                                            "\"from.{}.constants.{}\" is invalid: too much \".\"",
                                            key,
                                            con_key,
                                        )
                                    }

                                    append(&o_set.constants, ow)
                                }
                            case:
                                err = errors.message(
                                    "\"from.{}.constants\" has invalid type %T",
                                    key,
                                    con,
                                )
                                return
                            }
                        }

                        if "variables" in v {
                            #partial switch var in v["variables"] {
                            case yaml.Mapping:
                                for var_key, var_value in var {
                                    ow: Overwrite
                                    overwrite_value: string = ---

                                    #partial switch var_v in var_value {
                                    case string:
                                        overwrite_value = var_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.variables.{}\" has invalid type %T",
                                            key,
                                            var_key,
                                            var_v,
                                        )
                                        return
                                    }

                                    split := strings.split(var_key, ".")
                                    defer delete(split)

                                    ow.name = split[0]

                                    switch len(split) {
                                    case 1:
                                        ow.instruction = OverwriteWhole(
                                            overwrite_value,
                                        )
                                    case 2:
                                        switch split[1] {
                                        case "name":
                                            ow.instruction = OverwriteName {
                                                overwrite_value,
                                            }
                                        case:
                                            err = errors.message(
                                                "\"from.{}.variables.{}\" is invalid",
                                                key,
                                                var_key,
                                            )
                                            return
                                        }
                                    case:
                                        err = errors.message(
                                            "\"from.{}.variables.{}\" is invalid",
                                            key,
                                            var_key,
                                        )
                                        return
                                    }

                                    append(&o_set.variables, ow)
                                }
                            case:
                                err = errors.message(
                                    "\"from.{}.variables\" has invalid type %T",
                                    key,
                                    var,
                                )
                                return
                            }
                        }

                        if "types" in v {
                            #partial switch typ in v["types"] {
                            case yaml.Mapping:
                                for typ_key, typ_value in typ {
                                    overwrite_value: string = ---
                                    #partial switch typ_v in typ_value {
                                    case string:
                                        overwrite_value = typ_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.types.{}\" has invalid type %T",
                                            key,
                                            typ_key,
                                            typ_v,
                                        )
                                        return
                                    }

                                    split := strings.split(typ_key, ".")
                                    defer delete(split)

                                    ow: Overwrite = ---
                                    ow.name = split[0]

                                    switch len(split) {
                                    case 1:
                                        ow.instruction = OverwriteWhole(
                                            overwrite_value,
                                        )
                                    case 2:
                                        switch split[1] {
                                        case "name":
                                            ow.instruction = OverwriteName {
                                                overwrite_value,
                                            }
                                        case "return":
                                            ow.instruction =
                                                OverwriteReturnType(
                                                    overwrite_value,
                                                )
                                        case:
                                            err = errors.message(
                                                "\"from.{}.types.{}\" is invalid",
                                                key,
                                                typ_key,
                                            )
                                            return
                                        }
                                    case 4:
                                        switch split[1] {
                                        case "member":
                                            idx, idx_ok := strconv.parse_i64(
                                                split[2],
                                            )
                                            if !idx_ok {
                                                err = errors.message(
                                                    "\"from.{}.types.{}\" is invalid \"{}\" is not an integer",
                                                    key,
                                                    typ_key,
                                                    split[2],
                                                )
                                                return
                                            }

                                            switch split[3] {
                                            case "type":
                                                ow.instruction =
                                                    OverwriteMemberType {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case "name":
                                                ow.instruction =
                                                    OverwriteMemberName {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case:
                                                err = errors.message(
                                                    "\"from.{}.types.{}\" is invalid \"{}\"",
                                                    key,
                                                    typ_key,
                                                    split[3],
                                                )
                                                return
                                            }
                                        case "param":
                                            idx, idx_ok := strconv.parse_i64(
                                                split[2],
                                            )
                                            if !idx_ok {
                                                err = errors.message(
                                                    "\"from.{}.types.{}\" is invalid \"{}\" is not an integer",
                                                    key,
                                                    typ_key,
                                                    split[2],
                                                )
                                                return
                                            }

                                            switch split[3] {
                                            case "type":
                                                ow.instruction =
                                                    OverwriteParameterType {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case "name":
                                                ow.instruction =
                                                    OverwriteParameterName {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case:
                                                err = errors.message(
                                                    "\"from.{}.types.{}\" is invalid \"{}\"",
                                                    key,
                                                    typ_key,
                                                    split[3],
                                                )
                                                return
                                            }
                                        case:
                                            err = errors.message(
                                                "\"from.{}.types.{}\" is invalid \"{}\"",
                                                key,
                                                typ_key,
                                                split[1],
                                            )
                                            return
                                        }
                                    case:
                                        err = errors.message(
                                            "\"from.{}.types.{}\" is invalid: too much \".\"",
                                            key,
                                            typ_key,
                                        )
                                        return
                                    }

                                    append(&o_set.types, ow)
                                }
                            case:
                                err = errors.message(
                                    "\"from.{}.types\" has invalid type %T",
                                    key,
                                    typ,
                                )
                                return
                            }
                        }

                        if "functions" in v {
                            // func_name: "#Untyped" -> OverwriteWhole
                            // func_name.return: "#Untyped" -> OverwriteReturnType
                            // func_name.param.2.type: "#Untyped" -> OverwriteParameterType
                            // func_name.param.2.name: "#Untyped" -> OverwriteParameterName
                            #partial switch fun in v["functions"] {
                            case yaml.Mapping:
                                for fun_key, fun_value in fun {
                                    overwrite_value: string = ---
                                    #partial switch fun_v in fun_value {
                                    case string:
                                        overwrite_value = fun_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.functions.{}\" has invalid type %T",
                                            key,
                                            fun_key,
                                            fun_v,
                                        )
                                        return
                                    }

                                    split := strings.split(fun_key, ".")
                                    defer delete(split)

                                    ow: Overwrite = ---
                                    ow.name = split[0]

                                    switch len(split) {
                                    case 1:
                                        ow.instruction = OverwriteWhole(
                                            overwrite_value,
                                        )
                                    case 2:
                                        switch split[1] {
                                        case "name":
                                            ow.instruction = OverwriteName {
                                                overwrite_value,
                                            }
                                        case "return":
                                            ow.instruction =
                                                OverwriteReturnType(
                                                    overwrite_value,
                                                )
                                        case:
                                            err = errors.message(
                                                "\"from.{}.functions.{}\" is invalid \"{}\"",
                                                key,
                                                fun_key,
                                                split[1],
                                            )
                                            return
                                        }
                                    case 4:
                                        switch split[1] {
                                        case "param":
                                            idx, idx_ok := strconv.parse_i64(
                                                split[2],
                                            )
                                            if !idx_ok {
                                                err = errors.message(
                                                    "\"from.{}.functions.{}\" is invalid \"{}\" is not an integer",
                                                    key,
                                                    fun_key,
                                                    split[2],
                                                )
                                                return
                                            }

                                            switch split[3] {
                                            case "type":
                                                ow.instruction =
                                                    OverwriteParameterType {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case "name":
                                                ow.instruction =
                                                    OverwriteParameterName {
                                                        idx       = int(idx),
                                                        overwrite = overwrite_value,
                                                    }
                                            case:
                                                err = errors.message(
                                                    "\"from.{}.functions.{}\" is invalid \"{}\"",
                                                    key,
                                                    fun_key,
                                                    split[3],
                                                )
                                                return
                                            }
                                        case:
                                            err = errors.message(
                                                "\"from.{}.functions.{}\" is invalid \"{}\"",
                                                key,
                                                fun_key,
                                                split[1],
                                            )
                                            return
                                        }
                                    case:
                                        err = errors.message(
                                            "\"from.{}.functions.{}\" is invalid: too much \".\"",
                                            key,
                                            fun_key,
                                        )
                                        return
                                    }

                                    append(&o_set.functions, ow)
                                }
                            case:
                                err = errors.message(
                                    "\"from.{}.functions\" has invalid type %T",
                                    key,
                                    fun,
                                )
                                return
                            }
                        }
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.overwrite.d[plat] = o_set
                case "headers":
                    h_seq := make([dynamic]string, rn_arena_alloc)

                    #partial switch v in value {
                    case string:
                        append(
                            &h_seq,
                            relative_to_file(file_path, v, rn_arena_alloc),
                        )
                    case yaml.Sequence:
                        for seq_v, idx in v {
                            #partial switch v_seq in seq_v {
                            case string:
                                append(
                                    &h_seq,
                                    relative_to_file(
                                        file_path,
                                        v_seq,
                                        rn_arena_alloc,
                                    ),
                                )
                            case:
                                err = errors.message(
                                    "\"from.{}\"[{}] has invalid type %T",
                                    key,
                                    idx,
                                    v_seq,
                                )
                                return
                            }
                        }
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.headers.d[plat] = h_seq[:]
                case "includedirs":
                    i_seq := make([dynamic]string, rn_arena_alloc)

                    if value == nil {
                        f.includedirs.d[plat] = i_seq[:]
                        break
                    }

                    #partial switch v in value {
                    case string:
                        append(
                            &i_seq,
                            relative_to_file(file_path, v, rn_arena_alloc),
                        )
                    case yaml.Sequence:
                        for seq_v, idx in v {
                            #partial switch v_seq in seq_v {
                            case string:
                                append(
                                    &i_seq,
                                    relative_to_file(
                                        file_path,
                                        v_seq,
                                        rn_arena_alloc,
                                    ),
                                )
                            case:
                                err = errors.message(
                                    "\"from.{}\"[{}] has invalid type %T",
                                    key,
                                    idx,
                                    v_seq,
                                )
                                return
                            }
                        }
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.includedirs.d[plat] = i_seq[:]
                case "defines":
                    if value == nil {
                        f.defines.d[plat] = make(
                            map[string]string,
                            allocator = rn_arena_alloc,
                        )
                        break
                    }

                    #partial switch v in value {
                    case yaml.Mapping:
                        d_map := make(
                            map[string]string,
                            len(v),
                            allocator = rn_arena_alloc,
                        )

                        for d_key, d_value in v {
                            #partial switch d_v in d_value {
                            case string:
                                d_map[d_key] = d_v
                            case i64:
                                buf, mem_err := make(
                                    [dynamic]u8,
                                    256,
                                    rn_arena_alloc,
                                )
                                errors.wrap(mem_err) or_return

                                d_map[d_key] = strconv.write_int(
                                    buf[:],
                                    d_v,
                                    10,
                                )
                            case f64:
                                buf, mem_err := make(
                                    [dynamic]u8,
                                    310,
                                    rn_arena_alloc,
                                )
                                errors.wrap(mem_err) or_return

                                d_map[d_key] = strconv.write_float(
                                    buf[:],
                                    d_v,
                                    'f',
                                    4,
                                    64,
                                )
                            case bool:
                                if d_v {
                                    d_map[d_key] = "1"
                                } else {
                                    d_map[d_key] = "0"
                                }
                            case:
                                err = errors.message(
                                    "\"from.{}.{}\" has invalid type %T",
                                    key,
                                    d_key,
                                    d_v,
                                )
                                return
                            }
                        }

                        f.defines.d[plat] = d_map
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                case "enable_host_includes":
                    #partial switch v in value {
                    case bool:
                        f.enable_host_includes.d[plat] = v
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                case "disable_system_include_gen":
                    #partial switch v in value {
                    case bool:
                        f.disable_system_include_gen.d[plat] = v
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                case "disable_stdint_macros":
                    #partial switch v in value {
                    case bool:
                        f.disable_stdint_macros.d[plat] = v
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                case "flags":
                    flags := make([dynamic]cstring, rn_arena_alloc)

                    if value == nil {
                        f.flags.d[plat] = flags[:]
                    }

                    #partial switch v in value {
                    case yaml.Sequence:
                        for f, idx in v {
                            if f_str, ok := f.(string); ok {
                                append(
                                    &flags,
                                    strings.clone_to_cstring(
                                        f_str,
                                        rn_arena_alloc,
                                    ),
                                )
                            } else {
                                err = errors.message(
                                    "\"from.{}\"[{}] has invalud type %T",
                                    key,
                                    idx,
                                    f,
                                )
                                return
                            }
                        }
                    case string:
                        append(
                            &flags,
                            strings.clone_to_cstring(v, rn_arena_alloc),
                        )
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.flags.d[plat] = flags[:]
                case "load_all_includes":
                    #partial switch v in value {
                    case bool:
                        f.load_all_includes.d[plat] = v
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                case "forward_decl_type":
                    #partial switch v in value {
                    case string:
                        v_type, v_err := parse_type(v)
                        if v_err != nil {
                            err = errors.message(
                                "\"from.{}\": failed to parse type: {}",
                                key,
                                v_err,
                            )
                            return
                        }

                        f.forward_decl_type.d[plat] = v_type
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }
                case "packages":
                    p_seq := make([dynamic]string, rn_arena_alloc)

                    #partial switch v in value {
                    case string:
                        append(
                            &p_seq,
                            relative_to_file(file_path, v, rn_arena_alloc),
                        )
                    case yaml.Sequence:
                        for seq_v, idx in v {
                            #partial switch v_seq in seq_v {
                            case string:
                                append(
                                    &p_seq,
                                    relative_to_file(
                                        file_path,
                                        v_seq,
                                        rn_arena_alloc,
                                    ),
                                )
                            case:
                                err = errors.message(
                                    "\"from.{}\"[{}] has invalid type %T",
                                    key,
                                    idx,
                                    v_seq,
                                )
                                return
                            }
                        }
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.packages.d[plat] = p_seq[:]
                }
            }

            if extern_value, ok := from["extern"]; ok {
                #partial switch extern in extern_value {
                case string:
                    extern_arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 1,
                        cap = 1,
                    )
                    extern_arr[0] = extern
                    f.extern = extern_arr[:]
                case yaml.Sequence:
                    extern_arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 0,
                        cap = len(extern),
                    )

                    for ex, idx in extern {
                        #partial switch extern_element in ex {
                        case string:
                            append(&extern_arr, extern_element)
                        case:
                            err = errors.message(
                                "\"from.extern[{}]\" has invalid type",
                                idx,
                            )
                            return
                        }
                    }

                    f.extern = extern_arr[:]
                case:
                    err = errors.message("\"from.extern\" has invalid type")
                    return
                }
            }

            if remaps_value, remaps_ok := from["remaps"]; remaps_ok {
                #partial switch remaps in remaps_value {
                case yaml.Mapping:
                    for remap_name, remap_value_value in remaps {
                        #partial switch remap_value in remap_value_value {
                        case string:
                            f.remaps[remap_name] = remap_value
                        case:
                            err = errors.message(
                                "\"from.remaps.{}\" has invalid type",
                                remap_name,
                            )
                            return
                        }
                    }
                case:
                    err = errors.message("\"from.remaps\" has invalid type")
                    return
                }
            }

            if aliases_value, aliases_ok := from["aliases"]; aliases_ok {
                #partial switch aliases in aliases_value {
                case yaml.Mapping:
                    for alias_name, alias_value_value in aliases {
                        #partial switch alias_value in alias_value_value {
                        case string:
                            arr := make(
                                [dynamic]string,
                                allocator = rn_arena_alloc,
                                len = 1,
                                cap = 1,
                            )
                            arr[0] = alias_value
                            f.aliases[alias_name] = arr[:]
                        case yaml.Sequence:
                            arr := make(
                                [dynamic]string,
                                allocator = rn_arena_alloc,
                                len = 0,
                                cap = len(alias_value),
                            )

                            for alias_v, idx in alias_value {
                                #partial switch alias in alias_v {
                                case string:
                                    append(&arr, alias)
                                case:
                                    err = errors.message(
                                        "\"from.aliases.{}\"[{}] has invalid type",
                                        alias_name,
                                        idx,
                                    )
                                    return
                                }
                            }
                            f.aliases[alias_name] = arr[:]
                        case:
                            err = errors.message(
                                "\"from.aliases.{}\" has invalid type",
                                alias_name,
                            )
                            return
                        }
                    }
                case:
                    err = errors.message("\"from.remaps\" has invalid type")
                    return
                }
            }

            rn.from = f
        case string:
            if from != "stdin" {
                rn.from = relative_to_file(file_path, from, rn_arena_alloc)
            } else {
                rn.from = from
            }
        case yaml.Sequence:
            f := make(
                [dynamic]string,
                allocator = rn_arena_alloc,
                len = 0,
                cap = len(from),
            )

            for value, idx in from {
                #partial switch v in value {
                case string:
                    append(&f, relative_to_file(file_path, v, rn_arena_alloc))
                case:
                    err = errors.message(
                        "\"from\"[{}] has invalid type %T",
                        idx,
                        v,
                    )
                    return
                }
            }

            rn.from = f
        case:
            err = errors.message("\"from\" has invalid type %T", from)
            return
        }

        #partial switch to in y["to"] {
        case yaml.Mapping:
            t: To

            if language, ok := to["language"]; ok {
                t.language, ok = language.(string)
                errors.wrap(ok, "\"to.language\" has invalid type") or_return
            } else {
                err = errors.message("\"to.language\" is missing")
                return
            }

            if static_switch, ok := to["static_switch"]; ok {
                t.static_switch, ok = static_switch.(string)
                errors.wrap(
                    ok,
                    "\"to.static_switch\" has invalid type",
                ) or_return
            }

            if out, ok := to["out"]; ok {
                t.out, ok = out.(string)
                errors.wrap(ok, "\"to.out\" has invalid type") or_return
                t.out = relative_to_file(file_path, t.out, rn_arena_alloc)
            }

            if "trim_prefix" in to {
                #partial switch trim_prefix in to["trim_prefix"] {
                case string:
                    arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 1,
                        cap = 1,
                    )
                    arr[0] = trim_prefix

                    t.trim_prefix.functions = arr[:]
                    t.trim_prefix.variables = arr[:]
                    t.trim_prefix.types = arr[:]
                    t.trim_prefix.constants = arr[:]
                case yaml.Sequence:
                    arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 0,
                        cap = len(trim_prefix),
                    )

                    for seq_v, idx in trim_prefix {
                        #partial switch v_seq in seq_v {
                        case string:
                            append(&arr, v_seq)
                        case:
                            err = errors.message(
                                "\"to.trim_prefix\"[{}] has invalid type %T",
                                idx,
                                v_seq,
                            )
                            return
                        }
                    }

                    t.trim_prefix.functions = arr[:]
                    t.trim_prefix.variables = arr[:]
                    t.trim_prefix.types = arr[:]
                    t.trim_prefix.constants = arr[:]
                case yaml.Mapping:
                    functions_arr := make([dynamic]string, rn_arena_alloc)
                    variables_arr := make([dynamic]string, rn_arena_alloc)
                    types_arr := make([dynamic]string, rn_arena_alloc)
                    constants_arr := make([dynamic]string, rn_arena_alloc)

                    if "functions" in trim_prefix {
                        #partial switch f in trim_prefix["functions"] {
                        case string:
                            append(&functions_arr, f)
                        case yaml.Sequence:
                            for seq_f, idx in f {
                                #partial switch f_seq in seq_f {
                                case string:
                                    append(&functions_arr, f_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_prefix.functions\"[{}] has invalid type %T",
                                        idx,
                                        f_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_prefix.functions\" has invald type %T",
                                f,
                            )
                            return
                        }
                    }

                    if "variables" in trim_prefix {
                        #partial switch var in trim_prefix["variables"] {
                        case string:
                            append(&variables_arr, var)
                        case yaml.Sequence:
                            for seq_v, idx in var {
                                #partial switch v_seq in seq_v {
                                case string:
                                    append(&variables_arr, v_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_prefix.variables\"[{}] has invalid type %T",
                                        idx,
                                        v_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_prefix.variables\" has invald type %T",
                                var,
                            )
                            return
                        }
                    }

                    if "types" in trim_prefix {
                        #partial switch t in trim_prefix["types"] {
                        case string:
                            append(&types_arr, t)
                        case yaml.Sequence:
                            for seq_t, idx in t {
                                #partial switch t_seq in seq_t {
                                case string:
                                    append(&types_arr, t_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_prefix.types\"[{}] has invalid type %T",
                                        idx,
                                        t_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_prefix.types\" has invald type %T",
                                t,
                            )
                            return
                        }
                    }

                    if "constants" in trim_prefix {
                        #partial switch c in trim_prefix["constants"] {
                        case string:
                            append(&constants_arr, c)
                        case yaml.Sequence:
                            for seq_c, idx in c {
                                #partial switch c_seq in seq_c {
                                case string:
                                    append(&constants_arr, c_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_prefix.constants\"[{}] has invalid type %T",
                                        idx,
                                        c_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_prefix.constants\" has invald type %T",
                                t,
                            )
                            return
                        }
                    }

                    if "enum_type_name" in trim_prefix {
                        #partial switch etn in trim_prefix["enum_type_name"] {
                        case bool:
                            t.trim_prefix.enum_type_name = etn
                        case:
                            err = errors.message(
                                "\"to.trim_prefix.enum_type_name\" has invalid type %T",
                                t,
                            )
                            return
                        }
                    }

                    t.trim_prefix.functions = functions_arr[:]
                    t.trim_prefix.variables = variables_arr[:]
                    t.trim_prefix.types = types_arr[:]
                    t.trim_prefix.constants = constants_arr[:]
                case:
                    err = errors.message(
                        "\"to.trim_prefix\" has invalid type %T",
                        trim_prefix,
                    )
                    return
                }
            }

            if "trim_suffix" in to {
                #partial switch trim_suffix in to["trim_suffix"] {
                case string:
                    arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 1,
                        cap = 1,
                    )
                    arr[0] = trim_suffix

                    t.trim_suffix.functions = arr[:]
                    t.trim_suffix.variables = arr[:]
                    t.trim_suffix.types = arr[:]
                    t.trim_suffix.constants = arr[:]
                case yaml.Sequence:
                    arr := make(
                        [dynamic]string,
                        allocator = rn_arena_alloc,
                        len = 0,
                        cap = len(trim_suffix),
                    )

                    for v_seq, idx in trim_suffix {
                        #partial switch seq_v in v_seq {
                        case string:
                            append(&arr, seq_v)
                        case:
                            err = errors.message(
                                "\"to.trim_suffix\"[{}] has invalid type %T",
                                idx,
                                seq_v,
                            )
                            return
                        }
                    }

                    t.trim_suffix.functions = arr[:]
                    t.trim_suffix.variables = arr[:]
                    t.trim_suffix.types = arr[:]
                    t.trim_suffix.constants = arr[:]
                case yaml.Mapping:
                    functions_arr := make([dynamic]string, rn_arena_alloc)
                    variables_arr := make([dynamic]string, rn_arena_alloc)
                    types_arr := make([dynamic]string, rn_arena_alloc)
                    constants_arr := make([dynamic]string, rn_arena_alloc)

                    if "functions" in trim_suffix {
                        #partial switch f in trim_suffix["functions"] {
                        case string:
                            append(&functions_arr, f)
                        case yaml.Sequence:
                            for seq_f, idx in f {
                                #partial switch f_seq in seq_f {
                                case string:
                                    append(&functions_arr, f_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_suffix.functions\"[{}] has invalid type %T",
                                        idx,
                                        f_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_suffix.functions\" has invald type %T",
                                f,
                            )
                            return
                        }
                    }

                    if "variables" in trim_suffix {
                        #partial switch var in trim_suffix["variables"] {
                        case string:
                            append(&variables_arr, var)
                        case yaml.Sequence:
                            for seq_v, idx in var {
                                #partial switch v_seq in seq_v {
                                case string:
                                    append(&variables_arr, v_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_suffix.variables\"[{}] has invalid type %T",
                                        idx,
                                        v_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_suffix.variables\" has invald type %T",
                                var,
                            )
                            return
                        }
                    }

                    if "types" in trim_suffix {
                        #partial switch t in trim_suffix["types"] {
                        case string:
                            append(&types_arr, t)
                        case yaml.Sequence:
                            for seq_t, idx in t {
                                #partial switch t_seq in seq_t {
                                case string:
                                    append(&types_arr, t_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_suffix.types\"[{}] has invalid type %T",
                                        idx,
                                        t_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_suffix.types\" has invald type %T",
                                t,
                            )
                            return
                        }
                    }

                    if "constants" in trim_suffix {
                        #partial switch c in trim_suffix["constants"] {
                        case string:
                            append(&constants_arr, c)
                        case yaml.Sequence:
                            for seq_c, idx in c {
                                #partial switch c_seq in seq_c {
                                case string:
                                    append(&constants_arr, c_seq)
                                case:
                                    err = errors.message(
                                        "\"to.trim_suffix.constants\"[{}] has invalid type %T",
                                        idx,
                                        c_seq,
                                    )
                                    return
                                }
                            }
                        case:
                            err = errors.message(
                                "\"to.trim_suffix.constants\" has invald type %T",
                                t,
                            )
                            return
                        }
                    }
                    t.trim_suffix.functions = functions_arr[:]
                    t.trim_suffix.variables = variables_arr[:]
                    t.trim_suffix.types = types_arr[:]
                    t.trim_suffix.constants = constants_arr[:]
                case:
                    err = errors.message(
                        "\"to.trim_suffix\" has invalid type %T",
                        trim_suffix,
                    )
                    return
                }
            }

            if "add_prefix" in to {
                #partial switch add_prfx in to["add_prefix"] {
                case string:
                    t.add_prefix.functions = add_prfx
                    t.add_prefix.variables = add_prfx
                    t.add_prefix.types = add_prfx
                    t.add_prefix.constants = add_prfx
                case yaml.Mapping:
                    ok: bool = ---
                    if "functions" in add_prfx {
                        t.add_prefix.functions, ok =
                        add_prfx["functions"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_prefix.functions\" has invalid type",
                        ) or_return
                    }

                    if "variables" in add_prfx {
                        t.add_prefix.variables, ok =
                        add_prfx["variables"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_prefix.variables\" has invalid type",
                        ) or_return
                    }

                    if "types" in add_prfx {
                        t.add_prefix.types, ok = add_prfx["types"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_prefix.types\" has invalid type",
                        ) or_return
                    }

                    if "constants" in add_prfx {
                        t.add_prefix.constants, ok =
                        add_prfx["constants"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_prefix.constants\" has invalid type",
                        ) or_return
                    }
                case:
                    err = errors.message(
                        "\"to.add_prefix\" has invalid type %T",
                        add_prfx,
                    )
                    return
                }
            }

            if "add_suffix" in to {
                #partial switch add_sfx in to["add_suffix"] {
                case string:
                    t.add_suffix.functions = add_sfx
                    t.add_suffix.variables = add_sfx
                    t.add_suffix.types = add_sfx
                    t.add_suffix.constants = add_sfx
                case yaml.Mapping:
                    ok: bool = ---
                    if "functions" in add_sfx {
                        t.add_suffix.functions, ok =
                        add_sfx["functions"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_suffix.functions\" has invalid type",
                        ) or_return
                    }

                    if "variables" in add_sfx {
                        t.add_suffix.variables, ok =
                        add_sfx["variables"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_suffix.variables\" has invalid type",
                        ) or_return
                    }

                    if "types" in add_sfx {
                        t.add_suffix.types, ok = add_sfx["types"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_suffix.types\" has invalid type",
                        ) or_return
                    }

                    if "constants" in add_sfx {
                        t.add_suffix.constants, ok =
                        add_sfx["constants"].(string)
                        errors.wrap(
                            ok,
                            "\"to.add_suffix.constants\" has invalid type",
                        ) or_return
                    }
                case:
                    err = errors.message(
                        "\"to.add_suffix\" has invalid type %T",
                        add_sfx,
                    )
                    return
                }
            }

            if ignore_arch, ok := to["ignore_arch"]; ok {
                t.ignore_arch, ok = ignore_arch.(bool)
                errors.wrap(
                    ok,
                    "\"to.ignore_arch\" has invalid type",
                ) or_return
            }
            if package_name, ok := to["package"]; ok {
                t.package_name, ok = package_name.(string)
                errors.wrap(ok, "\"to.package\" has invalid type") or_return
            }

            if detect, ok := to["detect"]; ok {
                #partial switch d in detect {
                case yaml.Mapping:
                    if multi_pointer, mp_ok := d["multi_pointer"]; mp_ok {
                        t.detect.multi_pointer, mp_ok = multi_pointer.(string)
                        errors.wrap(
                            mp_ok,
                            "\"to.detect.multi_pointer\" has invalid type",
                        ) or_return
                    }
                case:
                    err = errors.message(
                        "\"to.detect\" has invalid type %T",
                        d,
                    )
                    return
                }
            }

            if len(t.detect.multi_pointer) == 0 {
                t.detect.multi_pointer = "auto"
            }

            if no_build_tag, ok := to["no_build_tag"]; ok {
                t.no_build_tag, ok = no_build_tag.(bool)
                errors.wrap(
                    ok,
                    "\"to.no_build_tag\" has invalid type",
                ) or_return
            }
            if use_when_else, ok := to["use_when_else"]; ok {
                t.use_when_else, ok = use_when_else.(bool)
                errors.wrap(ok, "\"to.use_when_else\" has invalid type")
            }

            if extern_value, ok := to["extern"]; ok {
                #partial switch extern in extern_value {
                case yaml.Mapping:
                    sources_value, sources_ok := extern["sources"]
                    errors.assert(
                        sources_ok,
                        "\"to.extern.sources\" is missing",
                    ) or_return

                    #partial switch sources in sources_value {
                    case yaml.Mapping:
                        t.extern.sources = make(
                            map[string]string,
                            len(sources),
                            allocator = rn_arena_alloc,
                        )

                        for source_name, import_name_value in sources {
                            import_name, import_name_ok := import_name_value.(string)
                            errors.assert(
                                import_name_ok,
                                "\"to.extern.sources\" has invalid entries",
                            ) or_return
                            t.extern.sources[source_name] = import_name
                        }
                    case:
                        err = errors.message(
                            "\"to.extern.sources\" has invalid type",
                        )
                        return
                    }

                    if remaps_value, remaps_ok := extern["remaps"]; remaps_ok {
                        #partial switch remaps in remaps_value {
                        case yaml.Mapping:
                            t.extern.remaps = make(
                                map[string]string,
                                len(remaps),
                                allocator = rn_arena_alloc,
                            )

                            for type_name, remap_name_value in remaps {
                                remap_name, remap_name_ok := remap_name_value.(string)
                                errors.assert(
                                    remap_name_ok,
                                    "\"to.extern.remaps\" has invalid entries",
                                ) or_return

                                t.extern.remaps[type_name] = remap_name
                            }
                        case:
                            err = errors.message(
                                "\"to.extern.remaps\" has invalid type",
                            )
                            return
                        }
                    }

                    if trim_prefix_value, tp_ok := extern["trim_prefix"];
                       tp_ok {
                        t.extern.trim_prefix, tp_ok = trim_prefix_value.(bool)
                        errors.assert(
                            tp_ok,
                            "\"to.extern.trim_prefix\" has invalid type",
                        ) or_return
                    }

                    if trim_suffix_value, tp_ok := extern["trim_suffix"];
                       tp_ok {
                        t.extern.trim_suffix, tp_ok = trim_suffix_value.(bool)
                        errors.assert(
                            tp_ok,
                            "\"to.extern.trim_suffix\" has invalid type",
                        ) or_return
                    }

                    if add_prefix_value, tp_ok := extern["add_prefix"]; tp_ok {
                        t.extern.add_prefix, tp_ok = add_prefix_value.(bool)
                        errors.assert(
                            tp_ok,
                            "\"to.extern.add_prefix\" has invalid type",
                        ) or_return
                    }

                    if add_suffix_value, tp_ok := extern["add_suffix"]; tp_ok {
                        t.extern.add_suffix, tp_ok = add_suffix_value.(bool)
                        errors.assert(
                            tp_ok,
                            "\"to.extern.add_suffix\" has invalid type",
                        ) or_return
                    }

                case:
                    err = errors.message("\"to.extern\" has invalid type")
                    return
                }
            }

            {
                context.allocator = rn_arena_alloc

                t.add_libs_shared = make_platform_value([]string)
                t.add_libs_static = make_platform_value([]string)
            }

            for key, value in to {
                splits, alloc_err := strings.split(key, ".")
                errors.wrap(alloc_err) or_return

                name: string = ---
                os, arch: Maybe(string)
                lib_type: Maybe(string)

                #no_bounds_check switch len(splits) {
                case 0:
                    err = errors.message("invalid key in \"to\"")
                    return
                case 1:
                    name = splits[0]
                case 2:
                    name = splits[0]
                    if name == "add_libs" {
                        if splits[1] == "static" || splits[1] == "shared" {
                            lib_type = splits[1]
                            break
                        }
                    }

                    os = splits[1]
                case 3:
                    name = splits[0]
                    if name == "add_libs" {
                        if splits[1] == "static" || splits[1] == "shared" {
                            lib_type = splits[1]
                            os = splits[2]
                            break
                        }
                    }

                    os = splits[1]
                    arch = splits[2]
                case 4:
                    name = splits[0]
                    if name == "add_libs" {
                        if splits[1] != "static" && splits[1] != "shared" {
                            err = errors.message(
                                "invalid key in \"from\": {}. Must be either {}.static.{}.{} or {}.shared.{}.{}",
                                key,
                                splits[0],
                                splits[2],
                                splits[3],
                                splits[0],
                                splits[2],
                                splits[3],
                            )
                            return
                        }
                        lib_type = splits[1]
                        os = splits[2]
                        arch = splits[3]
                    } else {
                        err = errors.message(
                            "invalid key in \"from\": {}",
                            key,
                        )
                        return
                    }
                case:
                    err = errors.message("invalid key in \"from\": {}", key)
                    return
                }

                delete(splits)

                plat, plat_ok := platform_from_strings(os, arch)
                if !plat_ok {
                    err = errors.message(
                        "invalid platform for \"from.{}\" os=\"{}\" arch=\"{}\"",
                        name,
                        os,
                        arch,
                    )
                    return
                }

                switch name {
                case "add_libs":
                    arr: [dynamic]string = ---
                    #partial switch v in value {
                    case string:
                        arr = make(
                            [dynamic]string,
                            len = 1,
                            cap = 1,
                            allocator = rn_arena_alloc,
                        )
                        arr[0] = relative_to_file(
                            file_path,
                            v,
                            rn_arena_alloc,
                            true,
                        )

                    case yaml.Sequence:
                        arr = make(
                            [dynamic]string,
                            len = 0,
                            cap = len(v),
                            allocator = rn_arena_alloc,
                        )
                        for lib, lib_idx in v {
                            #partial switch l in lib {
                            case string:
                                append(
                                    &arr,
                                    relative_to_file(
                                        file_path,
                                        l,
                                        rn_arena_alloc,
                                        true,
                                    ),
                                )
                            case:
                                err = errors.message(
                                    "\"to.{}\"[{}] has invalid type: %T",
                                    key,
                                    lib_idx,
                                    l,
                                )
                                return
                            }
                        }
                    case:
                        err = errors.message(
                            "\"to.{}\" has invalid type: %T",
                            key,
                            v,
                        )
                        return
                    }

                    if lt, lt_ok := lib_type.?; lt_ok {
                        switch lt {
                        case "static":
                            t.add_libs_static.d[plat] = arr[:]
                        case "shared":
                            t.add_libs_shared.d[plat] = arr[:]
                        }
                    } else {
                        t.add_libs_static.d[plat] = arr[:]
                        t.add_libs_shared.d[plat] = arr[:]
                    }
                }
            }

            rn.to = t
        case string:
            if to != "stdout" {
                rn.to = relative_to_file(file_path, to, rn_arena_alloc)
            } else {
                rn.to = to
            }
        case:
            err = errors.message("\"to\" has invalid type %T", to)
        }
    case:
        err = errors.message("yaml file has invalid type %T", y)
        return
    }

    // Add the out header to the header of from if requested
    if wrapper, wrapper_ok := rn.wrapper.?;
       wrapper_ok && wrapper.add_header_to_from {
        #partial switch &from in rn.from {
        case From:
            // First gather all different out headers based on the platform
            out_headers := make(map[Platform]string)
            defer delete(out_headers)

            if !wrapper.multi_platform || len(rn.platforms) < 2 {
                out_headers[{}] = wrapper.out_header
            } else {
                for rn_plat in rn.platforms {
                    out_header_platted := platform_file_name(
                        wrapper.out_header,
                        rn_plat,
                        rn_arena_alloc,
                    )

                    out_headers[rn_plat] = out_header_platted
                }
            }

            // Try to insert everyone of these out headers into the headers separately
            for plat, header in out_headers {
                inserted: bool

                // If it is already there insert it into them
                for from_plat, &from_headers in from.headers.d {
                    if from_plat != plat do continue

                    arr := make(
                        [dynamic]string,
                        len = 0,
                        cap = len(from_headers) + 1,
                        allocator = rn_arena_alloc,
                    )
                    append(&arr, ..from_headers)
                    append(&arr, header)

                    from_headers = arr[:]
                    inserted = true
                }

                // Otherwise find the next most common platform and add them together as a new entry
                if !inserted {
                    more_common_headers: Maybe([]string)

                    common_plat := Platform{plat.os, .Any}
                    if common_plat in from.headers.d {
                        more_common_headers = from.headers.d[common_plat]
                    } else {
                        common_plat = {.Any, .Any}
                        if common_plat in from.headers.d {
                            more_common_headers = from.headers.d[common_plat]
                        }
                    }

                    cap := 1
                    if more_common_headers == nil {
                        common_plat = plat
                    } else {
                        cap += len(more_common_headers.?)
                    }

                    arr := make(
                        [dynamic]string,
                        len = 0,
                        cap = cap,
                        allocator = rn_arena_alloc,
                    )
                    append(&arr, ..(more_common_headers.? or_else []string{}))
                    append(&arr, header)

                    from.headers.d[plat] = arr[:]
                }
            }
        }
    }

    return
}

rune_destroy :: proc(rn: ^Rune) {
    runtime.arena_destroy(&rn.arena)
}

@(private = "file")
single_list_trim_prefix :: #force_inline proc(
    ident: string,
    list: []string,
) -> string {
    str := ident
    for v in list {
        str = strings.trim_prefix(str, v)
    }
    return str
}

@(private = "file")
single_list_trim_suffix :: #force_inline proc(
    ident: string,
    list: []string,
) -> string {
    str := ident
    for v in list {
        str = strings.trim_suffix(str, v)
    }
    return str
}

@(private = "file")
add_prefix :: #force_inline proc(
    ident: string,
    prefix: string,
    allocator := context.allocator,
) -> string {
    return strings.concatenate({prefix, ident}, allocator)
}

@(private = "file")
add_suffix :: #force_inline proc(
    ident: string,
    suffix: string,
    allocator := context.allocator,
) -> string {
    return strings.concatenate({ident, suffix}, allocator)
}

@(private = "file")
is_valid_identifier :: proc(ident: string) -> bool {
    if len(ident) == 0 do return false

    for r, idx in ident {
        if !(unicode.is_letter(r) || r == '_') {
            if idx == 0 || !unicode.is_number(r) do return false
        }
    }


    return true
}

@(private = "file")
process_identifier :: #force_inline proc(
    ident: string,
    trim_prefix, trim_suffix: []string,
    add_pf, add_sf: string,
    reserved: []string,
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    if !valid_ident(ident) do return ident

    ident1 := single_list_trim_prefix(ident, trim_prefix)
    if !valid_ident(ident1) do return ident

    ident2 := single_list_trim_suffix(ident1, trim_suffix)
    if !valid_ident(ident2) do return ident1

    ident3 := add_prefix(ident2, add_pf, allocator)
    if !valid_ident(ident3) do return ident2

    ident4 := add_suffix(ident3, add_sf, allocator)
    if !valid_ident(ident4) {
        delete(ident4, allocator)
        return ident3
    }
    delete(ident3, allocator)

    if slice.contains(reserved, ident4) {
        ident5 := strings.concatenate({ident4, "_"}, allocator)
        delete(ident4, allocator)
        ident4 = ident5
    }

    return ident4
}

process_function_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        rn.trim_prefix.functions,
        rn.trim_suffix.functions,
        rn.add_prefix.functions,
        rn.add_suffix.functions,
        reserved,
        valid_ident,
        allocator,
    )
}

process_variable_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        rn.trim_prefix.variables,
        rn.trim_suffix.variables,
        rn.add_prefix.variables,
        rn.add_suffix.variables,
        reserved,
        valid_ident,
        allocator,
    )
}

process_type_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
    extern := false,
) -> string {
    return process_identifier(
        ident,
        {} if (extern && !rn.extern.trim_prefix) else rn.trim_prefix.types,
        {} if (extern && !rn.extern.trim_suffix) else rn.trim_suffix.types,
        {} if (extern && !rn.extern.add_prefix) else rn.add_prefix.types,
        {} if (extern && !rn.extern.add_suffix) else rn.add_suffix.types,
        reserved,
        valid_ident,
        allocator,
    )
}

process_constant_name :: proc(
    ident: string,
    rn: To,
    reserved: []string = {},
    valid_ident := is_valid_identifier,
    allocator := context.allocator,
) -> string {
    return process_identifier(
        ident,
        rn.trim_prefix.constants,
        rn.trim_suffix.constants,
        rn.add_prefix.constants,
        rn.add_suffix.constants,
        reserved,
        valid_ident,
        allocator,
    )
}

relative_to_file :: proc(
    rune_file_name, file_name: string,
    allocator := context.allocator,
    needs_dir := false,
) -> (
    string,
    bool,
) #optional_ok {
    if len(file_name) == 0 do return file_name, true
    if filepath.is_abs(file_name) || (needs_dir && !strings.contains(file_name, "/") && !strings.contains(file_name, "\\")) do return strings.clone(file_name, allocator), true

    rune_dir := filepath.dir(rune_file_name, allocator)
    defer delete(rune_dir, allocator)

    if !filepath.is_abs(rune_dir) {
        abs_rune_dir, ok := filepath.abs(rune_dir, allocator)
        if ok {
            delete(rune_dir, allocator)
            rune_dir = abs_rune_dir
        }
    }

    rel_path := filepath.join({rune_dir, file_name}, allocator)
    return rel_path, true
}

absolute_to_file :: proc(
    rune_file_name, file_name: string,
    allocator := context.allocator,
) -> (
    string,
    bool,
) #optional_ok {
    if !filepath.is_abs(file_name) {
        return strings.clone(file_name, allocator), true
    }

    rune_dir := filepath.dir(rune_file_name, allocator)
    defer delete(rune_dir, allocator)

    rel_path, rel_err := filepath.rel(rune_dir, file_name, allocator)
    if rel_err != .None do return file_name, false

    return rel_path, true
}

single_list_glob :: proc(list: []string, value: string) -> bool {
    for p in list {
        ok, _ := slashpath.match(p, value)
        if ok do return true
    }

    return false
}

map_glob :: proc(m: $M/map[$K]$V, v: K) -> (match: V, ok: bool) #optional_ok {
    for pattern, potential_match in m {
        if matched, _ := slashpath.match(pattern, v); matched {
            return potential_match, true
        }
    }
    return "", false
}

ignore_types :: proc(types: ^om.OrderedMap(string, Type), ignore: IgnoreSet) {
    for idx := 0; idx < len(types.data); idx += 1 {
        entry := types.data[idx]
        name := entry.key

        if single_list_glob(ignore.types, name) {
            om.delete_key(types, name)
            idx -= 1
        }
    }
}

ignore_constants :: proc(
    constants: ^om.OrderedMap(string, Constant),
    ignore: IgnoreSet,
) {
    for idx := 0; idx < len(constants.data); idx += 1 {
        entry := constants.data[idx]
        name := entry.key

        if single_list_glob(ignore.constants, name) {
            om.delete_key(constants, name)
            idx -= 1
        }
    }
}

ignore_symbols :: proc(
    symbols: ^om.OrderedMap(string, Symbol),
    ignore: IgnoreSet,
) {
    for idx := 0; idx < len(symbols.data); idx += 1 {
        entry := symbols.data[idx]
        name, sym := entry.key, entry.value

        switch _ in sym.value {
        case Type:
            if single_list_glob(ignore.variables, name) {
                om.delete_key(symbols, name)
                idx -= 1
            }
        case Function:
            if single_list_glob(ignore.functions, name) {
                om.delete_key(symbols, name)
                idx -= 1
            }
        }
    }
}

overwrite_runestone :: proc(
    rs: ^Runestone,
    overwrite: OverwriteSet,
) -> errors.Error {
    context.allocator = runtime.arena_allocator(&rs.arena)

    for ow in overwrite.constants {
        if idx, ok := om.index(rs.constants, ow.name); ok {
            const := &rs.constants.data[idx].value
            switch o in ow.instruction {
            case OverwriteName:
                rs.constants.data[idx].key = strings.clone(o.overwrite)
                delete_key(&rs.constants.indices, ow.name)
                rs.constants.indices[rs.constants.data[idx].key] = idx
            case OverwriteWhole:
                const^ = parse_constant(strings.clone(string(o))) or_return
            case OverwriteMemberName,
                 OverwriteMemberType,
                 OverwriteReturnType,
                 OverwriteParameterName,
                 OverwriteParameterType:
            }
        }
    }

    for ow in overwrite.functions {
        if idx, ok := om.index(rs.symbols, ow.name); ok {
            sym := &rs.symbols.data[idx].value

            #partial switch &func in sym.value {
            case Function:
                switch o in ow.instruction {
                case OverwriteName:
                    if sym.remap == nil {
                        sym.remap = rs.symbols.data[idx].key
                    }

                    rs.symbols.data[idx].key = strings.clone(o.overwrite)
                    delete_key(&rs.symbols.indices, ow.name)
                    rs.symbols.indices[rs.symbols.data[idx].key] = idx
                case OverwriteWhole:
                    func = parse_func(strings.clone(string(o))) or_return
                case OverwriteReturnType:
                    func.return_type = parse_type(
                        strings.clone(string(o)),
                    ) or_return
                case OverwriteParameterType:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(func.parameters),
                        "overwrite parameter type index is out of bounds",
                    ) or_return

                    #no_bounds_check func.parameters[o.idx].type = parse_type(
                        strings.clone(o.overwrite),
                    ) or_return
                case OverwriteParameterName:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(func.parameters),
                        "overwrite parameter name index is out of bounds",
                    ) or_return

                    #no_bounds_check func.parameters[o.idx].name =
                        strings.clone(o.overwrite)
                case OverwriteMemberName, OverwriteMemberType:
                    return errors.message(
                        "invalid overwrite instruction for function \"{}\"",
                        ow.name,
                    )
                }
            }
        }
    }

    for ow in overwrite.variables {
        if idx, ok := om.index(rs.symbols, ow.name); ok {
            sym := &rs.symbols.data[idx].value

            #partial switch &var in sym.value {
            case Type:
                switch o in ow.instruction {
                case OverwriteName:
                    if sym.remap == nil {
                        sym.remap = rs.symbols.data[idx].key
                    }

                    rs.symbols.data[idx].key = strings.clone(o.overwrite)
                    delete_key(&rs.symbols.indices, ow.name)
                    rs.symbols.indices[rs.symbols.data[idx].key] = idx
                case OverwriteWhole:
                    var = parse_type(strings.clone(string(o))) or_return
                case OverwriteMemberName,
                     OverwriteMemberType,
                     OverwriteReturnType,
                     OverwriteParameterName,
                     OverwriteParameterType:
                }
            }
        }
    }

    for ow in overwrite.types {
        if idx, ok := om.index(rs.types, ow.name); ok {
            type := &rs.types.data[idx].value
            switch o in ow.instruction {
            case OverwriteName:
                rs.types.data[idx].key = strings.clone(o.overwrite)
                delete_key(&rs.types.indices, ow.name)
                rs.types.indices[rs.types.data[idx].key] = idx
            case OverwriteWhole:
                type^ = parse_type(strings.clone(string(o))) or_return
            case OverwriteMemberType:
                #partial switch &t in type.spec {
                case Struct:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.members),
                        "member index is out of bounds",
                    ) or_return
                    #no_bounds_check t.members[o.idx].type = parse_type(
                        strings.clone(o.overwrite),
                    ) or_return
                case Union:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.members),
                        "member index is out of bounds",
                    ) or_return
                    #no_bounds_check t.members[o.idx].type = parse_type(
                        strings.clone(o.overwrite),
                    ) or_return
                case:
                    return errors.message(
                        "member type of \"{}\" can not be changed because it is not a type that has members",
                        ow.name,
                    )
                }
            case OverwriteMemberName:
                #partial switch &t in type.spec {
                case Struct:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.members),
                        "member index is out of bounds",
                    ) or_return
                    #no_bounds_check t.members[o.idx].name = strings.clone(
                        o.overwrite,
                    )
                case Union:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.members),
                        "member index is out of bounds",
                    ) or_return
                    #no_bounds_check t.members[o.idx].name = strings.clone(
                        o.overwrite,
                    )
                case:
                    return errors.message(
                        "member name of \"{}\" can not be changed because it is not a type that has members",
                        ow.name,
                    )
                }
            case OverwriteParameterType:
                #partial switch &t in type.spec {
                case FunctionPointer:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.parameters),
                        "parameter index is out of bounds",
                    ) or_return
                    #no_bounds_check t.parameters[o.idx].type = parse_type(
                        strings.clone(o.overwrite),
                    ) or_return
                case:
                    return errors.message(
                        "parameter type of \"{}\" can not be changed because it is not a function pointer",
                        ow.name,
                    )
                }
            case OverwriteParameterName:
                #partial switch &t in type.spec {
                case FunctionPointer:
                    errors.assert(
                        o.idx >= 0 && o.idx < len(t.parameters),
                        "parameter index is out of bounds",
                    ) or_return
                    #no_bounds_check t.parameters[o.idx].name = strings.clone(
                        o.overwrite,
                    )
                case:
                    return errors.message(
                        "parameter name of \"{}\" can not be changed because it is not a function pointer",
                        ow.name,
                    )
                }
            case OverwriteReturnType:
                #partial switch &t in type.spec {
                case FunctionPointer:
                    t.return_type = parse_type(
                        strings.clone(string(o)),
                    ) or_return
                case:
                    return errors.message(
                        "return type of \"{}\" can not be changed because it does not have a return type",
                        ow.name,
                    )
                }
            }
        }
    }

    return nil
}

check_for_unknown_types_in_runestone :: proc(
    rs: ^Runestone,
    allocator := context.allocator,
) -> (
    unknown_types: [dynamic]string,
) {
    unknown_types = make([dynamic]string, allocator)
    for &entry in rs.types.data {
        name, type := entry.key, &entry.value
        if b, b_ok := type.spec.(Builtin); b_ok && b == .Untyped {
            append_unknown_types(&unknown_types, name)
        }
        unknowns := check_for_unknown_types(type, rs.types)
        extend_unknown_types(&unknown_types, unknowns)
    }

    for &entry in rs.symbols.data {
        sym := &entry.value

        switch &value in sym.value {
        case Function:
            unknowns := check_for_unknown_types(&value.return_type, rs.types)
            extend_unknown_types(&unknown_types, unknowns)

            for &param in value.parameters {
                unknowns = check_for_unknown_types(&param.type, rs.types)
                extend_unknown_types(&unknown_types, unknowns)
            }
        case Type:
            unknowns := check_for_unknown_types(&value, rs.types)
            extend_unknown_types(&unknown_types, unknowns)
        }
    }

    for &entry in rs.externs.data {
        type := &entry.value

        unknowns := check_for_unknown_types(type, rs.externs)
        extend_unknown_types(&unknown_types, unknowns)
    }

    return
}

check_for_unknown_types_in_types :: proc(
    type: ^Type,
    types: om.OrderedMap(string, Type),
) -> (
    unknowns: [dynamic]string,
) {
    #partial switch &t in type.spec {
    case string:
        if found_type, ok := om.get(types, t); ok {
            if b, b_ok := found_type.spec.(Builtin); b_ok && b == .Untyped {
                type.spec = Unknown(t)
            }
        } else {
            append(&unknowns, t)
            type.spec = Unknown(t)
        }
    case Struct:
        for &member in t.members {
            u := check_for_unknown_types_in_types(&member.type, types)
            extend_unknown_types(&unknowns, u)
        }
    case Union:
        for &member in t.members {
            u := check_for_unknown_types_in_types(&member.type, types)
            extend_unknown_types(&unknowns, u)
        }
    case FunctionPointer:
        u := check_for_unknown_types_in_types(&t.return_type, types)
        extend_unknown_types(&unknowns, u)
        for &param in t.parameters {
            u = check_for_unknown_types_in_types(&param.type, types)
            extend_unknown_types(&unknowns, u)
        }
    }

    return
}

check_for_unknown_types_in_externs :: proc(
    type: ^Type,
    externs: om.OrderedMap(string, Extern),
) -> (
    unknowns: [dynamic]string,
) {
    #partial switch &t in type.spec {
    case string:
        if found_type, ok := om.get(externs, t); ok {
            if b, b_ok := found_type.spec.(Builtin); b_ok && b == .Untyped {
                type.spec = Unknown(t)
            } else {
                type.spec = ExternType(t)
            }
        } else {
            append(&unknowns, t)
            type.spec = Unknown(t)
        }
    case Struct:
        for &member in t.members {
            u := check_for_unknown_types_in_externs(&member.type, externs)
            extend_unknown_types(&unknowns, u)
        }
    case Union:
        for &member in t.members {
            u := check_for_unknown_types_in_externs(&member.type, externs)
            extend_unknown_types(&unknowns, u)
        }
    case FunctionPointer:
        u := check_for_unknown_types_in_externs(&t.return_type, externs)
        extend_unknown_types(&unknowns, u)
        for &param in t.parameters {
            u = check_for_unknown_types_in_externs(&param.type, externs)
            extend_unknown_types(&unknowns, u)
        }
    }

    return
}

check_for_unknown_types :: proc {
    check_for_unknown_types_in_runestone,
    check_for_unknown_types_in_types,
    check_for_unknown_types_in_externs,
}

extend_unknown_types :: #force_inline proc(
    unknown_types: ^[dynamic]string,
    unknowns: [dynamic]string,
) {
    for u in unknowns {
        if !slice.contains(unknown_types[:], u) {
            append(unknown_types, u)
        }
    }
    delete(unknowns)
}

recursively_extend_unknown_types :: proc(
    type_name: string,
    type: ^Type,
    rs: ^Runestone,
    unknown_types: ^[dynamic]string,
    allocator: runtime.Allocator,
    extern: []string = nil,
    source: Maybe(string) = nil,
    insert_type: bool = true,
) {
    is_extern :=
        extern != nil && source != nil && single_list_glob(extern, source.?)

    if is_extern {
        unknowns := check_for_unknown_types(type, rs.externs)
        extend_unknown_types(unknown_types, unknowns)

        if insert_type {
            om.insert(
                &rs.externs,
                type_name,
                Extern{source = source.?, type = type^},
            )
        }
    } else {
        unknowns := check_for_unknown_types(type, rs.types)
        extend_unknown_types(unknown_types, unknowns)

        if insert_type {
            om.insert(&rs.types, type_name, type^)
        }
    }
}

append_unknown_types :: #force_inline proc(
    unknown_types: ^[dynamic]string,
    unknown: string,
) {
    if !slice.contains(unknown_types[:], unknown) {
        append(unknown_types, unknown)
    }
}

validate_unknown_types_of_runestone :: proc(rs: ^Runestone) {
    // Check if the previously unknown types are now known
    // If so change the spec to a ExternType, because a type
    // can only be unknown if either does not exist or is included
    for &entry in rs.types.data {
        type := &entry.value
        validate_unknown_types(type, rs.types, rs.externs)
    }

    for &entry in rs.symbols.data {
        sym := &entry.value

        switch &value in sym.value {
        case Function:
            validate_unknown_types(&value.return_type, rs.types, rs.externs)

            for &param in value.parameters {
                validate_unknown_types(&param.type, rs.types, rs.externs)
            }
        case Type:
            validate_unknown_types(&value, rs.types, rs.externs)
        }
    }

    for &entry in rs.externs.data {
        extern := &entry.value
        validate_unknown_types(&extern.type, rs.types, rs.externs)
    }
}

validate_unknown_types_of_type :: proc(
    type: ^Type,
    types: om.OrderedMap(string, Type),
    externs: om.OrderedMap(string, Extern),
) {
    #partial switch &t in type.spec {
    case Unknown:
        if om.contains(types, string(t)) {
            type.spec = string(t)
        } else if om.contains(externs, string(t)) {
            type.spec = ExternType(t)
        }
    case Struct:
        for &member in t.members {
            validate_unknown_types(&member.type, types, externs)
        }
    case Union:
        for &member in t.members {
            validate_unknown_types(&member.type, types, externs)
        }
    case FunctionPointer:
        for &param in t.parameters {
            validate_unknown_types(&param.type, types, externs)
        }
        validate_unknown_types(&t.return_type, types, externs)
    }
}

validate_unknown_types :: proc {
    validate_unknown_types_of_runestone,
    validate_unknown_types_of_type,
}

@(private)
to_needs_to_process_type_names :: #force_inline proc(to: To) -> bool {
    return(
        len(to.trim_prefix.types) != 0 ||
        len(to.trim_suffix.types) != 0 ||
        len(to.add_prefix.types) != 0 ||
        len(to.add_suffix.types) != 0 ||
        to.trim_prefix.enum_type_name \
    )
}

@(private)
to_needs_to_process_extern_names :: #force_inline proc(to: To) -> bool {
    return(
        (to.extern.trim_prefix &&
            (len(to.trim_prefix.types) != 0 ||
                    to.trim_prefix.enum_type_name)) ||
        (to.extern.trim_suffix && len(to.trim_suffix.types) != 0) ||
        (to.extern.add_prefix && len(to.add_prefix.types) != 0) ||
        (to.extern.add_suffix && len(to.add_suffix.types) != 0) \
    )
}

@(private)
to_needs_to_process_extern_enum_entry_names :: #force_inline proc(
    to: To,
) -> bool {
    return(
        (to.extern.trim_prefix &&
            (len(to.trim_prefix.constants) != 0 ||
                    to.trim_prefix.enum_type_name)) ||
        (to.extern.trim_suffix && len(to.trim_suffix.constants) != 0) ||
        (to.extern.add_prefix && len(to.add_prefix.constants) != 0) ||
        (to.extern.add_suffix && len(to.add_suffix.constants) != 0) \
    )
}

@(private)
to_needs_to_process_variable_names :: #force_inline proc(to: To) -> bool {
    return(
        len(to.trim_prefix.variables) != 0 ||
        len(to.trim_suffix.variables) != 0 ||
        len(to.add_prefix.variables) != 0 ||
        len(to.add_suffix.variables) != 0 \
    )
}

@(private)
to_needs_to_process_function_names :: #force_inline proc(to: To) -> bool {
    return(
        len(to.trim_prefix.functions) != 0 ||
        len(to.trim_suffix.functions) != 0 ||
        len(to.add_prefix.functions) != 0 ||
        len(to.add_suffix.functions) != 0 \
    )
}

@(private)
to_needs_to_process_symbol_names :: #force_inline proc(to: To) -> bool {
    return(
        to_needs_to_process_variable_names(to) ||
        to_needs_to_process_function_names(to) \
    )
}

@(private)
to_needs_to_process_constant_names :: #force_inline proc(to: To) -> bool {
    return(
        len(to.trim_prefix.constants) != 0 ||
        len(to.trim_suffix.constants) != 0 ||
        len(to.add_prefix.constants) != 0 ||
        len(to.add_suffix.constants) != 0 \
    )
}
