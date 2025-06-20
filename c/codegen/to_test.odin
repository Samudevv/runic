#+ feature dynamic-literals
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

package c_codegen

import "core:os"
import "core:strings"
import "core:testing"
import "root:diff"
import "root:errors"
import "root:runic"

@(test)
test_c_to :: proc(t: ^testing.T) {
    using testing

    LINUX_RUNESTONE :: `
version = 0

os = Linux
arch = x86_64

[lib]
static = libfoo.a

[constants]
MAX_ARRAY_SIZE = 4096 #Untyped
MAX_ARRAY_CAP = 4096 #Untyped

[extern]
wl_output = "shared/wayland/src/wayland-client.h" #Untyped
SDL_Event = "shared/sdl2/SDL/SDL_Event.h" #Struct event_type #SInt32

[types]
my_size_type = #UInt64
Window = #Struct name #String width #UInt32 height #UInt32
Array = #Struct len my_size_type cap my_size_type els #UInt32 #Attr Ptr 1 #AttrEnd

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.create_array = Array size my_size_type
var.linux_globals = Array


`


    WINDOWS_RUNESTONE :: `
version = 0

os = Windows
arch = x86_64

[lib]
static = foo.lib

[constants]
MAX_ARRAY_SIZE = 2048 #Untyped
MAX_ARRAY_CAP = 4096 #Untyped

[extern]
wl_output = "shared/wayland/src/wayland-client.h" #Untyped
SDL_Event = "shared/sdl2/SDL/SDL_Event.h" #Struct event_type #SInt32

[types]
my_size_type = #UInt32
Window = #Struct name #String width #UInt32 height #UInt32
Array = #Struct len my_size_type cap my_size_type els #UInt32 #Attr Ptr 1 #AttrEnd

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.create_array = Array size my_size_type
var.windows_globals = Array

`


    MACOS_RUNESTONE :: `
version = 0

os = Macos
arch = arm64

[lib]
static = libfoo.a

[constants]
MAX_ARRAY_SIZE = 4096 #Untyped
MAX_ARRAY_CAP = 4096 #Untyped

[extern]
wl_output = "shared/wayland/src/wayland-client.h" #Untyped
SDL_Event = "shared/sdl2/SDL/SDL_Event.h" #Struct event_type #SInt32

[types]
my_size_type = #SInt64
Window = #Struct name #String width #UInt32 height #UInt32
Array = #Struct len my_size_type cap my_size_type els #UInt32 #Attr Ptr 1 #AttrEnd

[symbols]
func.create_window = Window #Attr Ptr 1 #AttrEnd name #String width #UInt32 height #UInt32
func.create_array = Array size my_size_type
var.macos_globals = Array

`


    rn := runic.To {
        language = "c",
        extern = {
            sources = {"shared/wayland/src/*" = "<wayland/wayland-client.h>"},
        },
    }

    defer delete(rn.extern.sources)

    linux_rd, windows_rd, macos_rd: strings.Reader
    linux_rs, linux_arm_rs, windows_rs, macos_rs: runic.Runestone =
        ---, ---, ---, ---
    rs_err: errors.Error = ---

    strings.reader_init(&linux_rd, string(LINUX_RUNESTONE))
    strings.reader_init(&windows_rd, string(WINDOWS_RUNESTONE))
    strings.reader_init(&macos_rd, string(MACOS_RUNESTONE))

    linux_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&linux_rd),
        "/linux",
    )
    if !expect_value(t, rs_err, nil) do return
    defer runic.runestone_destroy(&linux_rs)

    windows_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&windows_rd),
        "/windows",
    )
    if !expect_value(t, rs_err, nil) do return
    defer runic.runestone_destroy(&windows_rs)

    macos_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&macos_rd),
        "/macos",
    )
    if !expect_value(t, rs_err, nil) do return
    defer runic.runestone_destroy(&macos_rs)

    strings.reader_init(&linux_rd, string(LINUX_RUNESTONE))
    linux_arm_rs, rs_err = runic.parse_runestone(
        strings.reader_to_stream(&linux_rd),
        "/linux_arm",
    )
    if !expect_value(t, rs_err, nil) do return
    linux_arm_rs.platform.arch = .arm64
    defer runic.runestone_destroy(&linux_arm_rs)

    runic.to_preprocess_runestone(&linux_rs, rn, C_RESERVED)
    runic.to_preprocess_runestone(&windows_rs, rn, C_RESERVED)
    runic.to_preprocess_runestone(&macos_rs, rn, C_RESERVED)
    runic.to_preprocess_runestone(&linux_arm_rs, rn, C_RESERVED)

    runestones := []runic.Runestone {
        linux_rs,
        windows_rs,
        macos_rs,
        linux_arm_rs,
    }
    file_paths := []string{"/linux", "/windows", "/macos", "/linux_arm"}

    rc, rc_err := runic.cross_the_runes(file_paths, runestones)
    if !expect_value(t, rc_err, nil) do return
    defer runic.runecross_destroy(&rc)

    out_file, os_err := os.open(
        "test_data/to_c_test.h",
        os.O_CREATE | os.O_WRONLY | os.O_TRUNC,
        0o644,
    )
    if !expect_value(t, os_err, nil) do return
    defer os.close(out_file)

    err := generate_bindings(rc, rn, os.stream_from_handle(out_file))
    if !expect_value(t, err, nil) do return

    data, os_ok := os.read_entire_file("test_data/to_c_test.h")
    if !expect(t, os_ok) do return
    defer delete(data)

    EXPECTED_HEADER :: `#pragma once

#ifdef _MSC_VER
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#endif

#include <stddef.h>
#include <stdint.h>

#include <wayland/wayland-client.h>

#define OS_LINUX (defined(__linux__) || defined(__linux) || defined(linux))
#define OS_WINDOWS (defined(_WIN32) || defined(_WIN16) || defined(_WIN64))
#define OS_MACOS (defined(__APPLE__) && (defined(macintosh) || defined(Macintosh) || defined(__MACH__)))
#define ARCH_X86_64 (defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64))
#define ARCH_ARM64 (defined(__arm__) && defined(__aarch64__))

#if OS_LINUX || (OS_MACOS && ARCH_ARM64)
#define MAX_ARRAY_SIZE 4096

#endif
#if (OS_WINDOWS && ARCH_X86_64)
#define MAX_ARRAY_SIZE 2048

#endif
#define MAX_ARRAY_CAP 4096

typedef struct SDL_Event {
    int32_t event_type;
} SDL_Event;


#if (OS_MACOS && ARCH_ARM64)
typedef int64_t my_size_type;

#endif
#if (OS_WINDOWS && ARCH_X86_64)
typedef uint32_t my_size_type;

#endif
#if OS_LINUX
typedef uint64_t my_size_type;

#endif
typedef struct Window {
    char*    name;
    uint32_t width;
    uint32_t height;
} Window;

typedef struct Array {
    my_size_type len;
    my_size_type cap;
    uint32_t*    els;
} Array;


#if (OS_MACOS && ARCH_ARM64)
extern Array macos_globals;

#endif
#if (OS_WINDOWS && ARCH_X86_64)
extern Array windows_globals;

#endif
#if OS_LINUX
extern Array linux_globals;

#endif

extern struct Window* create_window(char* name, uint32_t width, uint32_t height);
extern struct Array create_array(my_size_type size);

`


    diff.expect_diff_strings(t, EXPECTED_HEADER, string(data))
}
