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
import ctz "core:c/frontend/tokenizer"
import "core:fmt"
import "core:io"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "root:errors"
import "root:ini"
import om "root:ordered_map"

parse_runestone :: proc(
    in_stm: io.Reader,
    file_path: string,
) -> (
    rs: Runestone,
    err: errors.Error,
) {
    context.allocator = runtime.arena_allocator(&rs.arena)

    def_alloc := runtime.default_allocator()
    temp_arena: runtime.Arena
    errors.wrap(runtime.arena_init(&temp_arena, 0, def_alloc)) or_return
    defer runtime.arena_destroy(&temp_arena)

    arena_alloc := runtime.arena_allocator(&temp_arena)

    ini_file := ini.parse(in_stm, file_path) or_return

    using rs

    global: {
        sect, ok := ini_file[""]
        errors.wrap(ok) or_return
        defer delete_key(&ini_file, "")

        version_str, ok1 := om.get(sect, "version")
        errors.wrap(ok1) or_return

        version, ok = strconv.parse_uint(version_str, 10)
        errors.wrap(ok) or_return

        os_str, ok2 := om.get(sect, "os")
        errors.wrap(ok2) or_return

        switch platform.os {
        case .Linux, .Windows, .Macos, .BSD, .Any:
        // Just a reminder to update this when platforms change
        }
        switch os_str {
        case "Linux":
            platform.os = .Linux
        case "Windows":
            platform.os = .Windows
        case "Macos":
            platform.os = .Macos
        case "BSD":
            platform.os = .BSD
        case "Any":
            err = errors.message("a runestone can not have any os")
            return
        case:
            err = errors.message("invalid os \"{}\"", os_str)
            return
        }

        arch_str, ok3 := om.get(sect, "arch")
        errors.wrap(ok3) or_return

        switch platform.arch {
        case .x86_64, .arm64, .Any, .x86, .arm32:
        // Just a reminder to update this when platforms change
        }
        switch arch_str {
        case "x86_64":
            platform.arch = .x86_64
        case "arm64":
            platform.arch = .arm64
        case "x86":
            platform.arch = .x86
        case "arm32":
            platform.arch = .arm32
        case "Any":
            err = errors.message("a runestone can not have any architecture")
            return
        case:
            err = errors.message("invalid arch \"{}\"", arch_str)
            return
        }
    }

    lib_section: {
        sect, ok := ini_file["lib"]
        errors.wrap(ok) or_return
        defer delete_key(&ini_file, "lib")

        shared, shared_ok := om.get(sect, "shared")
        static, static_ok := om.get(sect, "static")

        if shared_ok && len(shared) != 0 {
            lib.shared = relative_to_file(file_path, shared, needs_dir = true)
        }
        if static_ok && len(static) != 0 {
            lib.static = relative_to_file(file_path, static, needs_dir = true)
        }

        errors.assert(
            lib.shared != nil || lib.static != nil,
            "No libraries have been specified",
        ) or_return
    }

    symbols_section: {
        sect, ok := ini_file["symbols"]
        errors.wrap(ok, "no symbols") or_return
        defer delete_key(&ini_file, "symbols")

        symbols = om.make(string, Symbol)

        for value in sect.data {
            name, def := value.key, value.value
            symbol_type: string = ---
            symbol_name: string = ---

            arr, alloc_err := strings.split(name, ".", arena_alloc)
            errors.wrap(alloc_err) or_return

            if len(arr) != 2 do return rs, errors.message("\"{}\" none or too much dots in symbol name. a symbol needs the pattern var.name or func.name", name)

            symbol_type = arr[0]
            symbol_name = arr[1]

            switch symbol_type {
            case "func":
                func := parse_func(def) or_return

                om.insert(&symbols, symbol_name, Symbol{value = func})
            case "var":
                var := parse_type(def) or_return

                om.insert(&symbols, symbol_name, Symbol{value = var})
            case:
                err = errors.message("invalid symbol type {}", symbol_type)
                return
            }
        }
    }

    remap: {
        sect, ok := ini_file["remap"]
        if !ok do break remap
        defer delete_key(&ini_file, "remap")

        for value in sect.data {
            remap_name, symbol_name := value.key, value.value
            symbol, sym_ok := om.get(symbols, symbol_name)
            errors.wrap(sym_ok) or_return

            if symbol.remap != nil do return rs, errors.message("remap has already been set for {}", symbol_name)

            symbol.remap = symbol_name
            om.replace(&symbols, symbol_name, remap_name, symbol)
        }
    }

    alias: {
        sect, ok := ini_file["alias"]
        if !ok do break alias
        defer delete_key(&ini_file, "alias")

        for value in sect.data {
            alias_name, symbol_name := value.key, value.value
            symbol, sym_ok := om.get(symbols, symbol_name)
            errors.wrap(sym_ok) or_return

            append(&symbol.aliases, alias_name)
            om.insert(&symbols, symbol_name, symbol)
        }
    }

    extern_section: {
        sect, ok := ini_file["extern"]
        if !ok do break extern_section
        defer delete_key(&ini_file, "extern")

        rs.externs = om.make(string, Extern)

        for value in sect.data {
            type_name, extern_value := value.key, value.value

            str_idx := strings.index(extern_value, "\"")
            EXTERN_SOURCE_MISSING :: "\"extern\" entries require a string specifying the source at the front"
            errors.assert(str_idx != -1, EXTERN_SOURCE_MISSING) or_return

            source_start := str_idx + 1
            // TODO: handle strings containg '"' character
            str_idx = strings.index(extern_value[source_start:], "\"")
            errors.assert(str_idx != -1, EXTERN_SOURCE_MISSING) or_return
            str_idx += source_start

            source_end := str_idx
            source_string := extern_value[source_start:source_end]

            extern_type := parse_type(extern_value[str_idx + 1:]) or_return

            om.insert(
                &rs.externs,
                type_name,
                Extern{type = extern_type, source = source_string},
            )
        }
    }

    types: {
        sect, ok := ini_file["types"]
        if !ok do break types
        defer delete_key(&ini_file, "types")

        rs.types = om.make(string, Type)

        for value in sect.data {
            type_name, type_def := value.key, value.value
            type := parse_type(type_def) or_return
            om.insert(&rs.types, type_name, type)
        }
    }

    methods: {
        sect, ok := ini_file["methods"]
        if !ok do break methods
        defer delete_key(&ini_file, "methods")

        for value in sect.data {
            method_def, symbol_name := value.key, value.value
            method_caller: string = ---
            method_name: string = ---
            arr, alloc_err := strings.split(method_def, ".", arena_alloc)
            errors.wrap(alloc_err) or_return
            errors.wrap(len(arr) == 2) or_return

            method_caller = arr[0]
            method_name = arr[1]

            symbol, sym_ok := om.get(symbols, symbol_name)
            errors.wrap(sym_ok) or_return

            func, ok1 := symbol.value.(Function)
            errors.wrap(ok1) or_return

            errors.wrap(func.method_info == nil) or_return

            func.method_info = MethodInfo {
                type = method_caller,
                name = method_name,
            }

            symbol.value = func
            om.insert(&symbols, symbol_name, symbol)
        }
    }

    constants: {
        sect, ok := ini_file["constants"]
        if !ok do break constants
        defer delete_key(&ini_file, "constants")

        rs.constants = om.make(string, Constant)

        for value in sect.data {
            name, value_type := value.key, value.value
            c := parse_constant(value_type) or_return
            om.insert(&rs.constants, name, c)
        }
    }

    if len(ini_file) != 0 {
        when ODIN_DEBUG {
            fmt.eprintln("Sections")
            for sec in ini_file {
                fmt.eprintfln("\"{}\"", sec)
            }
        }
        return rs, errors.message(
            "unrecognized sections in ini: {}",
            len(ini_file),
        )
    }

    return
}

