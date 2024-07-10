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
// import "core:encoding/json"
import "core:io"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "root:errors"
import "shared:yaml"

Rune :: struct {
    version: uint,
    from:    union {
        From,
        string,
        [dynamic]string,
    },
    to:      union {
        To,
        string,
    },
    arena:   runtime.Arena,
}

From :: struct {
    // General
    language:    string,
    static:      PlatformValue(string),
    shared:      PlatformValue(string),
    ignore:      PlatformValue(IgnoreSet),
    overwrite:   PlatformValue(OverwriteSet),
    // C
    headers:     PlatformValue([]string),
    includedirs: PlatformValue([]string),
    defines:     PlatformValue(map[string]string),
    // Odin
    packages:    PlatformValue([]string),
}

To :: struct {
    language:      string,
    // General
    static_switch: string,
    out:           string,
    trim_prefix:   TrimSet,
    trim_suffix:   TrimSet,
    add_prefix:    AddSet,
    add_suffix:    AddSet,
    ignore_arch:   bool,
    // Odin
    package_name:  string `json:"package"`,
    detect:        OdinDetect,
    no_build_tag:  bool,
    use_when_else: bool,
}

TrimSet :: struct {
    functions: yaml.Value,
    variables: yaml.Value,
    types:     yaml.Value,
    constants: yaml.Value,
}

AddSet :: struct {
    functions: string,
    variables: string,
    types:     string,
    constants: string,
}

IgnoreSet :: struct {
    macros:    yaml.Value,
    functions: yaml.Value,
    variables: yaml.Value,
    types:     yaml.Value,
}

OverwriteSet :: struct {
    constants: map[string]string,
    functions: map[string]string,
    variables: map[string]string,
    types:     map[string]string,
}

OdinDetect :: struct {
    multi_pointer: string,
}


SingleList :: union {
    string,
    [dynamic]string,
}

