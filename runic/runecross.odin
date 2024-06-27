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
import "core:slice"
import "root:errors"
import om "root:ordered_map"

// TODO: memory management
Runecross :: struct {
    arenas:  [dynamic]runtime.Arena,
    general: RunestoneWithFile,
    cross:   [dynamic]PlatformRunestone,
}

PlatformRunestone :: struct {
    plats:           []Platform,
    using runestone: RunestoneWithFile,
}

RunestoneWithFile :: struct {
    file_path:   string,
    using stone: Runestone,
}

cross_the_runes :: proc(
    file_paths: [dynamic]string,
    stones: [dynamic]Runestone,
) -> (
    rc: Runecross,
    err: errors.Error,
) {
    errors.assert(len(stones) != 0, "no runestones specified") or_return

    rn_arena_alloc := runtime.arena_allocator(&stones[0].arena)

    rc.arenas = make([dynamic]runtime.Arena, len(stones))
    for stone, idx in stones {
        rc.arenas[idx] = stone.arena
    }

    errors.assert(
        len(file_paths) == len(stones),
        "file_paths and stones should have the same length",
    ) or_return
    if len(stones) == 1 {
        rc.general = RunestoneWithFile {
            file_path = file_paths[0],
            stone     = stones[0],
        }
        return
    }


    origin := om.make(Platform, RunestoneWithFile)
    defer om.delete(origin)

    for stone, idx in stones {
        if om.contains(origin, stone.platform) {
            err = errors.message(
                "duplicate runestone for platform {}.{}",
                stone.platform.os,
                stone.platform.arch,
            )
            return
        }

        om.insert(
            &origin,
            stone.platform,
            RunestoneWithFile{file_path = file_paths[idx], stone = stone},
        )
    }

    rc.general.file_path = "/general"
    rc.general.types = om.make(string, Type, allocator = rn_arena_alloc)
    rc.general.symbols = om.make(string, Symbol, allocator = rn_arena_alloc)
    rc.general.constants = om.make(
        string,
        Constant,
        allocator = rn_arena_alloc,
    )

    for entry0 in origin.data {
        stone1 := entry0.value

        {
            plats := get_same_platforms(
                stone1,
                origin,
                proc(stone1, stone2: RunestoneWithFile, _: rawptr) -> bool {
                    return(
                        stone1.lib.shared == stone2.lib.shared &&
                        stone1.lib.static == stone2.lib.static \
                    )
                },
            )
            defer delete(plats)

            set_for_same_platforms(
                stone1,
                plats,
                om.length(origin),
                &rc,
                proc(
                    stone1: RunestoneWithFile,
                    stone2: ^RunestoneWithFile,
                    _: rawptr,
                ) {
                    stone2.lib.shared = stone1.lib.shared
                    stone2.lib.static = stone1.lib.static
                },
                allocator = rn_arena_alloc,
            )
        }

        // types
        for entry1 in stone1.types.data {
            name1 := entry1.key

            plats := get_same_platforms(
                stone1,
                origin,
                proc(
                    stone1, stone2: RunestoneWithFile,
                    user_data: rawptr,
                ) -> bool {
                    name1 := cast(^string)user_data
                    type1 := om.get(stone1.types, name1^)

                    if type2, ok := om.get(stone2.types, name1^); ok {
                        if is_same(type1, type2) {
                            return true
                        }
                    }

                    return false
                },
                &name1,
            )
            defer delete(plats)

            set_for_same_platforms(
                stone1,
                plats,
                om.length(origin),
                &rc,
                proc(
                    stone1: RunestoneWithFile,
                    stone2: ^RunestoneWithFile,
                    user_data: rawptr,
                ) {
                    name1 := cast(^string)user_data
                    om.insert(
                        &stone2.types,
                        name1^,
                        om.get(stone1.types, name1^),
                    )
                },
                &name1,
                allocator = rn_arena_alloc,
            )
        }

        // symbols
        for entry1 in stone1.symbols.data {
            name1 := entry1.key

            plats := get_same_platforms(
                stone1,
                origin,
                proc(
                    stone1, stone2: RunestoneWithFile,
                    user_data: rawptr,
                ) -> bool {
                    name1 := cast(^string)user_data
                    symbol1 := om.get(stone1.symbols, name1^)

                    if symbol2, ok := om.get(stone2.symbols, name1^); ok {
                        if is_same(symbol1, symbol2) {
                            return true
                        }
                    }

                    return false
                },
                &name1,
            )
            defer delete(plats)

            set_for_same_platforms(
                stone1,
                plats,
                om.length(origin),
                &rc,
                proc(
                    stone1: RunestoneWithFile,
                    stone2: ^RunestoneWithFile,
                    user_data: rawptr,
                ) {
                    name1 := cast(^string)user_data
                    symbol1 := om.get(stone1.symbols, name1^)

                    if symbol2, ok := om.get(stone2.symbols, name1^); ok {
                        for alias in symbol1.aliases {
                            if !slice.contains(symbol2.aliases[:], alias) {
                                append(&symbol2.aliases, alias)
                            }
                        }

                        om.insert(&stone2.symbols, name1^, symbol2)
                    } else {
                        om.insert(&stone2.symbols, name1^, symbol1)
                    }
                },
                &name1,
                allocator = rn_arena_alloc,
            )
        }

        // constants
        for entry1 in stone1.constants.data {
            name1 := entry1.key

            plats := get_same_platforms(
                stone1,
                origin,
                proc(
                    stone1, stone2: RunestoneWithFile,
                    user_data: rawptr,
                ) -> bool {
                    name1 := cast(^string)user_data
                    constant1 := om.get(stone1.constants, name1^)

                    if constant2, ok := om.get(stone2.constants, name1^); ok {
                        if is_same(constant1, constant2) {
                            return true
                        }
                    }

                    return false
                },
                &name1,
            )
            defer delete(plats)

            set_for_same_platforms(
                stone1,
                plats,
                om.length(origin),
                &rc,
                proc(
                    stone1: RunestoneWithFile,
                    stone2: ^RunestoneWithFile,
                    user_data: rawptr,
                ) {
                    name1 := cast(^string)user_data
                    constant1 := om.get(stone1.constants, name1^)
                    om.insert(&stone2.constants, name1^, constant1)
                },
                &name1,
                allocator = rn_arena_alloc,
            )
        }
    }

    slice.sort_by(rc.cross[:], proc(i, j: PlatformRunestone) -> bool {
        return len(i.plats) < len(j.plats)
    })

    return
}

