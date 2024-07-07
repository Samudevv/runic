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

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "gl"
import "vendor:glfw"

START_WIDTH :: 64
START_HEIGHT :: 64
START_SCALE :: 10

START_ALLOC_WIDTH :: 10000
START_ALLOC_HEIGHT :: 10000

Game :: struct {
    window:     glfw.WindowHandle,
    shader:     Shader,
    width:      u64,
    height:     u64,
    front_grid: []u8,
    back_grid:  []u8,
}

main :: proc() {
    fmt.println("Welcome to Life!")

    game: Game
    game.width = START_WIDTH
    game.height = START_HEIGHT

    if !glfw.Init() {
        fmt.eprintln("failed to init glfw")
        os.exit(1)
    }
    defer glfw.Terminate()

    glfw.SetErrorCallback(proc "c" (error_code: i32, description: cstring) {
        context = runtime.default_context()
        fmt.eprintfln("GLFW ERROR ({}): {}", error_code, description)
    })

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_COMPAT_PROFILE)

    game.window = glfw.CreateWindow(
        START_WIDTH * START_SCALE,
        START_HEIGHT * START_SCALE,
        "Game of Life",
        nil,
        nil,
    )
    if game.window == nil {
        fmt.eprintln("failed to create window")
        os.exit(1)
    }
    defer glfw.DestroyWindow(game.window)

    glfw.SetWindowUserPointer(game.window, &game)

    glfw.MakeContextCurrent(game.window)

    if err := gl.ewInit(); err != gl.EW_OK {
        fmt.eprintln("failed to init glew")
        os.exit(1)
    }

    if gl.EW_VERSION_4_3() == gl.TRUE {
        gl.DebugMessageCallback(
            proc "c" (
                source, type: gl.GLenum,
                id: gl.GLuint,
                severity: gl.GLenum,
                length: gl.GLsizei,
                message: ^gl.GLchar,
                use_param: rawptr,
            ) {
                context = runtime.default_context()

                msg := strings.clone_from_cstring_bounded(
                    cstring(cast(^u8)message),
                    int(length),
                )
                defer delete(msg)

                fmt.eprintfln(
                    "GL_DEBUG source={} type={} id={} severity={} message=\"{}\"",
                    DebugSource(source),
                    DebugType(type),
                    id,
                    DebugSeverity(severity),
                    msg,
                )
            },
            nil,
        )
        gl.Enable(gl.DEBUG_OUTPUT)
    }

    ok: bool = ---
    game.shader, ok = build_shader()
    if !ok do os.exit(1)
    defer destroy_shader(game.shader)

    game.front_grid = make([]u8, START_ALLOC_WIDTH * START_ALLOC_HEIGHT)
    game.back_grid = make([]u8, START_ALLOC_WIDTH * START_ALLOC_HEIGHT)
    defer delete(game.front_grid)
    defer delete(game.back_grid)

    assert(
        len(game.front_grid) == START_ALLOC_HEIGHT * START_ALLOC_WIDTH,
        "alloc failed",
    )
    assert(
        len(game.back_grid) == START_ALLOC_HEIGHT * START_ALLOC_WIDTH,
        "alloc failed",
    )

    for idx in 0 ..< game.width * game.height {
        game.back_grid[idx] = u8(rand.int_max(2) * 255)
        game.front_grid[idx] = game.back_grid[idx]
    }

    glfw.SetWindowSizeCallback(
        game.window,
        proc "c" (window: glfw.WindowHandle, width, height: c.int) {
            context = runtime.default_context()

            game := cast(^Game)glfw.GetWindowUserPointer(window)
            w := width / START_SCALE
            h := height / START_SCALE
            game.width = u64(w)
            game.height = u64(h)
            fmt.printfln(
                "Resize width={} height={} w={} h={}",
                width,
                height,
                w,
                h,
            )
        },
    )

    for !glfw.WindowShouldClose(game.window) {
        copy(game.back_grid, game.front_grid)

        for w in 0 ..< game.width {
            for h in 0 ..< game.height {
                using game

                m_ := w
                _m := h
                l_ := (width - 1) if m_ == 0 else m_ - 1
                r_ := 0 if m_ == width - 1 else m_ + 1
                _u := height - 1 if _m == 0 else _m - 1
                _d := 0 if _m == height - 1 else _m + 1

                mm := m_ + width * _m
                lm := l_ + width * _m
                rm := r_ + width * _m
                mu := m_ + width * _u
                md := m_ + width * _d
                lu := l_ + width * _u
                ld := l_ + width * _d
                ru := r_ + width * _u
                rd := r_ + width * _d

                nc :=
                    back_grid[lm] / 255 +
                    back_grid[rm] / 255 +
                    back_grid[mu] / 255 +
                    back_grid[md] / 255 +
                    back_grid[lu] / 255 +
                    back_grid[ld] / 255 +
                    back_grid[ru] / 255 +
                    back_grid[rd] / 255

                // 1. Any live cell with fewer than two live neighbors dies, as if by underpopulation
                if nc < 2 && back_grid[mm] != 0 {
                    front_grid[mm] = 0
                }

                // 2. Any live cell with two or three live neighbors lives on to the next generation
                if (nc == 2 || nc == 3) && back_grid[mm] != 0 {
                    continue
                }

                // 3. Any live cell with more than three live neighbors dies, as if by overpopulation
                if nc > 3 && back_grid[mm] != 0 {
                    front_grid[mm] = 0
                }

                // 4. Any dead cell with exacly three live neighbors becomes a live cell, as if by reproduction
                if nc == 3 && back_grid[mm] == 0 {
                    front_grid[mm] = 255
                }
            }
        }

        update_texture(
            game.shader,
            gl.GLsizei(game.width),
            gl.GLsizei(game.height),
            game.front_grid,
        )

        window_width, window_height := glfw.GetWindowSize(game.window)
        gl.Viewport(0, 0, window_width, window_height)
        gl.ClearColor(1, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.DrawArrays(gl.TRIANGLES, 0, 6)

        glfw.SwapBuffers(game.window)
        glfw.PollEvents()
    }
}