PlatformValue :: struct(T: typeid) {
    d: map[Platform]T,
}

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


        #partial switch from in y["from"] {
        case yaml.Mapping:
            f: From

            f.static.d = make(map[Platform]string, allocator = rn_arena_alloc)
            f.shared.d = make(map[Platform]string, allocator = rn_arena_alloc)
            f.ignore.d = make(
                map[Platform]IgnoreSet,
                allocator = rn_arena_alloc,
            )
            f.overwrite.d = make(
                map[Platform]OverwriteSet,
                allocator = rn_arena_alloc,
            )
            f.headers.d = make(
                map[Platform][]string,
                allocator = rn_arena_alloc,
            )
            f.includedirs.d = make(
                map[Platform][]string,
                allocator = rn_arena_alloc,
            )
            f.defines.d = make(
                map[Platform]map[string]string,
                allocator = rn_arena_alloc,
            )
            f.packages.d = make(
                map[Platform][]string,
                allocator = rn_arena_alloc,
            )

            errors.assert(
                "language" in from,
                "\"from.language\" is missing",
            ) or_return

            for key, value in from {
                splits, alloc_err := strings.split(key, ".")
                errors.wrap(alloc_err) or_return

                name: string = ---
                os, arch: Maybe(string)

                if len(splits) == 0 {
                    err = errors.message("invalid key in \"from\"")
                    return
                } else if len(splits) == 1 {
                    #no_bounds_check name = splits[0]
                } else if len(splits) == 2 {
                    #no_bounds_check name = splits[0]
                    #no_bounds_check os = splits[1]
                } else if len(splits) == 3 {
                    #no_bounds_check name = splits[0]
                    #no_bounds_check os = splits[1]
                    #no_bounds_check arch = splits[2]
                } else {
                    err = errors.message("invalid key in \"from\": {}", key)
                    return
                }

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
                    #partial switch v in value {
                    case string:
                        i_set.macros = v
                        i_set.functions = v
                        i_set.variables = v
                        i_set.types = v
                    case yaml.Sequence:
                        i_set.macros = v
                        i_set.functions = v
                        i_set.variables = v
                        i_set.types = v
                    case yaml.Mapping:
                        i_set.macros = v["macros"]
                        i_set.functions = v["functions"]
                        i_set.variables = v["variables"]
                        i_set.types = v["types"]
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
                        map[string]string,
                        allocator = rn_arena_alloc,
                    )
                    o_set.functions = make(
                        map[string]string,
                        allocator = rn_arena_alloc,
                    )
                    o_set.variables = make(
                        map[string]string,
                        allocator = rn_arena_alloc,
                    )
                    o_set.types = make(
                        map[string]string,
                        allocator = rn_arena_alloc,
                    )

                    #partial switch v in value {
                    case yaml.Mapping:
                        if "constants" in v {
                            #partial switch con in v["constants"] {
                            case yaml.Mapping:
                                for con_key, con_value in con {
                                    #partial switch con_v in con_value {
                                    case string:
                                        o_set.constants[con_key] = con_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.constants.{}\" has invalid type %T",
                                            key,
                                            con_key,
                                            con_v,
                                        )
                                        return
                                    }
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

                        if "functions" in v {
                            #partial switch fun in v["functions"] {
                            case yaml.Mapping:
                                for fun_key, fun_value in fun {
                                    #partial switch fun_v in fun_value {
                                    case string:
                                        o_set.functions[fun_key] = fun_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.functions.{}\" has invalid type %T",
                                            key,
                                            fun_key,
                                            fun_v,
                                        )
                                        return
                                    }
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

                        if "variables" in v {
                            #partial switch var in v["variables"] {
                            case yaml.Mapping:
                                for var_key, var_value in var {
                                    #partial switch var_v in var_value {
                                    case string:
                                        o_set.variables[var_key] = var_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.variables.{}\" has invalid type %T",
                                            key,
                                            var_key,
                                            var_v,
                                        )
                                        return
                                    }
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
                                    #partial switch typ_v in typ_value {
                                    case string:
                                        o_set.types[typ_key] = typ_v
                                    case:
                                        err = errors.message(
                                            "\"from.{}.types.{}\" has invalid type %T",
                                            key,
                                            typ_key,
                                            typ_v,
                                        )
                                        return
                                    }
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
                    d_map := make(
                        map[string]string,
                        allocator = rn_arena_alloc,
                    )

                    #partial switch v in value {
                    case yaml.Mapping:
                        for d_key, d_value in v {
                            // TODO: convert i64 and f64 to string
                            #partial switch d_v in d_value {
                            case string:
                                d_map[d_key] = d_v
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
                    case:
                        err = errors.message(
                            "\"from.{}\" has invalid type %T",
                            key,
                            v,
                        )
                        return
                    }

                    f.defines.d[plat] = d_map
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
        case string:
            if from != "stdin" {
                rn.from = relative_to_file(file_path, from, rn_arena_alloc)
            } else {
                rn.from = from
            }
        case yaml.Sequence:
            f := make([dynamic]string, rn_arena_alloc)

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

            #partial switch trim_prefix in to["trim_prefix"] {
            case string:
                t.trim_prefix.functions = trim_prefix
                t.trim_prefix.variables = trim_prefix
                t.trim_prefix.types = trim_prefix
                t.trim_prefix.constants = trim_prefix
            case yaml.Sequence:
                t.trim_prefix.functions = trim_prefix
                t.trim_prefix.variables = trim_prefix
                t.trim_prefix.types = trim_prefix
                t.trim_prefix.constants = trim_prefix
            case yaml.Mapping:
                t.trim_prefix.functions = trim_prefix["functions"]
                t.trim_prefix.variables = trim_prefix["variables"]
                t.trim_prefix.types = trim_prefix["types"]
                t.trim_prefix.constants = trim_prefix["constants"]
            case:
                err = errors.message(
                    "\"to.trim_prefix\" has invalid type %T",
                    trim_prefix,
                )
                return
            }

            #partial switch trim_suffix in to["trim_suffix"] {
            case string:
                t.trim_suffix.functions = trim_suffix
                t.trim_suffix.variables = trim_suffix
                t.trim_suffix.types = trim_suffix
                t.trim_suffix.constants = trim_suffix
            case yaml.Sequence:
                t.trim_suffix.functions = trim_suffix
                t.trim_suffix.variables = trim_suffix
                t.trim_suffix.types = trim_suffix
                t.trim_suffix.constants = trim_suffix
            case yaml.Mapping:
                t.trim_suffix.functions = trim_suffix["functions"]
                t.trim_suffix.variables = trim_suffix["variables"]
                t.trim_suffix.types = trim_suffix["types"]
                t.trim_suffix.constants = trim_suffix["constants"]
            case:
                err = errors.message(
                    "\"to.trim_suffix\" has invalid type %T",
                    trim_suffix,
                )
                return
            }

            #partial switch add_prfx in to["add_prefix"] {
            case string:
                t.add_prefix.functions = add_prfx
                t.add_prefix.variables = add_prfx
                t.add_prefix.types = add_prfx
                t.add_prefix.constants = add_prfx
            case yaml.Mapping:
                ok: bool = ---
                if "functions" in add_prfx {
                    t.add_prefix.functions, ok = add_prfx["functions"].(string)
                    errors.wrap(
                        ok,
                        "\"to.add_prefix.functions\" has invalid type",
                    ) or_return
                }

                if "variables" in add_prfx {
                    t.add_prefix.variables, ok = add_prfx["variables"].(string)
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
                    t.add_prefix.constants, ok = add_prfx["constants"].(string)
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

            #partial switch add_sfx in to["add_suffix"] {
            case string:
                t.add_suffix.functions = add_sfx
                t.add_suffix.variables = add_sfx
                t.add_suffix.types = add_sfx
                t.add_suffix.constants = add_sfx
            case yaml.Mapping:
                ok: bool = ---
                if "functions" in add_sfx {
                    t.add_suffix.functions, ok = add_sfx["functions"].(string)
                    errors.wrap(
                        ok,
                        "\"to.add_suffix.functions\" has invalid type",
                    ) or_return
                }

                if "variables" in add_sfx {
                    t.add_suffix.variables, ok = add_sfx["variables"].(string)
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
                    t.add_suffix.constants, ok = add_sfx["constants"].(string)
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

                        if len(t.detect.multi_pointer) == 0 {
                            t.detect.multi_pointer = "auto"
                        }
                    }
                case:
                    err = errors.message(
                        "\"to.detect\" has invalid type %T",
                        d,
                    )
                    return
                }
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

    return
}