runestone_destroy :: proc(rs: ^Runestone) {
    runtime.arena_destroy(&rs.arena)
}

write_runestone :: proc(
    rs: Runestone,
    wd: io.Writer,
    file_path: string,
) -> io.Error {
    io.write_string(wd, "version = ") or_return
    io.write_uint(wd, rs.version) or_return
    io.write_string(wd, "\n\n") or_return

    io.write_string(wd, "os = ") or_return
    fmt.wprintln(wd, rs.platform.os)
    io.write_string(wd, "arch = ") or_return
    fmt.wprintln(wd, rs.platform.arch)
    io.write_rune(wd, '\n') or_return

    io.write_string(wd, "[lib]\n") or_return

    if shared, ok := rs.lib.shared.?; ok {
        io.write_string(wd, "shared = ") or_return

        if filepath.is_abs(shared) {
            dir_name := filepath.dir(file_path)
            defer delete(dir_name)
            rel_shared, err := filepath.rel(dir_name, shared)
            if err == .None && len(rel_shared) < len(shared) {
                if !strings.contains(rel_shared, "/") &&
                   !strings.contains(rel_shared, "\\") {
                    io.write_string(wd, "./") or_return
                }
                io.write_string(wd, rel_shared) or_return
            } else {
                io.write_string(wd, shared) or_return
            }
        } else {
            io.write_string(wd, shared) or_return
        }

        io.write_rune(wd, '\n') or_return
    }
    if static, ok := rs.lib.static.?; ok {
        io.write_string(wd, "static = ") or_return

        if filepath.is_abs(static) {
            dir_name := filepath.dir(file_path)
            defer delete(dir_name)
            rel_static, err := filepath.rel(dir_name, static)
            if err == .None && len(rel_static) < len(static) {
                if !strings.contains(rel_static, "/") &&
                   !strings.contains(rel_static, "\\") {
                    io.write_string(wd, "./") or_return
                }
                io.write_string(wd, rel_static) or_return
            } else {
                io.write_string(wd, static) or_return
            }
        } else {
            io.write_string(wd, static) or_return
        }

        io.write_rune(wd, '\n') or_return
    }
    io.write_rune(wd, '\n') or_return

    io.write_string(wd, "[symbols]\n") or_return

    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        func_ptr: Maybe(Function)

        switch t in sym.value {
        case Type:
            io.write_string(wd, "var") or_return
        case Function:
            io.write_string(wd, "func") or_return
        }
        io.write_rune(wd, '.') or_return
        if rp, ok := sym.remap.?; ok {
            io.write_string(wd, rp) or_return
        } else {
            io.write_string(wd, name) or_return
        }
        io.write_string(wd, " = ") or_return

        switch v in sym.value {
        case Type:
            if fp, ok := func_ptr.?; ok {
                write_function(wd, fp) or_return
            } else {
                write_type(wd, v) or_return
            }
        case Function:
            write_function(wd, v) or_return
        }

        io.write_rune(wd, '\n') or_return
    }

    io.write_rune(wd, '\n') or_return

    some_remaps: bool
    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        if sym.remap != nil {
            if !some_remaps {
                some_remaps = true
                io.write_string(wd, "[remap]\n") or_return
            }

            io.write_string(wd, name) or_return
            io.write_string(wd, " = ") or_return
            io.write_string(wd, sym.remap.?) or_return
            io.write_rune(wd, '\n') or_return
        }
    }

    if some_remaps do io.write_rune(wd, '\n') or_return

    some_alias: bool
    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        if len(sym.aliases) != 0 {
            if !some_alias {
                some_alias = true
                io.write_string(wd, "[alias]\n") or_return
            }

            for a in sym.aliases {
                io.write_string(wd, a) or_return
                io.write_string(wd, " = ") or_return
                io.write_string(wd, name) or_return
                io.write_rune(wd, '\n') or_return
            }
        }
    }

    if some_alias do io.write_rune(wd, '\n') or_return

    if om.length(rs.externs) != 0 {
        io.write_string(wd, "[extern]\n") or_return

        for entry in rs.externs.data {
            name, extern := entry.key, entry.value

            io.write_string(wd, name) or_return
            io.write_string(wd, " = \"") or_return
            // TODO: parse for line breaks (= \n) and stuff
            io.write_string(wd, extern.source) or_return
            io.write_string(wd, "\" ") or_return
            write_type(wd, extern.type) or_return
            io.write_rune(wd, '\n') or_return
        }

        io.write_rune(wd, '\n') or_return
    }

    if om.length(rs.types) != 0 {
        io.write_string(wd, "[types]\n") or_return

        for entry in rs.types.data {
            name, ty := entry.key, entry.value
            io.write_string(wd, name) or_return
            io.write_string(wd, " = ") or_return
            write_type(wd, ty) or_return
            io.write_rune(wd, '\n') or_return
        }
        io.write_rune(wd, '\n') or_return
    }

    some_method_info: bool
    for entry in rs.symbols.data {
        name, sym := entry.key, entry.value
        if f, ok := sym.value.(Function); ok {
            if mi, mi_ok := f.method_info.?; mi_ok {
                if !some_method_info {
                    some_method_info = true
                    io.write_string(wd, "[methods]\n") or_return
                }

                io.write_string(wd, mi.type) or_return
                io.write_rune(wd, '.') or_return
                io.write_string(wd, mi.name) or_return
                io.write_string(wd, " = ") or_return
                io.write_string(wd, name) or_return
                io.write_rune(wd, '\n') or_return
            }
        }
    }

    if some_method_info do io.write_rune(wd, '\n') or_return

    if om.length(rs.constants) != 0 {
        io.write_string(wd, "[constants]\n") or_return

        for entry in rs.constants.data {
            name, value_type := entry.key, entry.value
            io.write_string(wd, name) or_return
            io.write_string(wd, " = ") or_return
            switch v in value_type.value {
            case i64:
                io.write_i64(wd, v, 10) or_return
            case f64:
                io.write_f64(wd, v) or_return
            case string:
                io.write_rune(wd, '"') or_return
                io.write_string(wd, v) or_return
                io.write_rune(wd, '"') or_return
            }

            io.write_rune(wd, ' ') or_return

            write_type(wd, value_type.type) or_return
            io.write_rune(wd, '\n') or_return
        }

        io.write_rune(wd, '\n') or_return
    }

    return .None
}

