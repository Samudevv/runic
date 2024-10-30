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

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "root:runic"

@(private)
SYSTEM_INCLUDE_FILES :: [?]string {
    "aio.h",
    "alloca.h",
    "ar.h",
    "arpa/ftp.h",
    "arpa/inet.h",
    "arpa/nameser.h",
    "arpa/nameser_compat.h",
    "arpa/telnet.h",
    "arpa/tftp.h",
    "assert.h",
    "byteswap.h",
    "complex.h",
    "cpio.h",
    "crypt.h",
    "ctype.h",
    "dirent.h",
    "dlfcn.h",
    "elf.h",
    "endian.h",
    "err.h",
    "errno.h",
    "fcntl.h",
    "features.h",
    "fenv.h",
    "float.h",
    "fmtmsg.h",
    "fnmatch.h",
    "ftw.h",
    "getopt.h",
    "glob.h",
    "grp.h",
    "iconv.h",
    "ifaddrs.h",
    "inttypes.h",
    "iso646.h",
    "langinfo.h",
    "lastlog.h",
    "libgen.h",
    "libintl.h",
    "limits.h",
    "link.h",
    "locale.h",
    "malloc.h",
    "math.h",
    "memory.h",
    "mntent.h",
    "monetary.h",
    "mqueue.h",
    "net/ethernet.h",
    "net/if.h",
    "net/if_arp.h",
    "net/route.h",
    "netdb.h",
    "netinet/ether.h",
    "netinet/icmp6.h",
    "netinet/if_ether.h",
    "netinet/igmp.h",
    "netinet/in.h",
    "netinet/in_systm.h",
    "netinet/ip.h",
    "netinet/ip6.h",
    "netinet/ip_icmp.h",
    "netinet/tcp.h",
    "netinet/udp.h",
    "netpacket/packet.h",
    "nl_types.h",
    "paths.h",
    "poll.h",
    "pthread.h",
    "pty.h",
    "pwd.h",
    "regex.h",
    "resolv.h",
    "sched.h",
    "scsi/scsi.h",
    "scsi/scsi_ioctl.h",
    "scsi/sg.h",
    "search.h",
    "semaphore.h",
    "setjmp.h",
    "shadow.h",
    "signal.h",
    "spawn.h",
    "stdalign.h",
    "stdarg.h",
    "stdbool.h",
    "stdc-predef.h",
    "stddef.h",
    "stdint.h",
    "stdio.h",
    "stdio_ext.h",
    "stdlib.h",
    "stdnoreturn.h",
    "string.h",
    "strings.h",
    "stropts.h",
    "sys/acct.h",
    "sys/auxv.h",
    "sys/cachectl.h",
    "sys/dir.h",
    "sys/epoll.h",
    "sys/errno.h",
    "sys/eventfd.h",
    "sys/fanotify.h",
    "sys/fcntl.h",
    "sys/file.h",
    "sys/fsuid.h",
    "sys/inotify.h",
    "sys/io.h",
    "sys/ioctl.h",
    "sys/ipc.h",
    "sys/kd.h",
    "sys/klog.h",
    "sys/membarrier.h",
    "sys/mman.h",
    "sys/mount.h",
    "sys/msg.h",
    "sys/mtio.h",
    "sys/param.h",
    "sys/personality.h",
    "sys/poll.h",
    "sys/prctl.h",
    "sys/procfs.h",
    "sys/ptrace.h",
    "sys/quota.h",
    "sys/random.h",
    "sys/reboot.h",
    "sys/reg.h",
    "sys/resource.h",
    "sys/select.h",
    "sys/sem.h",
    "sys/sendfile.h",
    "sys/shm.h",
    "sys/signal.h",
    "sys/signalfd.h",
    "sys/socket.h",
    "sys/soundcard.h",
    "sys/stat.h",
    "sys/statfs.h",
    "sys/statvfs.h",
    "sys/stropts.h",
    "sys/swap.h",
    "sys/syscall.h",
    "sys/sysinfo.h",
    "sys/syslog.h",
    "sys/sysmacros.h",
    "sys/termios.h",
    "sys/time.h",
    "sys/timeb.h",
    "sys/timerfd.h",
    "sys/times.h",
    "sys/timex.h",
    "sys/ttydefaults.h",
    "sys/types.h",
    "sys/ucontext.h",
    "sys/uio.h",
    "sys/un.h",
    "sys/user.h",
    "sys/utsname.h",
    "sys/vfs.h",
    "sys/vt.h",
    "sys/wait.h",
    "sys/xattr.h",
    "syscall.h",
    "sysexits.h",
    "syslog.h",
    "tar.h",
    "termios.h",
    "tgmath.h",
    "threads.h",
    "time.h",
    "uchar.h",
    "ucontext.h",
    "ulimit.h",
    "unistd.h",
    "utime.h",
    "utmp.h",
    "utmpx.h",
    "values.h",
    "wait.h",
    "wchar.h",
    "wctype.h",
    "wordexp.h",
}