runecross_is_simple :: proc(rc: Runecross) -> bool {
    return(
        om.length(rc.general.types) == 0 &&
        om.length(rc.general.symbols) == 0 &&
        om.length(rc.general.constants) == 0 &&
        len(rc.cross) == 1 \
    )
}

is_same_constant :: proc(c1, c2: Constant) -> bool {
    switch v1 in c1.value {
    case i64:
        v2 := c2.value.(i64) or_return
        if v1 != v2 do return false
    case f64:
        v2 := c2.value.(f64) or_return
        if v1 != v2 do return false
    case string:
        v2 := c2.value.(string) or_return
        if v1 != v2 do return false
    }

    return is_same(c1.type, c2.type)
}

is_same_array_size :: proc(as1, as2: ArraySize) -> bool {
    if as1 == nil {
        return as2 == nil
    }

    switch s1 in as1 {
    case u64:
        s2 := as2.(u64) or_return
        return s1 == s2
    case string:
        s2 := as2.(string) or_return
        return s1 == s2
    case ConstantRef:
        s2 := as2.(ConstantRef) or_return
        return s1.name == s2.name
    }
    return false
}

is_same_array :: proc(a1, a2: Array) -> bool {
    return(
        is_same(a1.pointer_info, a2.pointer_info) &&
        a1.read_only == a2.read_only &&
        a1.write_only == a2.write_only &&
        is_same(a1.size, a2.size) \
    )
}

is_same_array_info :: proc(ai1, ai2: [dynamic]Array) -> bool {
    if len(ai1) != len(ai2) do return false

    for i1, idx in ai1 {
        if !is_same(i1, ai2[idx]) do return false
    }

    return true
}

is_same_pointer_info :: proc(p1, p2: PointerInfo) -> bool {
    return(
        p1.count == p2.count &&
        p1.read_only == p2.read_only &&
        p1.write_only == p2.write_only \
    )
}

is_same_function :: proc(f1, f2: Function) -> bool {
    if len(f1.parameters) != len(f2.parameters) || f1.variadic != f2.variadic || !is_same(f1.return_type, f2.return_type) do return false

    for p1, idx in f1.parameters {
        #no_bounds_check p2 := f2.parameters[idx]
        if p1.name != p2.name || !is_same(p1.type, p2.type) do return false
    }

    return true
}

