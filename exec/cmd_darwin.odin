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

package exec

import "core:os"
import "core:strings"
import "root:errors"

@(private)
ChildProcess :: struct {
    pid:    Pid,
    status: ^u32,
}

@(private)
start_child_process :: proc(
    abs_name: string,
    args: []string,
    pipeout, pipeerr, pipein: Maybe(RWPipe),
    env: Environ,
    allocator := context.allocator,
) -> (
    cp: ChildProcess,
    err: errors.Error,
) {
    pid, fork_ok := fork()
    if !fork_ok do return cp, errors.empty()

    if pid == 0 {
        if po, ok := pipeout.?; ok {
            if po.r != po.w do os.close(po.r)
            if _, dup2_ok := dup2(po.w, STDOUT_FILENO); !dup2_ok do return cp, errors.empty()
        }
        if pe, ok := pipeerr.?; ok {
            if pe.r != pe.w do os.close(pe.r)
            if _, dup2_ok := dup2(pe.w, STDERR_FILENO); !dup2_ok do return cp, errors.empty()
        }
        if pi, ok := pipein.?; ok {
            if pi.r != pi.w do os.close(pi.w)
            if _, dup2_ok := dup2(pi.r, STDIN_FILENO); !dup2_ok do return cp, errors.empty()
        }

        argv := make([]cstring, len(args) + 2, allocator)
        argv[0] = strings.clone_to_cstring(abs_name, allocator)
        for _, i in args {
            argv[i + 1] = strings.clone_to_cstring(args[i], allocator)
        }
        argv[len(argv) - 1] = nil

        os_env: []string = nil
        envp: []cstring = nil
        switch e in env {
        case Env:
            switch e {
            case .Parent:
                environ_count: int
                for ;; environ_count += 1 do if environ[environ_count] == nil do break
                envp = environ[:environ_count]
            case .None:
            }
        case []string:
            os_env = e
        case ParentAnd:
            os_dyn_env := make([dynamic]string, allocator)
            for i := 0;; i += 1 {
                ev := environ[i]
                if ev == nil do break
                append(&os_dyn_env, strings.clone_from_cstring(ev, allocator))
            }
            append(&os_dyn_env, ..e.vars)
            os_env = os_dyn_env[:]
        }

        if os_env != nil {
            envp = make([]cstring, len(os_env) + 1, allocator)
            for ev, i in os_env {
                envp[i] = strings.clone_to_cstring(ev, allocator)
            }
            envp[len(envp) - 1] = nil
        }

        execve_ok := execve(argv[0], raw_data(argv), raw_data(envp))
        assert(execve_ok)
        return cp, errors.empty()
    }

    if po, ok := pipeout.?; ok && po.r != po.w do os.close(po.w)
    if pe, ok := pipeerr.?; ok && pe.r != pe.w do os.close(pe.w)
    if pi, ok := pipein.?; ok && pi.r != pi.w do os.close(pi.r)

    cp.pid = pid
    cp.status = new(u32, allocator)
    return
}

@(private)
wait_for_child_process :: proc(cp: ChildProcess) -> errors.Error {
    if _, wait4_ok := wait4(cp.pid, cp.status); !wait4_ok do return errors.empty()
    return nil
}

@(private)
cleanup_child_process :: proc(_: ChildProcess) {
}

@(private)
get_exit_code :: proc(cp: ChildProcess) -> (status: int, err: errors.Error) {
    if cp.status^ & 0x7f != 0 do return 1, errors.empty()
    return int((cp.status^ & 0xff00) >> 8), nil
}

@(private)
executable_paths :: proc(
    allocator := context.allocator,
) -> (
    []string,
    bool,
) #optional_ok {
    return paths_of_PATH(allocator)
}
