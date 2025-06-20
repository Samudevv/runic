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

package cpp_codegen

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

@(private = "file")
Macro :: struct {
    def:    string,
    func:   bool,
    extern: bool,
}

@(private)
IncludedType :: struct {
    type:      union {
        clang.Type,
        runic.Type,
    },
    file_name: string,
    system:    bool,
}

@(private)
ParseContext :: struct {
    rune_file_name:    string,
    load_all_includes: bool,
    extern:            []string,
    main_file_name:    string,
    rs:                ^runic.Runestone,
    types:             ^om.OrderedMap(string, runic.Type),
    included_types:    ^map[string]IncludedType,
    included_anons:    ^om.OrderedMap(string, runic.Type),
    macros:            ^om.OrderedMap(string, Macro),
    int_sizes:         Int_Sizes,
    anon_index:        ^int,
    forward_decls:     ^[dynamic]string,
    allocator:         runtime.Allocator,
    err:               errors.Error,
}

generate_runestone :: proc(
    plat: runic.Platform,
    rune_file_name: string,
    rf: runic.From,
) -> (
    rs: runic.Runestone,
    err: errors.Error,
) {
    if !filepath.is_abs(rune_file_name) do return rs, errors.message("Internal Error: rune_file_name (\"{}\") needs to be absolute for cpp_codegen.generate_runestone", rune_file_name)

    rs_arena_alloc := runic.init_runestone(&rs)

    rs.platform = plat
    runic.set_library(plat, &rs, rf)

    disable_stdint_macros, dsm_ok := runic.platform_value_get(
        bool,
        rf.disable_stdint_macros,
        plat,
    )
    disable_stdint_macros = dsm_ok && disable_stdint_macros

    rune_defines, rd_ok := runic.platform_value_get(
        map[string]string,
        rf.defines,
        plat,
    )
    if !rd_ok do rune_defines = make(map[string]string, allocator = rs_arena_alloc)

    include_dirs, inc_ok := runic.platform_value_get(
        []string,
        rf.includedirs,
        plat,
    )
    if !inc_ok do include_dirs = make([]string, 0, rs_arena_alloc)

    // Generate system includes as empty files just for placeholders
    stdinc_gen_dir: Maybe(string)
    defer if gen_dir, ok := stdinc_gen_dir.?; ok {
        delete_system_includes(gen_dir)
    }

    enable_host_includes, hinc_ok := runic.platform_value_get(
        bool,
        rf.enable_host_includes,
        plat,
    )
    enable_host_includes = hinc_ok && enable_host_includes

    disable_system_include_gen, dsysinc_ok := runic.platform_value_get(
        bool,
        rf.disable_system_include_gen,
        plat,
    )
    disable_system_include_gen = dsysinc_ok && disable_system_include_gen

    flags, flag_ok := runic.platform_value_get([]cstring, rf.flags, plat)
    if !flag_ok do flags = make([]cstring, 0, rs_arena_alloc)

    if !enable_host_includes {
        if !disable_system_include_gen {
            stdinc_gen_dir_ok: bool = ---
            stdinc_gen_dir, stdinc_gen_dir_ok = system_includes_gen_dir(
                plat,
                rs_arena_alloc,
            )

            if stdinc_gen_dir_ok {
                if !generate_system_includes(stdinc_gen_dir.?) {
                    fmt.eprintfln(
                        "FATAL: failed to generate system includes for platform {}.{} into \"{}\"",
                        plat.os,
                        plat.arch,
                        stdinc_gen_dir,
                    )

                    stdinc_gen_dir = nil
                }
            } else {
                stdinc_gen_dir = nil
                fmt.eprintfln(
                    "FATAL: failed to create temporary directory for system includes for platform {}.{}",
                    plat.os,
                    plat.arch,
                )
            }
        }
    }

    clang_flags := generate_clang_flags(
        plat,
        disable_stdint_macros,
        rune_defines,
        include_dirs,
        enable_host_includes,
        stdinc_gen_dir,
        flags,
        rs_arena_alloc,
    )
    defer delete(clang_flags)

    headers := runic.platform_value_get([]string, rf.headers, plat)
    ignore := runic.platform_value_get(runic.IgnoreSet, rf.ignore, plat)

    included_types := make(map[string]IncludedType)
    defer delete(included_types)

    included_anons := om.make(string, runic.Type)
    defer om.delete(included_anons)

    macros := om.make(string, Macro)
    defer om.delete(macros)

    load_all_includes := runic.platform_value_get(
        bool,
        rf.load_all_includes,
        plat,
    )

    forward_decl_type := runic.platform_value_get(
        runic.Type,
        rf.forward_decl_type,
        plat,
    )

    // Add stdinc gen dir to externs
    extern := rf.extern
    if add_extern, ok := stdinc_gen_dir.?; ok {
        arr := system_includes_gen_extern(
            rf.extern,
            add_extern,
            rs_arena_alloc,
        )
        extern = arr[:]
    }

    anon_index: int
    forward_decls := make([dynamic]string)
    defer delete(forward_decls)

    ctx := ParseContext {
        rune_file_name    = rune_file_name,
        load_all_includes = load_all_includes,
        extern            = extern[:],
        rs                = &rs,
        types             = &rs.types,
        included_types    = &included_types,
        included_anons    = &included_anons,
        macros            = &macros,
        int_sizes         = int_sizes_from_platform(plat),
        anon_index        = &anon_index,
        forward_decls     = &forward_decls,
        allocator         = rs_arena_alloc,
    }
    context.user_ptr = &ctx

    index := clang.createIndex(0, 0)
    defer clang.disposeIndex(index)
    units := make(
        [dynamic]clang.TranslationUnit,
        len = len(headers),
        cap = len(headers),
    )
    defer delete(units)
    defer for unit in units {
        clang.disposeTranslationUnit(unit)
    }

    when ODIN_DEBUG {
        fmt.eprint("clang flags: ")
        for flag in clang_flags {
            fmt.eprintf("\"{}\" ", flag)
        }
        fmt.eprintln()
    }

    for header in headers {
        dealloc_me, os_stat := os.stat(header)
        #partial switch stat in os_stat {
        case os.General_Error:
            if stat == .Not_Exist {
                err = errors.message(
                    "failed to find header file: \"{}\"",
                    header,
                )
                return
            }
            err = errors.message(
                "failed to open header file \"{}\": {}",
                header,
                stat,
            )
            return
        case nil:
            os.file_info_delete(dealloc_me)
        case:
            err = errors.message(
                "failed to open header file \"{}\": {}",
                header,
                stat,
            )
            return
        }

        fmt.eprintfln("Parsing \"{}\" ...", header)

        header_cstr := strings.clone_to_cstring(header)

        unit := clang.parseTranslationUnit(
            index,
            header_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            .DetailedPreprocessingRecord | .SkipFunctionBodies,
        )
        delete(header_cstr)

        if unit == nil {
            err = errors.message(
                "\"{}\" failed to parse translation unit",
                header,
            )
            return
        }

        append(&units, unit)

        if print_diagnostics(os.stderr, unit) {
            fmt.eprintln(
                "Errors occurred. The resulting runestone can not be trusted! Make sure to fix the errors accordingly. If system includes can not be found you can check this page for help: https://github.com/Samudevv/runic/wiki#how-system-include-files-are-handled",
            )
        }

        cursor := clang.getTranslationUnitCursor(unit)

        rel_main_file_name, rel_main_ok := runic.absolute_to_file(
            rune_file_name,
            header,
            rs_arena_alloc,
        )
        ctx.main_file_name = rel_main_file_name if rel_main_ok else header

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.Cursor,
                client_data: clang.ClientData,
            ) -> clang.ChildVisitResult {
                context = runtime.default_context()
                context.user_ptr = client_data
                ctx := ps()

                cursor_location := clang.getCursorLocation(cursor)

                if !clang.Location_isFromMainFile(cursor_location) {
                    if !parse_cursor_not_from_main(cursor) do return .Continue
                }

                cursor_kind := clang.getCursorKind(cursor)

                #partial cursor_kind_switch: switch cursor_kind {
                case .TypedefDecl:
                    parse_typedef_decl(cursor)
                case .VarDecl:
                    parse_var_decl(cursor)
                case .StructDecl:
                    ctx.err = parse_struct_decl(cursor)
                case .UnionDecl:
                    ctx.err = parse_union_decl(cursor)
                case .EnumDecl:
                    ctx.err = parse_enum_decl(cursor)
                case .FunctionDecl:
                    parse_function_decl(cursor)
                case .MacroDefinition:
                    parse_macro_definition(cursor, false)
                case .MacroExpansion, .InclusionDirective:
                // Ignore
                case:
                    fmt.eprintln(
                        clang_source_error(
                            cursor,
                            fmt.aprintf(
                                "Other Cursor Type: {}\n\n\n",
                                cursor_kind,
                                allocator = errors.error_allocator,
                            ),
                        ),
                    )
                }

                if ctx.err != nil {
                    fmt.eprintln(ctx.err, "\n")
                    ctx.err = nil
                }

                return .Continue
            },
            &ctx,
        )

        if ctx.err != nil {
            err = ctx.err
            return
        }
    }

    make_forward_decls_into_actual_types(ctx.forward_decls^, forward_decl_type)

    runic.ignore_types(&rs.types, ignore)

    parse_unknowns(forward_decl_type, rf.extern)

    runic.ignore_types(&rs.types, ignore)

    // Remove all types that are they same inside of the externs
    // If a type is Untyped then the same type of the externs takes
    // precedence
    for entry in rs.externs.data {
        name := entry.key
        if om.contains(rs.types, name) {
            om.delete_key(&rs.types, name)
        }
    }

    // Handle Macros
    if om.length(macros) != 0 {
        macro_file_name: string = ---
        {
            macro_file: os.Handle = ---
            macro_file_err: errors.Error = ---
            macro_file, macro_file_name, macro_file_err = temp_file()
            if macro_file_err != nil {
                err = errors.message(
                    "failed to create macro file: {}",
                    macro_file_err,
                )
                return
            }
            defer os.close(macro_file)

            stringify_name, stringify2_name: strings.Builder
            strings.builder_init(&stringify_name)
            strings.builder_init(&stringify2_name)
            defer strings.builder_destroy(&stringify_name)
            defer strings.builder_destroy(&stringify2_name)

            strings.write_rune(&stringify_name, 'S')
            strings.write_string(&stringify2_name, "SS")

            for om.contains(macros, strings.to_string(stringify_name)) {
                strings.write_rune(&stringify_name, '_')
            }
            for om.contains(macros, strings.to_string(stringify2_name)) {
                strings.write_rune(&stringify2_name, '_')
            }

            fmt.fprintf(
                macro_file,
                `#define {}(X) #X
#define {}(X) {}(X)
`,
                strings.to_string(stringify2_name),
                strings.to_string(stringify_name),
                strings.to_string(stringify2_name),
            )

            for entry in macros.data {
                name, macro := entry.key, entry.value

                fmt.fprintfln(macro_file, "#define {} {}", name, macro.def)
            }

            first_macro_written := false
            for entry in macros.data {
                name, macro := entry.key, entry.value
                if macro.func || macro.extern || len(macro.def) == 0 do continue

                prefix_name := strings.concatenate({"R", name}, rs_arena_alloc)
                for om.contains(macros, prefix_name) {
                    prefix_name = strings.concatenate(
                        {"_", prefix_name},
                        rs_arena_alloc,
                    )
                }

                if first_macro_written {
                    os.write_rune(macro_file, ',')
                } else {
                    os.write_string(macro_file, "const char")
                }

                fmt.fprintf(
                    macro_file,
                    "*{}={}({})",
                    prefix_name,
                    strings.to_string(stringify_name),
                    name,
                )

                first_macro_written = true
            }

            os.write_rune(macro_file, ';')
        }

        defer delete(macro_file_name)
        defer os.remove(macro_file_name)

        macro_file_name_cstr := strings.clone_to_cstring(macro_file_name)

        macro_index := clang.createIndex(0, 0)
        defer clang.disposeIndex(macro_index)

        append(&clang_flags, "-xc")
        append(&clang_flags, "--std=c99")
        unit := clang.parseTranslationUnit(
            macro_index,
            macro_file_name_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            .SkipFunctionBodies | .SingleFileParse,
        )
        delete(macro_file_name_cstr)

        if unit == nil {
            err = errors.message("failed to parse macro file")
            return
        }
        defer clang.disposeTranslationUnit(unit)

        when ODIN_DEBUG {
            print_diagnostics(os.stderr, unit, "MACROS-FILE-")
        }

        cursor := clang.getTranslationUnitCursor(unit)

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.Cursor,
                client_data: clang.ClientData,
            ) -> clang.ChildVisitResult {
                context = runtime.default_context()
                context.user_ptr = client_data

                ctx := ps()

                cursor_kind := clang.getCursorKind(cursor)

                #partial switch cursor_kind {
                case .VarDecl:
                    var_name_clang := clang.getCursorSpelling(cursor)
                    var_name := clang_str(var_name_clang)
                    defer clang.disposeString(var_name_clang)

                    start: int = ---
                    for r, idx in var_name {
                        if r == 'R' {
                            start = idx
                            break
                        }
                    }
                    start += 1

                    var_name_str := strings.clone(
                        var_name[start:],
                        ctx.allocator,
                    )

                    om.insert(
                        &ctx.rs.constants,
                        var_name_str,
                        runic.Constant{},
                    )
                case .StringLiteral:
                    const_value_clang := clang.getCursorSpelling(cursor)
                    const_value := clang_str(const_value_clang)
                    defer clang.disposeString(const_value_clang)

                    const_value = const_value[1:len(const_value) - 1]

                    entry := &ctx.rs.constants.data[len(ctx.rs.constants.data) - 1]
                    const := &entry.value
                    const.type.spec = runic.Builtin.Untyped

                    if strings.has_prefix(const_value, "\\\"") &&
                       strings.has_suffix(const_value, "\\\"") {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_value, "\\\""),
                                "\\\"",
                            ),
                            ctx.allocator,
                        )
                        const.type.spec = runic.Builtin.String
                    } else if strings.has_prefix(const_value, "'") &&
                       strings.has_suffix(const_value, "'") &&
                       len(const_value) == 3 {
                        const.value = strings.clone(
                            strings.trim_prefix(
                                strings.trim_suffix(const_value, "'"),
                                "'",
                            ),
                            ctx.allocator,
                        )
                        const.type.spec = runic.Builtin.SInt8
                    } else if value_i64, ok_i64 := strconv.parse_i64(
                        const_value,
                    ); ok_i64 {
                        const.value = value_i64
                    } else if value_f64, ok_f64 := strconv.parse_f64(
                        const_value,
                    ); ok_f64 {
                        const.value = value_f64
                    } else {
                        name := entry.key

                        for &sym_entry in ctx.rs.symbols.data {
                            sym_name, sym := sym_entry.key, &sym_entry.value
                            if const_value == sym_name {
                                append(&sym.aliases, name)
                                om.delete_key(&ctx.rs.constants, name)
                                return .Recurse
                            }
                        }

                        for type_entry in ctx.rs.types.data {
                            type_name := type_entry.key

                            if const_value == type_name {
                                om.insert(
                                    &ctx.rs.types,
                                    name,
                                    runic.Type{spec = type_name},
                                )
                                om.delete_key(&ctx.rs.constants, name)
                                return .Recurse
                            }
                        }

                        const.value = strings.clone(const_value, ctx.allocator)
                    }
                }

                return .Recurse
            },
            &ctx,
        )
    }

    return
}

