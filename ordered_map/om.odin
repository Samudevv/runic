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

package ordered_map

import "base:runtime"

OrderedMap :: struct($Key, $Value: typeid) {
    indices: map[Key]int,
    data:    [dynamic]Entry(Key, Value),
}

Entry :: struct($Key, $Value: typeid) {
    key:   Key,
    value: Value,
}

make :: #force_inline proc(
    $Key, $Value: typeid,
    #any_int capacity: int = 1 << runtime.MAP_MIN_LOG2_CAPACITY,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    m: OrderedMap(Key, Value),
    err: runtime.Allocator_Error,
) #optional_allocator_error {
    m.indices = make_map_cap(map[Key]int, capacity, allocator, loc) or_return
    m.data = make_dynamic_array_len_cap(
        [dynamic]Entry(Key, Value),
        allocator = allocator,
        cap = capacity,
        len = 0,
        loc = loc,
    ) or_return
    return
}

insert :: #force_inline proc(
    using m: ^OrderedMap($Key, $Value),
    key: Key,
    value: Value,
    loc := #caller_location,
) {
    if idx, ok := indices[key]; ok {
        entry := &data[idx]
        entry.value = value
    } else {
        idx = len(data)
        indices[key] = idx
        append(&data, Entry(Key, Value){key = key, value = value}, loc = loc)
    }
}

replace :: #force_inline proc(
    using m: ^OrderedMap($Key, $Value),
    old_key: Key,
    new_key: Key,
    value: Value,
) {
    if idx, ok := indices[old_key]; ok {
        runtime.delete_key(&indices, old_key)
        data[idx].key = new_key
        data[idx].value = value
        indices[new_key] = idx
    } else {
        insert(m, new_key, value)
    }
}

get :: #force_inline proc(
    using m: OrderedMap($Key, $Value),
    key: Key,
) -> (
    value: Value,
    ok: bool,
) #optional_ok {
    idx: int = ---
    if idx, ok = indices[key]; ok {
        value = data[idx].value
    }
    return
}

delete :: #force_inline proc(
    using m: OrderedMap($Key, $Value),
    loc := #caller_location,
) -> runtime.Allocator_Error {
    delete_map(m.indices, loc) or_return
    delete_dynamic_array(m.data, loc) or_return
    return .None
}

delete_key :: #force_inline proc(
    using m: ^OrderedMap($Key, $Value),
    key: Key,
    loc := #caller_location,
) {
    idx, ok := indices[key]
    if !ok do return

    ordered_remove(&data, idx, loc)
    runtime.delete_key(&indices, key)

    for i, v in indices {
        if v > idx {
            indices[i] = v - 1
        }
    }
}

length :: #force_inline proc(using m: OrderedMap($Key, $Value)) -> int {
    return len(data)
}

contains :: #force_inline proc(
    using m: OrderedMap($Key, $Value),
    key: Key,
) -> bool {
    return key in indices
}

extend :: #force_inline proc(
    dst: ^OrderedMap($Key, $Value),
    src: OrderedMap(Key, Value),
    loc := #caller_location,
) {
    for entry in src.data {
        key, value := entry.key, entry.value
        insert(dst, key, value, loc = loc)
    }
}

index :: #force_inline proc(
    using m: OrderedMap($Key, $Value),
    key: Key,
) -> (
    idx: int,
    ok: bool,
) #optional_ok {
    return indices[key]
}

move :: #force_inline proc(
    using m: ^OrderedMap($Key, $Value),
    key: Key,
    dst: int,
) {
    assert(dst >= 0 && dst < len(data))

    src, ok := indices[key]
    if !ok do return

    tmp := data[src].value

    if dst < src {
        for i := src - 1; i >= dst; i -= 1 {
            i_key := data[i].key
            data[i + 1] = data[i]
            indices[i_key] = i + 1
        }
    } else if dst > src {
        for i := src + 1; i <= dst; i += 1 {
            i_key := data[i].key
            data[i - 1] = data[i]
            indices[i_key] = i - 1
        }
    } else {
        return
    }

    data[dst].key = key
    data[dst].value = tmp
    indices[key] = dst
}

