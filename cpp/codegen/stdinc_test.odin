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

import "core:os"
import "core:path/filepath"
import "core:testing"
import "root:runic"

@(test)
test_cpp_stdinc :: proc(t: ^testing.T) {
    using testing

    plat := runic.Platform{.Linux, .x86_64}

    gen_dir, gen_dir_ok := system_includes_gen_dir(plat)
    if !expect(t, gen_dir_ok) do return
    defer delete(gen_dir)

    ok := generate_system_includes(gen_dir)
    if !expect(t, ok) do return

    for file_name in SYSTEM_INCLUDE_FILES {
        file_path := filepath.join({gen_dir, file_name})
        defer delete(file_path)

        fd, err := os.open(file_path, os.O_RDONLY)
        expect_value(t, err, nil)
        os.close(fd)
    }

    delete_system_includes(gen_dir)

    expect(t, !(os.exists(gen_dir) || os.is_dir(gen_dir)))
}