// return value of false means "do not continue" else "continue"
@(private)
parse_cursor_not_from_main :: proc(cursor: clang.Cursor) -> bool {
    ctx := ps()

    cursor_kind := clang.getCursorKind(cursor)
    cursor_type := clang.getCursorType(cursor)
    cursor_location := clang.getCursorLocation(cursor)
    cursor_display_name := clang.getCursorDisplayName(cursor)
    defer clang.disposeString(cursor_display_name)
    display_name := clang_str(cursor_display_name)

    file: clang.File = ---
    clang.getFileLocation(cursor_location, &file, nil, nil, nil)
    file_name_clang := clang.getFileName(file)
    defer clang.disposeString(file_name_clang)
    file_name_str := clang_str(file_name_clang)

    if len(file_name_str) == 0 {
        when ODIN_DEBUG {
            if cursor_kind != .MacroDefinition {
                fmt.eprintfln(
                    "debug: cursor_kind={} display_name=\"{}\" will be ignored because the file name is empty",
                    cursor_kind,
                    display_name,
                )
            }
        }

        // if cursor_kind != .MacroDefinition do break not_from_main_file
        // NOTE: flags that define macros (e.g. "-DFOO_STATIC") are also parsed. To make sure that they are ignored this is added
        return false
    }

    file_name: string

    repl_file_name, repl_file_name_alloc := strings.replace_all(
        file_name_str,
        "\\",
        "/",
    )
    defer if repl_file_name_alloc do delete(repl_file_name)

    rel_file_name, rel_ok := runic.absolute_to_file(
        ctx.rune_file_name,
        repl_file_name,
        ctx.allocator,
    )

    if rel_ok {
        file_name = rel_file_name
    } else {
        file_name = repl_file_name
    }

    load_as_main :=
        (file_name == ctx.main_file_name) ||
        (ctx.load_all_includes &&
                !runic.single_list_glob(ctx.extern, file_name))
    if load_as_main do return true

    #partial switch cursor_kind {
    case .TypedefDecl:
        typedef := clang.getTypedefDeclUnderlyingType(cursor)

        type_name_clang := clang.getTypedefName(cursor_type)
        type_name := strings.clone(clang_str(type_name_clang), ctx.allocator)
        clang.disposeString(type_name_clang)

        if !(type_name in ctx.included_types) {
            // TODO: handle pointers to function pointers
            if typedef.kind == .Pointer {
                pointee := clang.getPointeeType(typedef)
                if pointee.kind == .FunctionProto ||
                   pointee.kind == .FunctionNoProto {
                    ctx.types = ctx.included_anons
                    defer ctx.types = &ctx.rs.types

                    // TODO: handle forward declarations
                    type: runic.Type = ---
                    type, ctx.err = type_to_type(
                        typedef,
                        cursor,
                        nil,
                        type_name,
                    )
                    if ctx.err != nil {
                        // TODO: add file name and line, column to the error output
                        fmt.eprintfln(
                            "{}: failed to parse function pointer: {}",
                            type_name,
                            ctx.err,
                        )
                        ctx.err = nil
                        break
                    }

                    ctx.included_types[type_name] = IncludedType {
                        file_name = strings.clone(file_name, ctx.allocator),
                        type      = type,
                        system    = bool(
                            clang.Location_isInSystemHeader(cursor_location),
                        ),
                    }
                    break
                }
            }

            ctx.included_types[type_name] = IncludedType {
                file_name = strings.clone(file_name, ctx.allocator),
                type      = typedef,
                system    = bool(
                    clang.Location_isInSystemHeader(cursor_location),
                ),
            }
        }
    case .StructDecl:
        if struct_is_unnamed(display_name) do break
        display_name = strings.clone(display_name, ctx.allocator)

        // TODO: if a forward declaration is declared in one included file (included by header A), but the implementation is defined in a file included by header B. This leads to the forward declaration being added instead of the implementation, maybe changing included_types to a map of arrays and then add every declaration found could solve this.
        if !(display_name in ctx.included_types) {
            ctx.included_types[display_name] = IncludedType {
                file_name = strings.clone(file_name, ctx.allocator),
                type      = cursor_type,
                system    = bool(
                    clang.Location_isInSystemHeader(cursor_location),
                ),
            }
        }
    case .EnumDecl:
        if enum_is_unnamed(display_name) do break
        display_name = strings.clone(display_name, ctx.allocator)

        if !(display_name in ctx.included_types) {
            ctx.included_types[display_name] = IncludedType {
                file_name = strings.clone(file_name, ctx.allocator),
                type      = cursor_type,
                system    = bool(
                    clang.Location_isInSystemHeader(cursor_location),
                ),
            }
        }
    case .UnionDecl:
        if union_is_unnamed(display_name) do break
        display_name = strings.clone(display_name, ctx.allocator)

        if !(display_name in ctx.included_types) {
            ctx.included_types[display_name] = IncludedType {
                file_name = strings.clone(file_name, ctx.allocator),
                type      = cursor_type,
                system    = bool(
                    clang.Location_isInSystemHeader(cursor_location),
                ),
            }
        }
    case .MacroDefinition:
        parse_macro_definition(cursor, true)
    }

    return false
}