/*parse_rune_json :: proc(
    rd: io.Reader,
    file_path: string,
) -> (
    rn: Rune,
    err: union {
        io.Error,
        json.Unmarshal_Error,
    },
) {
    rn_arena_alloc := runtime.arena_allocator(&rn.arena)

    buf: bytes.Buffer
    bytes.buffer_init_allocator(&buf, 0, 0)
    defer bytes.buffer_destroy(&buf)

    io.copy(bytes.buffer_to_stream(&buf), rd) or_return

    data := bytes.buffer_to_bytes(&buf)

    json.unmarshal(data, &rn, allocator = rn_arena_alloc) or_return

    switch &to in rn.to {
    case To:
        to.trim_prefix = trim_to_trim_set(to.trim_prefix)
        to.trim_suffix = trim_to_trim_set(to.trim_suffix)
        to.add_prefix = add_to_add_set(to.add_prefix)
        to.add_suffix = add_to_add_set(to.add_suffix)

        if to.detect.multi_pointer == "" {
            to.detect.multi_pointer = "auto"
        }
    case string:
        if to != "stdout" {
            to = relative_to_file(file_path, to, rn_arena_alloc)
        }
    }

    switch &from in rn.from {
    case From:
        from.static = relative_to_file(
            file_path,
            from.static,
            rn_arena_alloc,
            true,
        )
        from.static_linux = relative_to_file(
            file_path,
            from.static_linux,
            rn_arena_alloc,
            true,
        )
        from.static_linux_x86_64 = relative_to_file(
            file_path,
            from.static_linux_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_linux_arm64 = relative_to_file(
            file_path,
            from.static_linux_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_windows = relative_to_file(
            file_path,
            from.static_windows,
            rn_arena_alloc,
            true,
        )
        from.static_windows_x86_64 = relative_to_file(
            file_path,
            from.static_windows_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_windows_arm64 = relative_to_file(
            file_path,
            from.static_windows_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_macos = relative_to_file(
            file_path,
            from.static_macos,
            rn_arena_alloc,
            true,
        )
        from.static_macos_x86_64 = relative_to_file(
            file_path,
            from.static_macos_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_macos_arm64 = relative_to_file(
            file_path,
            from.static_macos_arm64,
            rn_arena_alloc,
            true,
        )
        from.static_bsd = relative_to_file(
            file_path,
            from.static_bsd,
            rn_arena_alloc,
            true,
        )
        from.static_bsd_x86_64 = relative_to_file(
            file_path,
            from.static_bsd_x86_64,
            rn_arena_alloc,
            true,
        )
        from.static_bsd_arm64 = relative_to_file(
            file_path,
            from.static_bsd_arm64,
            rn_arena_alloc,
            true,
        )

        from.shared = relative_to_file(
            file_path,
            from.shared,
            rn_arena_alloc,
            true,
        )
        from.shared_linux = relative_to_file(
            file_path,
            from.shared_linux,
            rn_arena_alloc,
            true,
        )
        from.shared_linux_x86_64 = relative_to_file(
            file_path,
            from.shared_linux_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_linux_arm64 = relative_to_file(
            file_path,
            from.shared_linux_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_windows = relative_to_file(
            file_path,
            from.shared_windows,
            rn_arena_alloc,
            true,
        )
        from.shared_windows_x86_64 = relative_to_file(
            file_path,
            from.shared_windows_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_windows_arm64 = relative_to_file(
            file_path,
            from.shared_windows_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_macos = relative_to_file(
            file_path,
            from.shared_macos,
            rn_arena_alloc,
            true,
        )
        from.shared_macos_x86_64 = relative_to_file(
            file_path,
            from.shared_macos_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_macos_arm64 = relative_to_file(
            file_path,
            from.shared_macos_arm64,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd = relative_to_file(
            file_path,
            from.shared_bsd,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd_x86_64 = relative_to_file(
            file_path,
            from.shared_bsd_x86_64,
            rn_arena_alloc,
            true,
        )
        from.shared_bsd_arm64 = relative_to_file(
            file_path,
            from.shared_bsd_arm64,
            rn_arena_alloc,
            true,
        )

        // TODO: for all platforms
        for &path in from.includedirs {
            path = relative_to_file(file_path, path, rn_arena_alloc)
        }

    case string:
        if from != "stdin" {
            from = relative_to_file(file_path, from, rn_arena_alloc)
        }
    case [dynamic]string:
        for &path in from {
            path = relative_to_file(file_path, path, rn_arena_alloc)
        }
    }

    return
}*/

