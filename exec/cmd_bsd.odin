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

// +build freebsd, openbsd, netbsd
package exec

import "core:os"
import "core:strings"
import "root:errors"

@(private)
ChildProcess :: struct {
    pid:    linux.Pid,
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
    pid, pid_err := fork()
    if pid_err != .NONE do return cp, errors.empty()

    if pid == 0 {
        if po, ok := pipeout.?; ok {
            if po.r != po.w do os.close(po.r)
            if !dup(po.w, STDOUT_FILENO) do return cp, errors.empty()
        }
        if pe, ok := pipeerr.?; ok {
            if pe.r != pe.w do os.close(pe.r)
            if !dup(pe.w, STDERR_FILENO) do return cp, errors.empty()
        }
        if pi, ok := pipein.?; ok {
            if pi.r != pi.w do os.close(pi.w)
            if !dup(pi.r, STDIN_FILENO) do return cp, errors.empty()
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

        e_err := execve(argv[0], raw_data(argv), raw_data(envp))
        assert(e_err == .NONE)
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
wait_for_child_process :: proc(child_process: ChildProcess) -> errors.Error {
    if _, w_err := linux.wait4(child_process.pid, child_process.status, nil, nil); w_err != .NONE do return errors.empty()
    return nil
}

@(private)
cleanup_child_process :: proc(_: ChildProcess) {
}

@(private)
get_exit_code :: proc(
    child_process: ChildProcess,
) -> (
    status: int,
    err: errors.Error,
) {
    if !linux.WIFEXITED(child_process.status^) do return 1, errors.empty()

    status = int(linux.WEXITSTATUS(child_process.status^))
    return
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