@(private)
parse_typedef_decl :: proc(cursor: clang.Cursor) {
    ctx := ps()

    cursor_type := clang.getCursorType(cursor)

    typedef := clang.getTypedefDeclUnderlyingType(cursor)

    type_name_clang := clang.getTypedefName(cursor_type)
    type_name := clang_str(type_name_clang)
    defer clang.disposeString(type_name_clang)

    if om.contains(ctx.types^, type_name) do return

    type_hint: Maybe(string)
    if typedef.kind == .Int {
        type_hint = clang_typedef_get_type_hint(cursor)
    }

    if typedef.kind == .Elaborated {
        named_type := clang.Type_getNamedType(typedef)
        named_cursor := clang.getTypeDeclaration(named_type)

        named_name_clang := clang.getCursorDisplayName(named_cursor)
        named_name := clang_str(named_name_clang)
        defer clang.disposeString(named_name_clang)

        if named_name == type_name do return
    }

    type: runic.Type = ---
    type, ctx.err = type_to_type(typedef, cursor, type_hint, type_name)
    if ctx.err != nil do return

    om.insert(ctx.types, strings.clone(type_name, ctx.allocator), type)
}

@(private)
parse_var_decl :: proc(cursor: clang.Cursor) {
    ctx := ps()

    storage_class := clang.Cursor_getStorageClass(cursor)
    cursor_display_name := clang.getCursorDisplayName(cursor)
    defer clang.disposeString(cursor_display_name)
    display_name := clang_str(cursor_display_name)
    cursor_type := clang.getCursorType(cursor)

    switch storage_class {
    case .Invalid, .Static, .OpenCLWorkGroupLocal, .PrivateExtern:
        return
    case .Auto, .None, .Register, .Extern:
    }

    if om.contains(ctx.rs.symbols, display_name) do return

    type_hint: Maybe(string)
    if cursor_type.kind == .Int {
        type_hint = clang_var_decl_get_type_hint(cursor)
    }

    type: runic.Type = ---
    type, ctx.err = type_to_type(cursor_type, cursor, type_hint, display_name)
    if ctx.err != nil do return

    var_name := strings.clone(display_name, ctx.allocator)

    if _, ok := type.spec.(runic.FunctionPointer); !ok {
        handle_anon_type(&type, var_name)
    }

    om.insert(&ctx.rs.symbols, var_name, runic.Symbol{value = type})
}

