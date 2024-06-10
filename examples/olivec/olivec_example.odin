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

package main

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "olivec"
import stb "vendor:stb/image"

when ODIN_OS ==
    .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD {
    foreign import olivec2 "system:libolivec.a"
} else when ODIN_OS == .Windows {
    foreign import olivec2 "system:olivec.lib"
} else when ODIN_OS == .Darwin {
    foreign import olivec2 "system:olivec"
}

foreign olivec2 {
    @(link_name = "export_olivec_default_font")
    olivec_default_font :: proc() -> olivec.Font ---
}


WIDTH :: 1024
HEIGHT :: 1024

main :: proc() {
    pixels := make([dynamic]u32, WIDTH * HEIGHT)
    defer delete(pixels)

    c := olivec.canvas(raw_data(pixels), WIDTH, HEIGHT, WIDTH)

    olivec.fill(c, 0xFFFFFFFF)
    olivec.circle(c, WIDTH / 2, HEIGHT / 2, WIDTH / 2 - 20, 0xFFFF0000)
    olivec.triangle(
        c,
        WIDTH / 2 - 300,
        HEIGHT / 2,
        WIDTH / 2,
        HEIGHT / 2 - 300,
        WIDTH / 2 + 300,
        HEIGHT / 2,
        0xFF000000,
    )
    olivec.triangle(
        c,
        WIDTH / 2 - 300,
        HEIGHT / 2,
        WIDTH / 2,
        HEIGHT / 2 + 300,
        WIDTH / 2 + 300,
        HEIGHT / 2,
        0xFF000000,
    )
    olivec.text(
        c,
        "olibec",
        WIDTH / 2 - 150,
        HEIGHT / 2 - 40,
        olivec_default_font(),
        10,
        0xFFFFFFFF,
    )

    IMAGE_PATH :: "../../test_data/olivec_example.ppm"

    err := canvas_to_ppm(c, IMAGE_PATH)
    if err != nil {
        fmt.eprintfln("failed to write ppm file: {}", err)
        os.exit(1)
    }

    fmt.println("Wrote image to", filepath.abs(IMAGE_PATH))

    fmt.println("Checking correctness ...")

    img_width, img_height, img_channels: i32 = ---, ---, ---
    img := stb.load(
        "../../test_data/olivec_example.expected.png",
        &img_width,
        &img_height,
        &img_channels,
        4,
    )
    if img == nil {
        fmt.eprintln("failed to load expected image")
        os.exit(1)
    }
    defer libc.free(img)

    if i32(c.width) != img_width {
        fmt.eprintfln("width: {} != {}", c.width, img_width)
        os.exit(1)
    }
    if i32(c.height) != img_height {
        fmt.eprintfln("height: {} != {}", c.height, img_height)
        os.exit(1)
    }

    canvas_pixels := cast([^]u8)c.pixels
    img_pixels := cast([^]u8)img

    for i in 0 ..< (WIDTH * HEIGHT * 4) {
        if canvas_pixels[i] != img_pixels[i] {
            width := (i / 4) % HEIGHT
            height := (i / 4) / HEIGHT
            fmt.eprintfln(
                "Pixel[{}][{}] ({}): {} != {}",
                width,
                height,
                i,
                canvas_pixels[i],
                img_pixels[i],
            )
            os.exit(1)
        }
    }
}

canvas_to_ppm :: proc(
    using canvas: olivec.Canvas,
    file_name: string,
) -> union {
        os.Errno,
        io.Error,
    } {
    file, os_err := os.open(
        file_name,
        os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
        0o644,
    )
    if os_err != 0 do return os_err
    defer os.close(file)

    fmt.fprintf(file, "P6\n{} {}\n255\n", width, height)

    stream := os.stream_from_handle(file)

    for h in 0 ..< height {
        for w in 0 ..< width {
            io.write_ptr(stream, &pixels[stride * h + w], 3) or_return
        }
    }

    return nil
}