VERTEX_SHADER :: `
#version 330

#extension GL_ARB_shading_language_420pack : enable

out vec2 FragUV;

vec2 vertexPositions[6] = {vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
                           vec2(1.0, 1.0),   vec2(-1.0, 1.0), vec2(-1.0, -1.0)};
vec2 vertexUVs[6] = {vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
                     vec2(1.0, 0.0), vec2(0.0, 0.0), vec2(0.0, 1.0)};

void main() {
  vec2 pos = vertexPositions[gl_VertexID];
  vec2 uv = vertexUVs[gl_VertexID];

  FragUV = uv;
  gl_Position = vec4(pos.xy, 0.0, 1.0);
}
`

FRAGMENT_SHADER :: `
#version 330

#extension GL_ARB_explicit_uniform_location : enable

in vec2 FragUV;

out vec4 FragColor;

layout(location = 0) uniform sampler2D uTex;

void main() {
  vec4 texColor = texture(uTex, FragUV);
  vec3 gridColor = vec3(texColor.r, texColor.r, texColor.r);

  FragColor = vec4(mix(gridColor, vec3(FragUV, 0.0), 0.5), 1.0);
}
`

DebugSeverity :: enum {
    NOTIFICATION = 33387,
    HIGH         = 37190,
    MEDIUM       = 37191,
    LOW          = 37192,
}

DebugType :: enum {
    ERROR               = 33356,
    DEPRECATED_BEHAVIOR = 33357,
    UNDEFINED_BEHAVIOR  = 33358,
    PORTABILITY         = 33359,
    PERFORMANCE         = 33360,
    OTHER               = 33361,
    MARKER              = 33384,
    PUSH_GROUP          = 33385,
    POP_GROUP           = 33386,
}

DebugSource :: enum {
    API             = 33350,
    WINDOW_SYSTEM   = 33351,
    SHADER_COMPILER = 33352,
    THIRD_PARTY     = 33353,
    APPLICATION     = 33354,
    OTHER           = 33355,
}