@(private)
parse_struct_decl :: proc(cursor: clang.Cursor) -> (err: errors.Error) {
    ctx := ps()

    cursor_display_name := clang.getCursorDisplayName(cursor)
    defer clang.disposeString(cursor_display_name)
    display_name := clang_str(cursor_display_name)

    if struct_is_unnamed(display_name) do return
    if om.contains(ctx.rs.types, display_name) do return

    cursor_type := clang.getCursorType(cursor)

    type := type_to_type(
        cursor_type,
        cursor,
        name_hint = display_name,
    ) or_return

    if spec, is_struct := type.spec.(runic.Struct);
       is_struct && len(spec.members) == 0 {
        append(ctx.forward_decls, strings.clone(display_name, ctx.allocator))
        return
    }

    om.insert(ctx.types, strings.clone(display_name, ctx.allocator), type)

    return
}

@(private)
parse_union_decl :: proc(cursor: clang.Cursor) -> (err: errors.Error) {
    ctx := ps()

    cursor_display_name := clang.getCursorDisplayName(cursor)
    defer clang.disposeString(cursor_display_name)
    display_name := clang_str(cursor_display_name)

    if union_is_unnamed(display_name) do return

    if om.contains(ctx.rs.types, display_name) do return

    cursor_type := clang.getCursorType(cursor)

    type := type_to_type(
        cursor_type,
        cursor,
        name_hint = display_name,
    ) or_return

    if spec, is_union := type.spec.(runic.Union);
       is_union && len(spec.members) == 0 {
        append(ctx.forward_decls, strings.clone(display_name, ctx.allocator))
        return
    }

    om.insert(ctx.types, strings.clone(display_name, ctx.allocator), type)

    return
}

