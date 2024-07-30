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
import "core:strings"
import ccdg "root:c/codegen"
import "root:errors"
import om "root:ordered_map"
import "root:runic"
import clang "shared:libclang"

ClientData :: struct {
    rs:        ^runic.Runestone,
    allocator: runtime.Allocator,
    err:       errors.Error,
    isz:       ccdg.Int_Sizes,
}

generate_runestone :: proc(
    plat: runic.Platform,
    rune_file_name: string,
    rf: runic.From,
) -> (
    rs: runic.Runestone,
    err: errors.Error,
) {
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    arena_alloc := runtime.arena_allocator(&arena)

    rs_arena_alloc := runtime.arena_allocator(&rs.arena)

    rs.platform = plat
    runic.set_library(plat, &rs, rf)

    clang_flags := make([dynamic]cstring, arena_alloc)

    if rune_defines, ok := runic.platform_value_get(
        map[string]string,
        rf.defines,
        plat,
    ); ok {
        for name, value in rune_defines {
            arg := strings.clone_to_cstring(
                fmt.aprintf("-D{}={}", name, value, allocator = arena_alloc),
                arena_alloc,
            )

            append(&clang_flags, arg)
        }
    }

    headers := runic.platform_value_get([]string, rf.headers, plat)
    /*overwrite := runic.platform_value_get(
        runic.OverwriteSet,
        rf.overwrite,
        plat,
    )
    ignore := runic.platform_value_get(runic.IgnoreSet, rf.ignore, plat)*/

    for header in headers {
        header_cstr := strings.clone_to_cstring(header, arena_alloc)

        index := clang.createIndex(0, 0)
        defer clang.disposeIndex(index)

        unit := clang.parseTranslationUnit(
            index,
            header_cstr,
            raw_data(clang_flags),
            i32(len(clang_flags)),
            nil,
            0,
            u32(clang.CXTranslationUnit_Flags.CXTranslationUnit_None),
        )

        if unit == nil {
            err = errors.message(
                "\"{}\" failed to parse translation unit",
                header,
            )
            return
        }
        defer clang.disposeTranslationUnit(unit)

        num_diag := clang.getNumDiagnostics(unit)
        if num_diag != 0 {
            err_msg: strings.Builder
            strings.builder_init(&err_msg, errors.error_allocator)

            for idx in 0 ..< num_diag {
                dig := clang.getDiagnostic(unit, idx)
                defer clang.disposeDiagnostic(dig)

                sev := clang.getDiagnosticSeverity(dig)

                #partial switch sev {
                case .CXDiagnostic_Error, .CXDiagnostic_Fatal:
                    dig_msg := clang.formatDiagnostic(
                        dig,
                        clang.defaultDiagnosticDisplayOptions(),
                    )
                    defer clang.disposeString(dig_msg)

                    dig_str := strings.clone_from_cstring(
                        clang.getCString(dig_msg),
                        arena_alloc,
                    )

                    strings.write_string(&err_msg, dig_str)
                    strings.write_rune(&err_msg, '\n')
                }
            }

            if strings.builder_len(err_msg) != 0 {
                err = errors.message(
                    "\"{}\": {}",
                    header,
                    strings.to_string(err_msg),
                )
                return
            }
        }

        rs.constants = om.make(
            string,
            runic.Constant,
            allocator = rs_arena_alloc,
        )
        rs.symbols = om.make(string, runic.Symbol, allocator = rs_arena_alloc)
        rs.types = om.make(string, runic.Type, allocator = rs_arena_alloc)

        cursor := clang.getTranslationUnitCursor(unit)

        data := ClientData {
            rs        = &rs,
            allocator = rs_arena_alloc,
            isz       = ccdg.int_sizes_from_platform(plat),
        }

        clang.visitChildren(
            cursor,
            proc "c" (
                cursor, parent: clang.CXCursor,
                client_data: clang.CXClientData,
            ) -> clang.CXChildVisitResult {
                data := cast(^ClientData)client_data
                context = runtime.default_context()
                rs_arena_alloc := data.allocator

                cursor_kind := clang.getCursorKind(cursor)
                cursor_type := clang.getCursorType(cursor)
                display_name := clang.getCursorDisplayName(cursor)
                storage_class := clang.Cursor_getStorageClass(cursor)

                defer clang.disposeString(display_name)

                #partial switch cursor_kind {
                case .CXCursor_TypedefDecl:
                    typedef := clang.getTypedefDeclUnderlyingType(cursor)

                    type_name := clang.getTypedefName(cursor_type)
                    defer clang.disposeString(type_name)

                    type: runic.Type = ---
                    type, data.err = clang_type_to_runic_type(
                        typedef,
                        cursor,
                        data.isz,
                        rs_arena_alloc,
                    )
                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    om.insert(
                        &data.rs.types,
                        strings.clone_from_cstring(
                            clang.getCString(type_name),
                            rs_arena_alloc,
                        ),
                        type,
                    )
                case .CXCursor_VarDecl:
                    switch storage_class {
                    case .CX_SC_Invalid, .CX_SC_Extern, .CX_SC_Static, .CX_SC_OpenCLWorkGroupLocal, .CX_SC_PrivateExtern:
                        return .CXChildVisit_Continue
                    case .CX_SC_Auto, .CX_SC_None, .CX_SC_Register:
                    }

                    type: runic.Type = ---
                    type, data.err = clang_type_to_runic_type(
                        cursor_type,
                        cursor,
                        data.isz,
                        rs_arena_alloc,
                    )

                    if data.err != nil {
                        fmt.eprintln(data.err, "\n")
                        data.err = nil
                        return .CXChildVisit_Continue
                    }

                    om.insert(
                        &data.rs.symbols,
                        strings.clone_from_cstring(
                            clang.getCString(display_name),
                            rs_arena_alloc,
                        ),
                        runic.Symbol{value = type},
                    )
                case:
                    fmt.printfln("Other Cursor Type: {}", cursor_kind)
                }

                return .CXChildVisit_Continue
            },
            &data,
        )

        if data.err != nil {
            err = data.err
            return
        }
    }

    return
}