is_same_type_specifier :: proc(s1, s2: TypeSpecifier) -> bool {
    switch t1 in s1 {
    case Builtin:
        t2 := s2.(Builtin) or_return
        return t1 == t2
    case Struct:
        t2 := s2.(Struct) or_return
        if len(t1.members) != len(t2.members) do return false

        for m1, idx in t1.members {
            #no_bounds_check m2 := t2.members[idx]
            if m1.name != m2.name || !is_same(m1.type, m2.type) do return false
        }

        return true
    case Enum:
        t2 := s2.(Enum) or_return
        if t1.type != t2.type || len(t1.entries) != len(t2.entries) do return false

        for e1, idx in t1.entries {
            #no_bounds_check e2 := t2.entries[idx]
            if e1.name != e2.name do return false

            switch c1 in e1.value {
            case i64:
                c2 := e2.value.(i64) or_return
                return c1 == c2
            case string:
                c2 := e2.value.(string) or_return
                return c1 == c2
            case ConstantRef:
                c2 := e2.value.(ConstantRef) or_return
                return c1.name == c2.name
            }
        }
    case Union:
        t2 := s2.(Union) or_return
        if len(t1.members) != len(t2.members) do return false

        for m1, idx in t1.members {
            #no_bounds_check m2 := t2.members[idx]
            if m1.name != m2.name || !is_same(m1.type, m2.type) do return false
        }

        return true
    case string:
        t2 := s2.(string) or_return
        return t1 == t2
    case Unknown:
        _, ok := s2.(Unknown)
        return ok
    case FunctionPointer:
        t2 := s2.(FunctionPointer) or_return
        return is_same(t1^, t2^)
    }
    return false
}

is_same_type :: proc(t1, t2: Type) -> bool {
    return(
        is_same(t1.spec, t2.spec) &&
        t1.read_only == t2.read_only &&
        t1.write_only == t2.write_only &&
        is_same(t1.pointer_info, t2.pointer_info) &&
        is_same(t1.array_info, t2.array_info) \
    )
}

is_same_symbol :: proc(s1, s2: Symbol) -> bool {
    if s1.remap != s2.remap do return false

    switch v1 in s1.value {
    case Type:
        v2 := s2.value.(Type) or_return
        return is_same(v1, v2)
    case Function:
        v2 := s2.value.(Function) or_return
        return is_same(v1, v2)
    }
    return false
}

is_same :: proc {
    is_same_type,
    is_same_type_specifier,
    is_same_pointer_info,
    is_same_array_info,
    is_same_array,
    is_same_array_size,
    is_same_function,
    is_same_symbol,
    is_same_constant,
}

get_same_platforms :: proc(
    stone1: RunestoneWithFile,
    origin: om.OrderedMap(Platform, RunestoneWithFile),
    same_proc: #type proc(
        stone1, stone2: RunestoneWithFile,
        user_data: rawptr,
    ) -> bool,
    user_data: rawptr = nil,
) -> (
    plats: [dynamic]Platform,
) {
    append(&plats, stone1.platform)
    for entry2 in origin.data {
        plat2, stone2 := entry2.key, entry2.value
        if stone1.platform == plat2 do continue
        if same_proc(stone1, stone2, user_data) {
            append(&plats, stone2.platform)
        }
    }
    return
}

set_for_same_platforms :: proc(
    stone1: RunestoneWithFile,
    plats: [dynamic]Platform,
    len_origin: int,
    rc: ^Runecross,
    set_proc: #type proc(
        stone1: RunestoneWithFile,
        stone2: ^RunestoneWithFile,
        user_data: rawptr,
    ),
    user_data: rawptr = nil,
    allocator := context.allocator,
) {
    if len(plats) == len_origin {
        if len(plats) == 1 {
            rc.general.platform = plats[0]
            rc.general.file_path = stone1.file_path
        }
        set_proc(stone1, &rc.general, user_data)
        return
    }

    stone2_loop: for &stone2 in rc.cross {
        if len(stone2.plats) == len(plats) {
            for plat2 in stone2.plats {
                if !slice.contains(plats[:], plat2) {
                    continue stone2_loop
                }
            }

            if len(plats) == 1 {
                stone2.platform = plats[0]
                stone2.file_path = stone1.file_path
            }
            set_proc(stone1, &stone2.runestone, user_data)
            return
        }
    }

    stone2: RunestoneWithFile
    if len(plats) == 1 {
        stone2.platform = plats[0]
        stone2.file_path = stone1.file_path
    }
    set_proc(stone1, &stone2, user_data)

    context.allocator = allocator
    plats_copy := make([]Platform, len(plats), allocator = allocator)
    copy(plats_copy, plats[:])
    append(
        &rc.cross,
        PlatformRunestone{plats = plats_copy, runestone = stone2},
    )
}