@(private)
parse_enum_decl :: proc(cursor: clang.Cursor) -> (err: errors.Error) {
    ctx := ps()

    cursor_display_name := clang.getCursorDisplayName(cursor)
    defer clang.disposeString(cursor_display_name)
    display_name := clang_str(cursor_display_name)

    if enum_is_unnamed(display_name) do return

    if om.contains(ctx.rs.types, display_name) do return

    cursor_type := clang.getCursorType(cursor)

    type := type_to_type(
        cursor_type,
        cursor,
        name_hint = display_name,
    ) or_return

    om.insert(ctx.types, strings.clone(display_name, ctx.allocator), type)

    return
}

@(private)
parse_function_decl :: proc(cursor: clang.Cursor) {
    ctx := ps()

    storage_class := clang.Cursor_getStorageClass(cursor)

    // NOTE: defining structs, unions and enums with a name inside the parameter list is not supported
    switch storage_class {
    case .Invalid, .Static, .OpenCLWorkGroupLocal, .PrivateExtern:
        return
    case .Auto, .None, .Register, .Extern:
    }
    if clang.Cursor_isFunctionInlined(cursor) do return

    func_name_clang := clang.getCursorSpelling(cursor)
    func_name := clang_str(func_name_clang)
    defer clang.disposeString(func_name_clang)

    if om.contains(ctx.rs.symbols, func_name) do return

    cursor_return_type := clang.getCursorResultType(cursor)
    num_params := clang.Cursor_getNumArguments(cursor)

    func: runic.Function

    type_hint := clang_func_return_type_get_type_hint(cursor)

    return_type_name_hint := strings.concatenate({func_name, "_return_type"})
    defer delete(return_type_name_hint)

    func.return_type, ctx.err = type_to_type(
        cursor_return_type,
        cursor,
        type_hint,
        return_type_name_hint,
    )
    if ctx.err != nil do return

    handle_anon_type(&func.return_type, func_name)

    func.parameters = make(
        [dynamic]runic.Member,
        allocator = ctx.allocator,
        len = 0,
        cap = num_params,
    )
    func.variadic = bool(
        num_params != 0 &&
        clang.isFunctionTypeVariadic(clang.getCursorType(cursor)),
    )

    for idx in 0 ..< num_params {
        param_cursor := clang.Cursor_getArgument(cursor, u32(idx))
        param_type := clang.getCursorType(param_cursor)
        param_name_clang := clang.getCursorSpelling(param_cursor)
        param_name := clang_str(param_name_clang)

        defer clang.disposeString(param_name_clang)

        param_name_str: string = ---
        if len(param_name) == 0 {
            param_name_str = fmt.aprintf(
                "param{}",
                idx,
                allocator = ctx.allocator,
            )
        } else {
            param_name_str = strings.clone(param_name, ctx.allocator)
        }

        type_hint = nil
        if param_type.kind == .Int {
            type_hint = clang_var_decl_get_type_hint(param_cursor)
        }

        type: runic.Type = ---
        type, ctx.err = type_to_type(
            param_type,
            param_cursor,
            type_hint,
            param_name,
        )
        if ctx.err != nil do return

        handle_anon_type(&type, param_name_str)

        append(
            &func.parameters,
            runic.Member{name = param_name_str, type = type},
        )
    }

    if len(func.parameters) != 0 {
        has_va_list: bool

        #partial switch spec in
            func.parameters[len(func.parameters) - 1].type.spec {
        case string:
            if spec == "va_list" do has_va_list = true
        case runic.Unknown:
            if spec == "va_list" do has_va_list = true
        }

        if has_va_list {
            pop(&func.parameters)
            func.variadic = true
        }
    }

    om.insert(
        &ctx.rs.symbols,
        strings.clone(func_name, ctx.allocator),
        runic.Symbol{value = func},
    )
}