Shader :: struct {
    program: gl.GLuint,
    texture: gl.GLuint,
}

build_shader :: proc() -> (sh: Shader, ok: bool) {
    sh.program = gl.CreateProgram()
    if sh.program == 0 {
        return
    }

    vertex := gl.CreateShader(gl.VERTEX_SHADER)
    fragment := gl.CreateShader(gl.FRAGMENT_SHADER)
    if vertex == 0 || fragment == 0 {
        return
    }
    defer gl.DeleteShader(vertex)
    defer gl.DeleteShader(fragment)

    vertex_source := raw_data(string(VERTEX_SHADER))
    fragment_source := raw_data(string(FRAGMENT_SHADER))

    vertex_len := gl.GLint(len(VERTEX_SHADER))
    fragment_len := gl.GLint(len(FRAGMENT_SHADER))

    gl.ShaderSource(vertex, 1, cast(^^gl.GLchar)&vertex_source, &vertex_len)
    gl.ShaderSource(
        fragment,
        1,
        cast(^^gl.GLchar)&fragment_source,
        &fragment_len,
    )

    gl.CompileShader(vertex)
    gl.CompileShader(fragment)

    info_log: [512]gl.GLchar
    status: gl.GLint = ---
    gl.GetShaderiv(vertex, gl.COMPILE_STATUS, &status)
    if status != gl.TRUE {
        gl.GetShaderInfoLog(vertex, 512, nil, &info_log[0])
        fmt.eprintfln(
            "SHADER::VERTEX::COMPILE: {}",
            cstring(cast(^u8)&info_log[0]),
        )
        return
    }

    fmt.println("SHADER::VERTEX::COMPILE: SUCCESS")

    gl.GetShaderiv(fragment, gl.COMPILE_STATUS, &status)
    if status != gl.TRUE {
        gl.GetShaderInfoLog(fragment, 512, nil, &info_log[0])
        fmt.eprintfln(
            "SHADER::FRAGMENT::COMPILE: {}",
            cstring(cast(^u8)&info_log[0]),
        )
        return
    }

    fmt.println("SHADER::FRAGMENT::COMPILE: SUCCESS")

    gl.AttachShader(sh.program, vertex)
    gl.AttachShader(sh.program, fragment)
    gl.LinkProgram(sh.program)

    gl.GetProgramiv(sh.program, gl.LINK_STATUS, &status)
    if status != gl.TRUE {
        gl.GetProgramInfoLog(sh.program, 512, nil, &info_log[0])
        fmt.eprintfln("SHADER::LINK: {}", cstring(cast(^u8)&info_log[0]))
        return
    }

    fmt.println("SHADER::LINK: SUCCESS")

    vao: gl.GLuint = ---
    gl.GenVertexArrays(1, &vao)
    defer gl.DeleteVertexArrays(1, &vao)

    gl.BindVertexArray(vao)
    gl.ValidateProgram(sh.program)
    gl.BindVertexArray(0)

    gl.GetProgramiv(sh.program, gl.VALIDATE_STATUS, &status)
    if status != gl.TRUE {
        gl.GetProgramInfoLog(sh.program, 512, nil, &info_log[0])
        fmt.eprintfln("SHADER::VALIDATE: {}", cstring(cast(^u8)&info_log[0]))
        return
    }

    fmt.println("SHADER::VALIDATE: SUCCESS")

    gl.GenTextures(1, &sh.texture)
    if sh.texture == 0 {
        fmt.eprintln("TEXTURE: glGenTextures failed")
        return
    }

    gl.BindTexture(gl.TEXTURE_2D, sh.texture)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

    gl.UseProgram(sh.program)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.Uniform1i(0, 0)

    ok = true
    return
}

destroy_shader :: proc(sh: Shader) {
    gl.DeleteProgram(sh.program)
    tex := sh.texture
    gl.DeleteTextures(1, &tex)
}

update_texture :: proc(sh: Shader, width, height: gl.GLsizei, data: []u8) {
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RED,
        width,
        height,
        0,
        gl.RED,
        gl.UNSIGNED_BYTE,
        raw_data(data),
    )
}
