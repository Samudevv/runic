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
// +private
package exec

import "base:intrinsics"
import "core:os"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
    @(link_name = "environ")
    environ: [^]cstring

    @(link_name = "pipe")
    cpipe :: proc(pipedd: ^RWPipe) -> i32 ---
}

SYS_fork :: uintptr(2)
SYS_wait4 :: uintptr(7)
SYS_dup2 :: uintptr(90)
SYS_execve :: uintptr(59)

STDIN_FILENO :: 0
STDOUT_FILENO :: 1
STDERR_FILENO :: 2

Pid :: distinct i32

fork :: proc "contextless" () -> (Pid, bool) #optional_ok {
    ret := cast(i32)intrinsics.syscall(SYS_fork)
    return Pid(ret), ret >= 0
}

execve :: proc "contextless" (
    name: cstring,
    argv: [^]cstring,
    envp: [^]cstring,
) -> bool {
    ret := cast(i32)intrinsics.syscall(
        SYS_execve,
        uintptr(cast(rawptr)name),
        uintptr(argv),
        uintptr(envp),
    )
    return ret >= 0
}

dup2 :: proc "contextless" (from, to: os.Handle) -> bool {
    ret := cast(i32)intrinsics.syscall(SYS_dup2, uintptr(from), uintptr(to))
    return ret >= 0
}

pipe :: proc "contextless" () -> Maybe(RWPipe) {
    p: RWPipe = ---
    ret := cpipe(&p)
    if ret < 0 do return nil
    return p
}

wait4 :: proc "contextless" (
    pid: Pid,
    status: ^u32,
    options: i32 = 0,
    rusage: rawptr = nil,
) -> bool {
    ret := cast(i32)intrinsics.syscall(
        SYS_wait4,
        uintptr(pid),
        uintptr(status),
        uintptr(options),
        uintptr(rusage),
    )
    return ret >= 0
}
