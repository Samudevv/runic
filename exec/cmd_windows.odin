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

#+build windows
package exec

import "core:os"
import win32 "core:sys/windows"
import "root:errors"

@(private)
ChildProcess :: win32.PROCESS_INFORMATION

@(private)
pipe :: proc() -> Maybe(RWPipe) {
    using win32

    // NOTE: sus
    saAttr: SECURITY_ATTRIBUTES
    saAttr.nLength = size_of(saAttr)
    saAttr.bInheritHandle = TRUE
    saAttr.lpSecurityDescriptor = nil

    p: RWPipe = ---
    if CreatePipe(cast(^HANDLE)&p.r, cast(^HANDLE)&p.w, &saAttr, 0) != TRUE do return nil
    return p
}

@(private)
start_child_process :: proc(
    abs_name: string,
    args: []string,
    pipeout, pipeerr, pipein: Maybe(RWPipe),
    env: Environ,
    allocator := context.allocator,
) -> (
    pi: ChildProcess,
    err: errors.Error,
) {
    using win32

    si: STARTUPINFOW

    si.cb = size_of(si)
    si.dwFlags |= STARTF_USESTDHANDLES

    if po, ok := pipeout.?; ok {
        si.hStdOutput = HANDLE(po.w)
        if po.r != po.w do SetHandleInformation(HANDLE(po.r), HANDLE_FLAG_INHERIT, 0)
    } else {
        si.hStdOutput = HANDLE(os.stdout)
    }

    if pe, ok := pipeerr.?; ok {
        si.hStdError = HANDLE(pe.w)
        if pe.r != pe.w do SetHandleInformation(HANDLE(pe.r), HANDLE_FLAG_INHERIT, 0)
    } else {
        si.hStdError = HANDLE(os.stderr)
    }

    if pipei, ok := pipein.?; ok {
        si.hStdInput = HANDLE(pipei.r)
        if pipei.r != pipei.w do SetHandleInformation(HANDLE(pipei.w), HANDLE_FLAG_INHERIT, 0)
    } else {
        si.hStdInput = HANDLE(os.stdin)
    }

    cmd_call := make([dynamic]WCHAR, allocator)

    append(&cmd_call, '"')
    for r in abs_name {
        append(&cmd_call, WCHAR(r))
    }
    append(&cmd_call, '"')

    for arg in args {
        append(&cmd_call, ' ')
        for r in arg {
            append(&cmd_call, WCHAR(r))
        }
    }
    append(&cmd_call, 0)

    environ: Maybe([dynamic]WCHAR)

    switch e in env {
    case Env:
        switch e {
        case .Parent:
        case .None:
            envi := make([dynamic]WCHAR, allocator)
            append(&envi, 0)
            environ = envi
        }
    case []string:
        envi := make([dynamic]WCHAR, allocator)
        for s in e {
            for r in s {
                append(&envi, WCHAR(r))
            }
            append(&envi, 0)
        }
        append(&envi, 0)
        environ = envi
    case ParentAnd:
        err = errors.message("ParentAnd for env is not implemented")
        return
    }

    if CreateProcessW(nil, raw_data(cmd_call), nil, nil, TRUE, CREATE_UNICODE_ENVIRONMENT if environ != nil else 0, raw_data(environ.?) if environ != nil else nil, nil, &si, &pi) != TRUE do return pi, errors.empty()

    if po, ok := pipeout.?; ok && po.r != po.w do os.close(po.w)
    if pe, ok := pipeerr.?; ok && pe.r != pe.w do os.close(pe.w)
    if pipei, ok := pipein.?; ok && pipei.r != pipei.w do os.close(pipei.r)

    return
}

@(private)
wait_for_child_process :: proc(pi: ChildProcess) -> errors.Error {
    win32.WaitForSingleObject(pi.hProcess, win32.INFINITE)
    return nil
}

@(private)
cleanup_child_process :: proc(pi: ChildProcess) {
    win32.CloseHandle(pi.hProcess)
    win32.CloseHandle(pi.hThread)
}

@(private)
get_exit_code :: proc(pi: ChildProcess) -> (status: int, err: errors.Error) {
    exitCode: win32.DWORD = ---
    if win32.GetExitCodeProcess(pi.hProcess, &exitCode) != win32.TRUE do return 1, errors.empty()

    status = int(exitCode)
    return
}

@(private)
executable_paths :: proc(
    allocator := context.allocator,
) -> (
    []string,
    bool,
) #optional_ok {
    paths_var, ok := paths_of_PATH(allocator)
    if !ok do return {}, false

    paths := make([dynamic]string, allocator)
    append(&paths, ..paths_var)
    append(&paths, os.get_current_directory(allocator))

    return paths[:], true
}