rune_destroy :: proc(rn: ^Rune) {
    runtime.arena_destroy(&rn.arena)
}

@(private = "file")
single_list_trim_prefix :: #force_inline proc(
    ident: string,
    list: yaml.Value,
) -> string {
    #partial switch l in list {
    case string:
        return strings.trim_prefix(ident, l)
    case yaml.Sequence:
        str := ident
        for v in l {
            #partial switch x in v {
            case string:
                str = strings.trim_prefix(str, x)
            }
        }
        return str
    }

    return ident
}

@(private = "file")
single_list_trim_suffix :: #force_inline proc(
    ident: string,
    list: yaml.Value,
) -> string {
    #partial switch l in list {
    case string:
        return strings.trim_suffix(ident, l)
    case yaml.Sequence:
        str := ident
        for v in l {
            #partial switch x in v {
            case string:
                str = strings.trim_suffix(str, x)
            }
        }
    }

    return ident
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
        if idx == 0 {
            switch r {
            case '0' ..= '9':
                return false
            }
        }

        switch r {
        case 0 ..= '/', ':' ..= '@', '[' ..= '`', '{' ..= 127:
            return false
        }

        break
    }


    return true
}

@(private = "file")
process_identifier :: #force_inline proc(
    ident: string,
    trim_prefix, trim_suffix: yaml.Value,
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
) -> string {
    return process_identifier(
        ident,
        rn.trim_prefix.types,
        rn.trim_suffix.types,
        rn.add_prefix.types,
        rn.add_suffix.types,
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

single_list_contains :: proc(list: SingleList, value: string) -> bool {
    switch l in list {
    case string:
        return value == l
    case [dynamic]string:
        return slice.contains(l[:], value)
    }

    return false
}

single_list_glob :: proc(list: SingleList, value: string) -> bool {
    switch l in list {
    case string:
        ok, _ := filepath.match(l, value)
        return ok
    case [dynamic]string:
        for p in l {
            ok, _ := filepath.match(p, value)
            if ok do return true
        }
    }

    return false
}

contains :: proc {
    single_list_contains,
}

overwrite_type :: proc(
    ow: OverwriteSet,
    name: string,
) -> (
    value: Maybe(Type),
    err: errors.Error,
) {
    if value_str, ok := ow.types[name]; ok {
        return parse_type(value_str)
    }
    return
}

overwrite_func :: proc(
    ow: OverwriteSet,
    name: string,
) -> (
    value: Maybe(Function),
    err: errors.Error,
) {
    if value_str, ok := ow.functions[name]; ok {
        return parse_func(value_str)
    }
    return
}

overwrite_constant :: proc(
    ow: OverwriteSet,
    name: string,
) -> (
    value: Maybe(Constant),
    err: errors.Error,
) {
    if value_str, ok := ow.constants[name]; ok {
        return parse_constant(value_str)
    }
    return
}

overwrite_var :: overwrite_type