@(private)
parse_func :: proc(def: string) -> (func: Function, err: errors.Error) {
    token_arena: runtime.Arena
    defer runtime.arena_destroy(&token_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = runtime.arena_allocator(&token_arena)

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, "func", transmute([]u8)def, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.wrap(token != nil) or_return

    func, _ = parse_func_token(token) or_return
    return
}

@(private)
parse_type :: proc(def: string) -> (type: Type, err: errors.Error) {
    token_arena: runtime.Arena
    defer runtime.arena_destroy(&token_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = runtime.arena_allocator(&token_arena)

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, "type", transmute([]u8)def, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.assert(token != nil) or_return

    type, _ = parse_type_token(token) or_return
    return
}

@(private = "file")
parse_type_token :: proc(
    _token: ^ctz.Token,
) -> (
    type: Type,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    if token.kind == .Punct && token.lit == "#" {
        token = token.next
        errors.assert(token.kind == .Ident) or_return

        switch token.lit {
        case "Untyped":
            type.spec = Builtin.Untyped
        case "Void":
            type.spec = Builtin.Void
        case "RawPtr":
            type.spec = Builtin.RawPtr
        case "SInt8":
            type.spec = Builtin.SInt8
        case "SInt16":
            type.spec = Builtin.SInt16
        case "SInt32":
            type.spec = Builtin.SInt32
        case "SInt64":
            type.spec = Builtin.SInt64
        case "SInt128":
            type.spec = Builtin.SInt128
        case "UInt8":
            type.spec = Builtin.UInt8
        case "UInt16":
            type.spec = Builtin.UInt16
        case "UInt32":
            type.spec = Builtin.UInt32
        case "UInt64":
            type.spec = Builtin.UInt64
        case "UInt128":
            type.spec = Builtin.UInt128
        case "Float32":
            type.spec = Builtin.Float32
        case "Float64":
            type.spec = Builtin.Float64
        case "Float128":
            type.spec = Builtin.Float128
        case "String":
            type.spec = Builtin.String
        case "Bool8":
            type.spec = Builtin.Bool8
        case "Bool16":
            type.spec = Builtin.Bool16
        case "Bool32":
            type.spec = Builtin.Bool32
        case "Bool64":
            type.spec = Builtin.Bool64
        case "Struct":
            token = token.next

            s: Struct = ---
            s, token = parse_struct_token(token) or_return
            type.spec = s
            return
        case "Enum":
            token = token.next

            e: Enum = ---
            e, token = parse_enum_token(token) or_return
            type.spec = e
            return
        case "Union":
            token = token.next

            u: Union = ---
            u, token = parse_union_token(token) or_return
            type.spec = u
            return
        case "Unknown":
            token = token.next
            errors.assert(token.kind == .Ident) or_return

            type.spec = Unknown(token.lit)
        case "FuncPtr":
            token = token.next
            func: Function = ---
            func, token = parse_func_token(token) or_return
            type.spec = cast(FunctionPointer)new_clone(func)
            return
        case "Extern":
            token = token.next
            errors.assert(token.kind == .Ident) or_return

            type.spec = ExternType(token.lit)
        case:
            err = errors.message("invalid type specifier {}", token.lit)
            return
        }

        token = token.next
    } else if token.kind != .Ident {
        err = errors.message(
            "invalid type specifier {}",
            "EOF" if token.kind == .EOF else token.lit,
        )
        return
    } else {
        type.spec = token.lit
        token = token.next
    }

    if token.lit == "#" {
        if p := token.next; p.lit == "Attr" {
            current_pointer_info := &type.pointer_info
            current_array: ^Array
            current_read_only := &type.read_only
            current_write_only := &type.write_only

            for token = p.next;
                token.kind != .EOF && token.lit != "#";
                token = token.next {

                switch token.lit {
                case "Ptr":
                    token = token.next
                    errors.assert(token.kind == .Number) or_return

                    count, ok := strconv.parse_uint(token.lit)
                    errors.wrap(ok) or_return

                    current_pointer_info.count += count
                    current_read_only = &current_pointer_info.read_only
                    current_write_only = &current_pointer_info.write_only
                case "Arr":
                    token = token.next

                    append(&type.array_info, Array{})
                    current_array = &type.array_info[len(type.array_info) - 1]

                    #partial switch token.kind {
                    case .Number:
                        size, ok := strconv.parse_u64(token.lit)
                        errors.wrap(ok) or_return

                        current_array.size = size if size != 0 else nil
                    case .String:
                        current_array.size = strings.trim_suffix(
                            strings.trim_prefix(token.lit, "\""),
                            "\"",
                        )
                    case .Ident:
                        current_array.size = ConstantRef {
                            name = token.lit,
                        }
                    case:
                        err = errors.message(
                            "Number, String or Identifier expected after Arr but got {} (\"{}\")",
                            token.kind,
                            token.lit,
                        )
                        return
                    }

                    current_pointer_info = &current_array.pointer_info
                    current_read_only = &current_array.read_only
                    current_write_only = &current_array.write_only
                case "ReadOnly":
                    current_read_only^ = true
                case "WriteOnly":
                    current_write_only^ = true
                case:
                    err = errors.message("invalid attribute {}", token.lit)
                    return
                }
            }
            token = token.next

            errors.assert(
                token.lit == "AttrEnd",
                "#AttrEnd expected",
            ) or_return

            token = token.next
        }
    }

    return
}

@(private = "file")
parse_func_token :: proc(
    _token: ^ctz.Token,
) -> (
    func: Function,
    token: ^ctz.Token,
    err: errors.Error,
) {
    func.return_type, token = parse_type_token(_token) or_return

    for token.kind != .EOF {
        errors.assert(token.kind == .Ident) or_return

        name := token.lit
        token = token.next

        if token.lit == "#" {
            if p := token.next; p.lit == "Variadic" {
                func.variadic = true
                token = p.next
                continue
            }
        }

        type: Type = ---
        type, token = parse_type_token(token) or_return

        append(&func.parameters, Member{name = name, type = type})
    }

    return
}

@(private = "file")
parse_struct :: proc(def: string) -> (s: Struct, err: errors.Error) {
    token_arena: runtime.Arena
    defer runtime.arena_destroy(&token_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = runtime.arena_allocator(&token_arena)

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, "struct", transmute([]u8)def, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.assert(token != nil) or_return

    s, _ = parse_struct_token(token) or_return
    return
}

@(private = "file")
parse_struct_token :: proc(
    _token: ^ctz.Token,
) -> (
    s: Struct,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    for token.kind != .EOF {
        errors.assert(token.kind == .Ident) or_return

        name := token.lit
        token = token.next

        type: Type = ---
        type, token = parse_type_token(token) or_return

        append(&s.members, Member{name = name, type = type})
    }

    return
}

@(private = "file")
parse_enum :: proc(def: string) -> (e: Enum, err: errors.Error) {
    token_arena: runtime.Arena
    defer runtime.arena_destroy(&token_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = runtime.arena_allocator(&token_arena)

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, "enum", transmute([]u8)def, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.assert(token != nil) or_return

    e, _ = parse_enum_token(token) or_return
    return
}

@(private = "file")
parse_enum_token :: proc(
    _token: ^ctz.Token,
) -> (
    e: Enum,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    errors.assert(token.lit == "#") or_return
    token = token.next
    errors.assert(token.kind == .Ident) or_return

    switch token.lit {
    case "SInt8":
        e.type = .SInt8
    case "SInt16":
        e.type = .SInt16
    case "SInt32":
        e.type = .SInt32
    case "SInt64":
        e.type = .SInt64
    case "SInt128":
        e.type = .SInt128
    case "UInt8":
        e.type = .UInt8
    case "UInt16":
        e.type = .UInt16
    case "UInt32":
        e.type = .UInt32
    case "UInt64":
        e.type = .UInt64
    case "UInt128":
        e.type = .UInt128
    case:
        err = errors.message("invalid enum type {}", token.lit)
        return
    }

    token = token.next

    for token.kind != .EOF {
        errors.assert(token.kind == .Ident) or_return

        name := token.lit
        token = token.next

        value: EnumConstant

        #partial switch token.kind {
        case .Number:
            n, ok := strconv.parse_i64(token.lit)
            errors.wrap(ok) or_return

            value = n
        case .String:
            value = strings.trim_suffix(
                strings.trim_prefix(token.lit, `"`),
                `"`,
            )
        case .Ident:
            value = ConstantRef {
                name = token.lit,
            }
        case:
            err = errors.empty()
            return
        }

        token = token.next

        append(&e.entries, EnumEntry{name = name, value = value})
    }

    return
}

@(private = "file")
parse_union :: proc(def: string) -> (u: Union, err: errors.Error) {
    s := parse_struct(def) or_return
    u = Union {
        members = s.members,
    }
    return
}

@(private = "file")
parse_union_token :: proc(
    _token: ^ctz.Token,
) -> (
    u: Union,
    token: ^ctz.Token,
    err: errors.Error,
) {
    s: Struct = ---
    s, token = parse_struct_token(_token) or_return
    u = Union {
        members = s.members,
    }
    return
}

@(private)
parse_constant :: proc(def: string) -> (c: Constant, err: errors.Error) {
    token_arena: runtime.Arena
    defer runtime.arena_destroy(&token_arena)

    token: ^ctz.Token = ---
    {
        context.allocator = runtime.arena_allocator(&token_arena)

        tokenizer: ctz.Tokenizer
        file := ctz.add_new_file(&tokenizer, "constant", transmute([]u8)def, 1)
        token = ctz.tokenize(&tokenizer, file)
    }

    errors.assert(token != nil) or_return

    c, _ = parse_constant_token(token) or_return
    return
}

@(private = "file")
parse_constant_token :: proc(
    _token: ^ctz.Token,
) -> (
    c: Constant,
    token: ^ctz.Token,
    err: errors.Error,
) {
    token = _token

    #partial switch token.kind {
    case .Number:
        ok: bool = ---
        switch token.type_hint {
        case .None:
            c.value, ok = strconv.parse_i64(token.lit)
            if !ok {
                c.value, ok = strconv.parse_f64(token.lit)
                errors.wrap(ok) or_return
            }
        case .Int ..= .Unsigned_Long_Long:
            c.value, ok = strconv.parse_i64(token.lit)
            errors.wrap(ok) or_return
        case .Float ..= .Long_Double:
            c.value, ok = strconv.parse_f64(token.lit)
            errors.wrap(ok) or_return
        case .UTF_8 ..= .UTF_Wide:
            err = errors.empty()
            return
        }
    case .String:
        c.value = strings.trim_suffix(
            strings.trim_prefix(token.lit, "\""),
            "\"",
        )
    case:
        err = errors.message(
            "{}: int, float or string expected but got {}",
            token.pos.column,
            token.lit,
        )
        return
    }

    token = token.next

    errors.assert(token.kind == .Punct && token.lit == "#") or_return

    c.type, token = parse_type_token(token) or_return
    return
}

@(private = "file")
write_type_specifier :: proc(wd: io.Writer, ts: TypeSpecifier) -> io.Error {
    switch t in ts {
    case Builtin:
        fmt.wprintf(wd, "#{}", t)
    case Struct:
        io.write_string(wd, "#Struct") or_return
        for m in t.members {
            io.write_rune(wd, ' ') or_return
            io.write_string(wd, m.name) or_return
            io.write_rune(wd, ' ') or_return
            write_type(wd, m.type) or_return
        }
    case Union:
        io.write_string(wd, "#Union") or_return
        for m in t.members {
            io.write_rune(wd, ' ') or_return
            io.write_string(wd, m.name) or_return
            io.write_rune(wd, ' ') or_return
            write_type(wd, m.type) or_return
        }
    case Enum:
        fmt.wprintf(wd, "#Enum #{}", t.type)
        for e in t.entries {
            io.write_rune(wd, ' ') or_return
            io.write_string(wd, e.name) or_return
            io.write_rune(wd, ' ') or_return
            switch v in e.value {
            case i64:
                io.write_i64(wd, v) or_return
            case string:
                io.write_rune(wd, '"') or_return
                io.write_string(wd, v) or_return
                io.write_rune(wd, '"') or_return
            case ConstantRef:
                io.write_string(wd, v.name) or_return
            }
        }
    case FunctionPointer:
        io.write_string(wd, "#FuncPtr ") or_return
        write_function(wd, t^) or_return
    case Unknown:
        io.write_string(wd, "#Unknown ") or_return
        io.write_string(wd, string(t)) or_return
    case string:
        io.write_string(wd, t) or_return
    case ExternType:
        io.write_string(wd, "#Extern ") or_return
        io.write_string(wd, string(t)) or_return
    }

    return .None
}

write_type :: proc(wd: io.Writer, ty: Type) -> io.Error {
    write_type_specifier(wd, ty.spec) or_return

    has_attr :=
        ty.pointer_info.count != 0 ||
        len(ty.array_info) != 0 ||
        ty.read_only ||
        ty.write_only

    if has_attr {
        io.write_string(wd, " #Attr") or_return
    }

    if ty.read_only {
        io.write_string(wd, " ReadOnly") or_return
    }
    if ty.write_only {
        io.write_string(wd, " WriteOnly") or_return
    }

    if ty.pointer_info.count != 0 {
        io.write_rune(wd, ' ') or_return
        io.write_string(wd, "Ptr ") or_return
        io.write_uint(wd, ty.pointer_info.count) or_return
        if ty.pointer_info.read_only {
            io.write_string(wd, " ReadOnly") or_return
        }
        if ty.pointer_info.write_only {
            io.write_string(wd, " WriteOnly") or_return
        }
    }

    for a in ty.array_info {
        io.write_rune(wd, ' ') or_return
        io.write_string(wd, "Arr ") or_return
        if a.size == nil {
            io.write_rune(wd, '0') or_return
        } else {
            switch s in a.size {
            case u64:
                io.write_u64(wd, s) or_return
            case string:
                io.write_rune(wd, '"') or_return
                io.write_string(wd, s) or_return
                io.write_rune(wd, '"') or_return
            case ConstantRef:
                io.write_string(wd, s.name) or_return
            }
        }

        if a.read_only {
            io.write_string(wd, " ReadOnly") or_return
        }
        if a.write_only {
            io.write_string(wd, " WriteOnly") or_return
        }

        if a.pointer_info.count != 0 {
            io.write_rune(wd, ' ') or_return
            io.write_string(wd, "Ptr ") or_return
            io.write_uint(wd, a.pointer_info.count) or_return

            if a.pointer_info.read_only {
                io.write_string(wd, " ReadOnly") or_return
            }
            if a.pointer_info.write_only {
                io.write_string(wd, " WriteOnly") or_return
            }
        }
    }

    if has_attr {
        io.write_string(wd, " #AttrEnd") or_return
    }

    return .None
}

write_function :: proc(wd: io.Writer, fc: Function) -> io.Error {
    write_type(wd, fc.return_type) or_return

    for p in fc.parameters {
        io.write_rune(wd, ' ') or_return
        io.write_string(wd, p.name) or_return
        io.write_rune(wd, ' ') or_return
        write_type(wd, p.type) or_return
    }

    if fc.variadic {
        io.write_rune(wd, ' ') or_return
        io.write_string(wd, "var_args #Variadic") or_return
    }

    return .None
}

create_anon_type :: proc(
    spec: TypeSpecifier,
    anon_counter: ^int,
    ow: OverwriteSet,
    allocator := context.allocator,
) -> (
    anon_name: string,
    anon_type: Type,
    is_anon: bool,
) {
    is_anon = true

    #partial switch s in spec {
    case Struct:
        anon_type = Type {
            spec = s,
        }
    case Union:
        anon_type = Type {
            spec = s,
        }
    case Enum:
        anon_type = Type {
            spec = s,
        }
    case FunctionPointer:
        anon_type = Type {
            spec = s,
        }
    case:
        is_anon = false
    }

    if is_anon {
        anon_name = fmt.aprintf(
            "anon_{}",
            anon_counter^,
            allocator = allocator,
        )
        anon_counter^ += 1
    }

    return
}

from_postprocess_runestone :: proc(rs: ^Runestone, from: From) {
    rs_arena_alloc := runtime.arena_allocator(&rs.arena)

    for remap_name, remap_value in from.remaps {
        if sym, sym_ok := om.get(rs.symbols, remap_name); sym_ok {
            sym.remap = strings.clone(remap_value, rs_arena_alloc)
            om.insert(&rs.symbols, remap_name, sym)
        }
    }

    for alias_name, alias_values in from.aliases {
        if sym, sym_ok := om.get(rs.symbols, alias_name); sym_ok {
            for alias_value in alias_values {
                append(
                    &sym.aliases,
                    strings.clone(alias_value, rs_arena_alloc),
                )
            }
            om.insert(&rs.symbols, alias_name, sym)
        }
    }
}

