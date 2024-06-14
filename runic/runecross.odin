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

import "core:slice"
import "root:errors"
import om "root:ordered_map"

// TODO: add file paths of runestones
// TODO: move to ordered map for cross
// TODO: memory management
Runecross :: struct {
    general: Runestone,
    cross:   map[Platform]Runestone,
}

cross_the_runes :: proc(
    stones: [dynamic]Runestone,
) -> (
    rc: Runecross,
    err: errors.Error,
) {
    errors.assert(len(stones) != 0, "no runestones specified") or_return
    if len(stones) == 1 {
        rc.general = stones[0]
        return
    }

    origin := make(map[Platform]Runestone)
    defer delete(origin)

    for stone in stones {
        if _, ok := origin[stone.platform]; ok {
            err = errors.message(
                "duplicate runestone for platform {}.{}",
                stone.platform.os,
                stone.platform.arch,
            )
            return
        }

        origin[stone.platform] = stone
    }

    half_stones := len(origin) / 2

    rc.general.types = om.make(string, Type)
    rc.general.symbols = om.make(string, Symbol)
    rc.general.constants = om.make(string, Constant)

    for plat1, stone1 in origin {
        {
            // TODO: don't always do this just when it's different for platforms
            stone2 := rc.cross[plat1]
            stone2.version = stone1.version
            stone2.platform = plat1
            stone2.lib_static = stone1.lib_static
            stone2.lib_shared = stone1.lib_shared
            rc.cross[plat1] = stone2
        }

        // types
        for entry1 in stone1.types.data {
            name1, type1 := entry1.key, entry1.value
            if om.contains(rc.general.types, name1) do continue

            same_platforms := 1
            for plat2, stone2 in origin {
                if plat1 == plat2 do continue

                if type2, ok := om.get(stone2.types, name1); ok {
                    if is_same(type1, type2) {
                        same_platforms += 1
                    }
                }
            }

            if same_platforms <= half_stones {
                stone2 := rc.cross[plat1]
                defer rc.cross[plat1] = stone2

                if stone2.types.indices == nil {
                    stone2.types = om.make(string, Type)
                }

                om.insert(&stone2.types, name1, type1)
            } else {
                om.insert(&rc.general.types, name1, type1)
            }
        }

        // symbols
        for entry1 in stone1.symbols.data {
            name1, symbol1 := entry1.key, entry1.value
            if symbol2, ok := om.get(rc.general.symbols, name1); ok {
                for alias in symbol1.aliases {
                    if !slice.contains(symbol2.aliases[:], alias) {
                        append(&symbol2.aliases, alias)
                    }
                }

                om.insert(&rc.general.symbols, name1, symbol2)
                continue
            }

            same_platforms := 1
            for plat2, stone2 in origin {
                if plat1 == plat2 do continue

                if symbol2, ok := om.get(stone2.symbols, name1); ok {
                    if is_same(symbol1, symbol2) {
                        same_platforms += 1
                    }
                }
            }

            if same_platforms <= half_stones {
                stone2 := rc.cross[plat1]
                defer rc.cross[plat1] = stone2

                if stone2.symbols.indices == nil {
                    stone2.symbols = om.make(string, Symbol)
                }

                om.insert(&stone2.symbols, name1, symbol1)
            } else {
                om.insert(&rc.general.symbols, name1, symbol1)
            }
        }

        // constants
        for entry1 in stone1.constants.data {
            name1, constant1 := entry1.key, entry1.value
            if om.contains(rc.general.constants, name1) do continue

            same_platforms := 1
            for plat2, stone2 in origin {
                if plat1 == plat2 do continue

                if constant2, ok := om.get(stone2.constants, name1); ok {
                    if is_same(constant1, constant2) {
                        same_platforms += 1
                    }
                }
            }

            if same_platforms <= half_stones {
                stone2 := rc.cross[plat1]
                defer rc.cross[plat1] = stone2

                if stone2.constants.indices == nil {
                    stone2.constants = om.make(string, Constant)
                }

                om.insert(&stone2.constants, name1, constant1)
            } else {
                om.insert(&rc.general.constants, name1, constant1)
            }
        }
    }

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
