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

#+build linux
#+private
package exec

import "core:os"
import "core:sys/linux"

foreign import libc "system:c"

foreign libc {
    @(link_name = "environ")
    environ: [^]cstring
}

STDIN_FILENO :: 0
STDOUT_FILENO :: 1
STDERR_FILENO :: 2

/*
	Creates a copy of the running process.
	Available since Linux 1.0.
*/
fork :: proc "contextless" () -> (linux.Pid, linux.Errno) {
    when ODIN_ARCH == .arm64 {
        ret := linux.syscall(
            linux.SYS_clone,
            u64(linux.Signal.SIGCHLD),
            cast(rawptr)nil,
            cast(rawptr)nil,
            cast(rawptr)nil,
            u64(0),
        )
        return errno_unwrap(ret, linux.Pid)
    } else {
        ret := linux.syscall(linux.SYS_fork)
        return errno_unwrap(ret, linux.Pid)
    }
}

/*
	Replace the current process with another program.
	Available since Linux 1.0.
	On ARM64 available since Linux 3.19.
*/
execve :: proc "contextless" (
    name: cstring,
    argv: [^]cstring,
    envp: [^]cstring,
) -> linux.Errno {
    when ODIN_ARCH != .arm64 {
        ret := linux.syscall(
            linux.SYS_execve,
            cast(rawptr)name,
            cast(rawptr)argv,
            cast(rawptr)envp,
        )
        return linux.Errno(-ret)
    } else {
        ret := linux.syscall(
            linux.SYS_execveat,
            linux.AT_FDCWD,
            cast(rawptr)name,
            cast(rawptr)argv,
            cast(rawptr)envp,
            i32(0),
        )
        return linux.Errno(-ret)
    }
}

dup :: proc "contextless" (hd: os.Handle, idx: linux.Fd) -> bool {
    _, err := linux.dup2(cast(linux.Fd)hd, idx)
    return err == .NONE
}

pipe :: proc "contextless" () -> Maybe(RWPipe) {
    p: RWPipe = ---
    if p_err := linux.pipe2(transmute(^[2]linux.Fd)&p, nil); p_err != .NONE do return nil
    return p
}

/* This has been copied from the core:sys/linux package from helpers.odin */
errno_unwrap :: #force_inline proc "contextless" (
    ret: $P,
    $T: typeid,
) -> (
    T,
    linux.Errno,
) {
    if ret < 0 {
        default_value: T
        return default_value, linux.Errno(-ret)
    } else {
        return cast(T)ret, linux.Errno(.NONE)
    }
}