@(private)
parse_macro_definition :: proc(cursor: clang.Cursor, not_from_main: bool) {
    ctx := ps()

    cursor_extent := clang.getCursorExtent(cursor)
    cursor_start := clang.getRangeStart(cursor_extent)
    cursor_end := clang.getRangeEnd(cursor_extent)

    start_offset, end_offset: u32 = ---, ---
    file: clang.File = ---
    clang.getSpellingLocation(cursor_start, &file, nil, nil, &start_offset)
    clang.getSpellingLocation(cursor_end, nil, nil, nil, &end_offset)

    unit := clang.Cursor_getTranslationUnit(cursor)

    buffer_size: u64 = ---
    buf := clang.getFileContents(unit, file, &buffer_size)
    buffer := strings.string_from_ptr(cast(^byte)buf, int(buffer_size))

    macro_def := buffer[start_offset:end_offset]
    macro_name_end: int = len(macro_def)
    open_parens: int
    macro_def_loop: for r, idx in macro_def {
        switch r {
        case '(':
            open_parens += 1
        case ')':
            open_parens -= 1
            if open_parens == 0 {
                macro_name_end = idx
                break macro_def_loop
            }
        case:
            if open_parens == 0 && unicode.is_space(r) {
                macro_name_end = idx
                break macro_def_loop
            }
        }
    }

    macro_name := strings.clone(macro_def[:macro_name_end], ctx.allocator)

    macro_value: string
    if macro_name_end != len(macro_def) {
        macro_value = strings.clone(
            strings.trim_space(macro_def[macro_name_end:]),
            ctx.allocator,
        )
    }

    om.insert(
        ctx.macros,
        macro_name,
        Macro {
            def = macro_value,
            func = bool(clang.Cursor_isMacroFunctionLike(cursor)),
            extern = not_from_main,
        },
    )

    return
}