clang_type_to_runic_type :: proc(
    type: clang.CXType,
    cursor: clang.CXCursor,
    isz: ccdg.Int_Sizes,
    allocator := context.allocator,
) -> (
    tp: runic.Type,
    err: errors.Error,
) {
    #partial switch type.kind {
    case .CXType_Void:
        tp.spec = runic.Builtin.Void
    case .CXType_Bool:
        tp.spec = ccdg.bool_type(isz._Bool)
    case .CXType_Char_U:
        tp.spec = ccdg.int_type(isz.char, false)
    case .CXType_UChar:
        tp.spec = ccdg.int_type(isz.char, false)
    case .CXType_Char16:
        tp.spec = runic.Builtin.SInt16
    case .CXType_Char32:
        tp.spec = runic.Builtin.SInt32
    case .CXType_UShort:
        tp.spec = ccdg.int_type(isz.short, false)
    case .CXType_UInt:
        tp.spec = ccdg.int_type(isz.Int, false)
    case .CXType_ULong:
        tp.spec = ccdg.int_type(isz.long, false)
    case .CXType_ULongLong:
        tp.spec = ccdg.int_type(isz.longlong, false)
    case .CXType_UInt128:
        tp.spec = runic.Builtin.SInt128
    case .CXType_Char_S:
        tp.spec = ccdg.int_type(isz.char, true)
    case .CXType_SChar:
        tp.spec = ccdg.int_type(isz.char, true)
    case .CXType_WChar:
        // TODO: find out about wchar_t
        tp.spec = runic.Builtin.UInt32
    case .CXType_Short:
        tp.spec = ccdg.int_type(isz.short, true)
    case .CXType_Int:
        tp.spec = ccdg.int_type(isz.Int, true)
    case .CXType_Long:
        tp.spec = ccdg.int_type(isz.long, true)
    case .CXType_LongLong:
        tp.spec = ccdg.int_type(isz.longlong, true)
    case .CXType_Int128:
        tp.spec = runic.Builtin.SInt128
    case .CXType_Float:
        tp.spec = ccdg.float_type(isz.float)
    case .CXType_Double:
        tp.spec = ccdg.float_type(isz.double)
    case .CXType_LongDouble:
        tp.spec = ccdg.float_type(isz.long_double)
    case .CXType_Float128:
        tp.spec = runic.Builtin.Float128
    case .CXType_Pointer:
        pointee := clang.getPointeeType(type)
        tp = clang_type_to_runic_type(pointee, cursor, isz) or_return

        if pointee.kind == .CXType_Void {
            tp.spec = runic.Builtin.RawPtr
        } else {
            // NOTE: Not Sure
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.count += 1
            } else {
                tp.pointer_info.count += 1
            }
        }

        if clang.isConstQualifiedType(pointee) != 0 {
            // NOTE: Not Sure
            if len(tp.array_info) != 0 {
                tp.array_info[len(tp.array_info) - 1].pointer_info.read_only =
                    true
            } else {
                tp.pointer_info.read_only = true
            }
        }
    case .CXType_Enum:
        return tp, errors.not_implemented()
    case .CXType_ConstantArray:
        arr_type := clang.getArrayElementType(type)
        tp = clang_type_to_runic_type(
            arr_type,
            cursor,
            isz,
            allocator,
        ) or_return

        // NOTE: Probably dangerous, because it uses the values and sizes from the host platform
        arr_size := clang.getArraySize(type)

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, allocator)
        }

        append(&tp.array_info, runic.Array{size = u64(arr_size)})
    case .CXType_IncompleteArray:
        arr_type := clang.getArrayElementType(type)
        tp = clang_type_to_runic_type(
            arr_type,
            cursor,
            isz,
            allocator,
        ) or_return

        if len(tp.array_info) == 0 {
            tp.array_info = make([dynamic]runic.Array, allocator)
        }

        append(&tp.array_info, runic.Array{size = nil})
    case .CXType_Elaborated:
        return tp, errors.not_implemented()
    case .CXType_Typedef:
        type_name := clang.getTypedefName(type)
        defer clang.disposeString(type_name)

        tp.spec = strings.clone_from_cstring(
            clang.getCString(type_name),
            allocator,
        )
    case:
        type_spell := clang.getTypeKindSpelling(type.kind)
        defer clang.disposeString(type_spell)

        err = clang_source_error(
            cursor,
            "unsupported type \"{}\"",
            clang.getCString(type_spell),
        )
        return
    }

    if clang.isConstQualifiedType(type) != 0 {
        if len(tp.array_info) != 0 {
            tp.array_info[len(tp.array_info) - 1].read_only = true
        }
        tp.read_only = true
    }

    if b, ok := tp.spec.(runic.Builtin); ok && b == .SInt8 {
        if tp.pointer_info.count != 0 {
            tp.spec = runic.Builtin.String
            tp.pointer_info.count -= 1
        }
    }

    return
}

clang_source_error :: proc(
    cursor: clang.CXCursor,
    msg: string,
    args: ..any,
    loc := #caller_location,
) -> errors.Error {
    cursor_loc := clang.getCursorLocation(cursor)

    line, column, offset: u32 = ---, ---, ---
    file: clang.CXFile = ---

    clang.getExpansionLocation(cursor_loc, &file, &line, &column, &offset)

    file_name := clang.getFileName(file)
    defer clang.disposeString(file_name)

    return errors.message(
        "{}:{}:{}: {}",
        clang.getCString(file_name),
        line,
        column,
        fmt.aprintf(msg, ..args, allocator = errors.error_allocator),
        loc = loc,
    )
}