when ODIN_OS == .Windows {
    SYSTEM_INCLUDE_GEN_DIR :: "C:\\temp\\runic_system_includes\\"
} else {
    SYSTEM_INCLUDE_GEN_DIR :: "/tmp/runic_system_includes/"
}

system_includes_gen_dir :: proc(
    plat: runic.Platform,
    allocator := context.allocator,
) -> (
    gen_dir: string,
    ok: bool,
) #optional_ok {
    os_arch_name := fmt.aprintf(
        "{}_{}",
        plat.os,
        plat.arch,
        allocator = allocator,
    )
    defer delete(os_arch_name, allocator = allocator)

    // Max 100 attempts
    for _ in 0 ..< 100 {
        // At max six digits
        id := rand.uint32() % 1000000
        folder_name := fmt.aprintf(
            "{}-{:06d}",
            os_arch_name,
            id,
            allocator = allocator,
        )
        gen_dir = filepath.join(
            {SYSTEM_INCLUDE_GEN_DIR, folder_name},
            allocator,
        )
        delete(folder_name, allocator = allocator)

        err := make_directory_parents(gen_dir)
        #partial switch errno in err {
        case nil:
            ok = true
            return
        case:
            delete(gen_dir, allocator = allocator)
            if plat_err, plat_err_ok := os.is_platform_error(errno);
               plat_err_ok {
                when ODIN_OS == .Windows {
                    is_already_exists :=
                        plat_err == i32(os.ERROR_ALREADY_EXISTS)
                } else {
                    is_already_exists := plat_err == i32(os.EEXIST)
                }

                if is_already_exists do continue
            }
            ok = false
            return
        }
    }

    ok = false
    return
}

generate_system_includes :: proc(gen_dir: string) -> bool {
    arena: runtime.Arena
    alloc_err := runtime.arena_init(&arena, 0, context.allocator)
    if alloc_err != .None do return false
    defer runtime.arena_destroy(&arena)

    context.allocator = runtime.arena_allocator(&arena)

    for file_name in SYSTEM_INCLUDE_FILES {
        file_path := filepath.join({gen_dir, file_name})
        dir := filepath.dir(file_path)
        if err := make_directory_parents(dir); err != nil do return false

        fd, err := os.open(file_path, os.O_CREATE | os.O_TRUNC, 0o644)
        if err != nil do return false
        os.close(fd)
    }

    return true
}

delete_system_includes :: proc(gen_dir: string) {
    arena: runtime.Arena
    alloc_err := runtime.arena_init(&arena, 0, context.allocator)
    if alloc_err != .None do return
    defer runtime.arena_destroy(&arena)

    context.allocator = runtime.arena_allocator(&arena)

    walk_proc := proc(
        info: os.File_Info,
        in_err: os.Error,
        user_data: rawptr,
    ) -> (
        err: os.Error,
        skip_dir: bool,
    ) {
        if !info.is_dir {
            os.remove(info.fullpath)
        } else {
            remove_directory(info.fullpath)
        }

        return
    }

    for os.is_dir(gen_dir) {
        filepath.walk(gen_dir, walk_proc, nil)
    }
}

@(private = "file")
make_directory_parents :: proc(path: string) -> os.Error {
    // An arena is necessary because filepath.dir can allocate memory
    arena: runtime.Arena
    defer runtime.arena_destroy(&arena)
    runtime.arena_init(&arena, 0, context.allocator) or_return
    context.allocator = runtime.arena_allocator(&arena)

    dir := filepath.dir(path)
    if dir != "." && dir != "/" {
        if err := make_directory_parents(dir); err != nil do return err
    }
    if !os.is_dir(path) {
        return os.make_directory(path, 0o755)
    }

    return nil
}