@(private)
parse_unknowns :: proc(forward_decl_type: runic.Type, extern: []string) {
    ctx := ps()

    // Look for unknown types
    unknown_types := runic.check_for_unknown_types(ctx.rs)
    defer delete(unknown_types)

    // Try to find the unknown types in the includes
    unknown_anons := om.make(string, runic.Type)
    unknown_forward_decls := make([dynamic]string)
    for unknown in unknown_types {
        if included_type_value, ok := ctx.included_types[unknown]; ok {
            type: runic.Type = ---
            switch &included_type in included_type_value.type {
            case clang.Type:
                cursor := clang.getTypeDeclaration(included_type)

                if included_type.kind == .Elaborated {
                    named_type := clang.Type_getNamedType(included_type)
                    named_cursor := clang.getTypeDeclaration(named_type)
                    named_name_clang := clang.getCursorDisplayName(
                        named_cursor,
                    )
                    named_name := clang_str(named_name_clang)
                    defer clang.disposeString(named_name_clang)

                    if named_name == unknown {
                        file: clang.File = ---
                        named_location := clang.getCursorLocation(named_cursor)
                        clang.getFileLocation(
                            named_location,
                            &file,
                            nil,
                            nil,
                            nil,
                        )
                        file_name_clang := clang.getFileName(file)
                        defer clang.disposeString(file_name_clang)
                        file_name := clang_str(file_name_clang)

                        included_type = named_type
                        included_type_value.file_name = strings.clone(
                            file_name,
                            ctx.allocator,
                        )
                        cursor = named_cursor
                    }
                }

                forward_decls := ctx.forward_decls
                ctx.types = &unknown_anons
                ctx.forward_decls = &unknown_forward_decls
                defer ctx.types = &ctx.rs.types
                defer ctx.forward_decls = forward_decls

                type, ctx.err = type_to_type(
                    included_type,
                    cursor,
                    name_hint = unknown,
                )

                #partial switch spec in type.spec {
                case runic.Struct:
                    if len(spec.members) == 0 {
                        append(&unknown_forward_decls, unknown)
                        type = {
                            spec = runic.Builtin.RawPtr,
                        }
                    }
                case runic.Union:
                    if len(spec.members) == 0 {
                        append(&unknown_forward_decls, unknown)
                        type = {
                            spec = runic.Builtin.RawPtr,
                        }
                    }
                }
            case runic.Type:
                type = included_type

                deps := runic.compute_dependencies(type)
                defer delete(deps)

                for dep in deps {
                    if anon, a_ok := om.get(ctx.included_anons^, dep); a_ok {
                        om.insert(&unknown_anons, dep, anon)
                    }
                }
            }

            make_forward_decls_into_actual_types(
                unknown_forward_decls,
                forward_decl_type,
                included_type_value.file_name,
            )

            delete(unknown_forward_decls)
            unknown_forward_decls = make([dynamic]string)

            for &entry in unknown_anons.data {
                anon_name, t := entry.key, &entry.value

                // Adds unknowns of t to unknown_types (if there are any) and inserts t into either types or externs
                runic.recursively_extend_unknown_types(
                    anon_name,
                    t,
                    ctx.rs,
                    &unknown_types,
                    ctx.allocator,
                    extern,
                    included_type_value.file_name,
                )
            }
            om.delete(unknown_anons)
            unknown_anons = om.make(string, runic.Type)

            if ctx.err != nil {
                fmt.eprintln(ctx.err, "\n")
                ctx.err = nil
                continue
            }

            // Adds unknowns of type to unknown_types (if there are any) and inserts type into either types or externs
            runic.recursively_extend_unknown_types(
                unknown,
                &type,
                ctx.rs,
                &unknown_types,
                ctx.allocator,
                extern,
                included_type_value.file_name,
            )
        } else {
            // If the type is #Untyped then it technically exists and we don't need to notify the user about it
            if !(om.contains(ctx.rs.types, unknown) ||
                   om.contains(ctx.rs.externs, unknown)) {
                fmt.eprintfln(
                    "Unknown type \"{}\" has not been found in the includes",
                    unknown,
                )
            }
        }
    }

    om.delete(unknown_anons)
}
