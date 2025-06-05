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

package diff

import "core:log"
import os "core:os/os2"
import "core:testing"

expect_diff_files :: proc(
    t: ^testing.T,
    old_path, new_path: string,
    loc := #caller_location,
) -> bool {
    command: [dynamic]string
    defer delete(command)

    if program_installed("difft") {
        c := [?]string {
            "difft",
            "--display",
            "side-by-side-show-both",
            "--exit-code",
            "--color=always",
            old_path,
            new_path,
        }
        append(&command, ..c[:])
    } else if program_installed("diff") {
        c := [?]string {
            "diff",
            "-y",
            "--suppress-common-lines",
            old_path,
            new_path,
        }
        append(&command, ..c[:])
    } else {
        old, old_err := os.read_entire_file(old_path, context.allocator)
        if !testing.expect_value(t, old_err, nil) do return false
        defer delete(old)

        new, new_err := os.read_entire_file(new_path, context.allocator)
        if !testing.expect_value(t, new_err, nil) do return false
        defer delete(new)

        if !testing.expect_value(t, len(new), len(old)) ||
           !testing.expect_value(t, string(new), string(old)) {
            return false
        }

        return true
    }

    env, _ := os.environ(context.allocator)
    defer delete(env)
    defer for e in env do delete(e)

    diff_process := os.Process_Desc {
        command = command[:],
        env     = env,
    }

    state, stdout, stderr, exec_err := os.process_exec(
        diff_process,
        context.allocator,
    )
    if !testing.expect_value(t, exec_err, nil) do return false
    defer delete(stdout)
    defer delete(stderr)

    if !testing.expect(t, state.exited) {
        return false
    }

    if !state.success {
        if len(stderr) != 0 do log.errorf("{}\n{}\n\n", loc, string(stderr))
        if len(stdout) != 0 do log.errorf("{}\n{}\n\n", loc, string(stdout))
        return false
    }

    return true
}

@(private)
program_installed :: proc(prog_name: string) -> bool {
    PATH, found := os.lookup_env("PATH", context.allocator)
    if !found do return false
    defer delete(PATH)

    PATHs, err := os.split_path_list(PATH, context.allocator)
    if err != nil do return false
    defer delete(PATHs)
    defer for p in PATHs do delete(p)

    for p in PATHs {
        prog_path, join_err := os.join_path({p, prog_name}, context.allocator)
        if join_err != nil do continue
        defer delete(prog_path)

        if os.is_file(prog_path) {
            return true
        }
    }

    return false
}
