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

foreign libc {
    @(link_name = "environ")
    environ: [^]cstring
}

STDIN_FILENO :: 0
STDOUT_FILENO :: 1
STDERR_FILENO :: 2

Pid :: distinct i32

fork :: proc "contextless" () -> (Pid, bool) #optional_ok {
    pid := cast(i32)intrinsics.syscall(darwin.unix_offset_syscall(.fork))
    return Pid(pid), pid >= 0
}

execve :: proc "contextless" (
    name: cstring,
    argv: [^]cstring,
    env: [^]cstring,
) -> bool {
    return darwin.syscall_execve(name, argv, env) >= 0
}

dup2 :: proc "contextless" (
    from, to: os.Handle,
) -> (
    os.Handle,
    bool,
) #optional_ok {
    ret := cast(i32)intrinsics.syscall(
        darwin.unix_offset_syscall(.dup2),
        uintptr(from),
        uintptr(to),
    )
    return cast(os.Handle)ret, ret >= 0
}

pipe :: proc "contextless" () -> Maybe(RWPipe) {
    p: RWPipe = ---
    if darwin.syscall_pipe(cast([^]i32)&p) < 0 do return nil
    return p
}

wait4 :: proc "contextless" (
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
