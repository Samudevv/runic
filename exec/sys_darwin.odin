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

import "base:intrinsics"
import "core:os"
import "core:sys/darwin"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
    @(link_name = "environ")
    environ: [^]cstring

    @(link_name = "fork")
    cfork :: proc() -> i32 ---

    @(link_name = "pipe")
    cpipe :: proc(pipedd: ^RWPipe) -> i32 ---

    @(link_name = "dup2")
    cdup2 :: proc(from, to: os.Handle) -> i32 ---
}

STDIN_FILENO :: 0
STDOUT_FILENO :: 1
STDERR_FILENO :: 2

Pid :: distinct i32

fork :: #force_inline proc "contextless" () -> (Pid, bool) #optional_ok {
    pid := cfork()
    return Pid(pid), pid >= 0
}

execve :: #force_inline proc "contextless" (
    name: cstring,
    argv: [^]cstring,
    env: [^]cstring,
) -> bool {
    return darwin.syscall_execve(name, argv, env) >= 0
}

dup2 :: #force_inline proc "contextless" (from, to: os.Handle) -> bool {
    return cdup2(from, to) >= 0
}

pipe :: #force_inline proc "contextless" () -> Maybe(RWPipe) {
    p: RWPipe = ---
    if cpipe(&p) < 0 do return nil
    return p
}

wait4 :: #force_inline proc "contextless" (
    pid: Pid,
    status: ^u32,
    options: i32 = 0,
    rusage: rawptr = nil,
) -> (
    Pid,
    bool,
) #optional_ok {
    ret := cast(i32)intrinsics.syscall(
        darwin.unix_offset_syscall(.wait4),
        uintptr(pid),
        uintptr(status),
        uintptr(options),
        uintptr(rusage),
    )
    return Pid(ret), ret >= 0
}
