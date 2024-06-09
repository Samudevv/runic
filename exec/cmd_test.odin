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

import "core:os"
import "core:strings"
import "core:testing"

when ODIN_OS == .Linux || ODIN_OS == .Darwin {

    @(test)
    test_stderr :: proc(t: ^testing.T) {
        using testing

        out: strings.Builder
        strings.builder_init(&out)
        defer strings.builder_destroy(&out)

        _, err := command(
            "man",
            {"i_dont_exist"},
            stderr = strings.to_stream(&out),
            env = Env.None,
        )
        if !expect_value(t, err, nil) do return

        expect_value(
            t,
            strings.to_string(out),
            "No manual entry for i_dont_exist\n",
        )
    }

    @(test)
    test_pipe_commands :: proc(t: ^testing.T) {
        using testing
        out: strings.Builder
        status, err := pipe_commands(
             {
                {"printf", "#1\n#2\n3\n4\n#5"},
                {"sed", "/^#/d"},
                {"grep", "-n", "."},
            },
            stdout = strings.to_stream(&out),
            env = Env.None,
        )

        if !expect_value(t, err, nil) do return
        expect_value(t, status, 0)
        expect_value(t, strings.to_string(out), "1:3\n2:4\n")
    }
    @(test)
    test_status :: proc(t: ^testing.T) {
        using testing

        {
            status, err := command("/bin/sh", {"-c", "exit 0"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 0)
        }
        {
            status, err := command("/bin/sh", {"-c", "exit 1"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 1)
        }
        {
            status, err := command("/bin/sh", {"-c", "exit 10"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 10)
        }
        {
            status, err := command("/bin/sh", {"-c", "exit 123"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 123)
        }
        {
            status, err := command("/bin/sh", {"-c", "exit 255"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 255)
        }
    }

    @(test)
    test_stdin :: proc(t: ^testing.T) {
        using testing

        out: strings.Builder
        strings.builder_init(&out)
        defer strings.builder_destroy(&out)
        in_stm: strings.Reader

        _, err := command(
            "cat",
            stdout = strings.to_stream(&out),
            stdin = strings.to_reader(&in_stm, "Hello World from cat"),
            env = Env.None,
        )
        if !expect_value(t, err, nil) do return

        expect_value(t, strings.to_string(out), "Hello World from cat")
    }

    @(test)
    test_stdout :: proc(t: ^testing.T) {
        using testing

        out: strings.Builder
        strings.builder_init(&out)
        defer strings.builder_destroy(&out)

        _, err := command(
            "echo",
            {"Hello", "World", "from", "echo"},
            stdout = strings.to_stream(&out),
            env = Env.None,
        )
        if !expect_value(t, err, nil) do return

        expect_value(t, strings.to_string(out), "Hello World from echo\n")

    }

    @(test)
    test_env :: proc(t: ^testing.T) {
        using testing

        {
            out: strings.Builder
            strings.builder_init(&out)
            defer strings.builder_destroy(&out)

            status, err := command(
                "env",
                stdout = strings.to_stream(&out),
                env = []string{"TEST=test_env"},
            )
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 0)
            expect_value(t, strings.to_string(out), "TEST=test_env\n")
        }

        {
            out: strings.Builder
            strings.builder_init(&out)
            defer strings.builder_destroy(&out)

            os.set_env("test_env_parent", "Yes")

            status, err := command(
                "env",
                stdout = strings.to_stream(&out),
                env = ParentAnd{{"test_env_child=test_env"}},
            )
            if !expect_value(t, err, nil) do return

            out_str := strings.to_string(out)

            expect_value(t, status, 0)
            expect(t, strings.contains(out_str, "test_env_parent=Yes"))
            expect(t, strings.contains(out_str, "test_env_child=test_env"))
        }
    }

    @(test)
    test_write_to_handle :: proc(t: ^testing.T) {
        using testing

        file, os_err := os.open(
            "test_data/write_to_handle",
            os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
            0o644,
        )
        if !expect_value(t, os_err, 0) do return

        status, err := command("echo", {"cogito ergo sum"}, stdout = file)
        os.close(file)
        if !expect_value(t, err, nil) do return

        expect_value(t, status, 0)

        data, ok := os.read_entire_file("test_data/write_to_handle")
        if !expect(t, ok) do return
        defer delete(data)

        expect_value(t, string(data), "cogito ergo sum\n")
    }
} else when ODIN_OS == .Windows {

    @(test)
    test_hello_world :: proc(t: ^testing.T) {
        using testing

        status, err := command("cmd", {"/c", "echo Hello World"})
        if !expect_value(t, err, nil) do return

        expect_value(t, status, 0)
    }

    @(test)
    test_status :: proc(t: ^testing.T) {
        using testing

        {
            status, err := command("cmd", {"/c", "exit 0"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 0)
        }
        {
            status, err := command("cmd", {"/c", "exit 1"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 1)
        }
        {
            status, err := command("cmd", {"/c", "exit 10"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 10)
        }
        {
            status, err := command("cmd", {"/c", "exit 123"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 123)
        }
        {
            status, err := command("cmd", {"/c", "exit 255"})
            if !expect_value(t, err, nil) do return

            expect_value(t, status, 255)
        }
    }

    @(test)
    test_stdin :: proc(t: ^testing.T) {
        using testing

        out: strings.Builder
        strings.builder_init(&out)
        defer strings.builder_destroy(&out)
        in_stm: strings.Reader

        _, err := command(
            "build/win_cat.exe",
            stdout = strings.to_stream(&out),
            stdin = strings.to_reader(&in_stm, "Hello World from cat"),
        )
        if !expect_value(t, err, nil) do return

        expect_value(t, strings.to_string(out), "Hello World from cat")
    }


    @(test)
    test_stdout :: proc(t: ^testing.T) {
        using testing

        out: strings.Builder
        strings.builder_init(&out)
        defer strings.builder_destroy(&out)

        _, err := command(
            "cmd",
            {"/c", "echo Hello World from echo"},
            stdout = strings.to_stream(&out),
        )
        if !expect_value(t, err, nil) do return

        expect_value(t, strings.to_string(out), "Hello World from echo\r\n")

    }

    @(test)
    test_env :: proc(t: ^testing.T) {
        using testing

        {
            out: strings.Builder
            strings.builder_init(&out)
            defer strings.builder_destroy(&out)

            os.set_env("TEST", "testy")

            _, err := command(
                "cmd",
                {"/c", "echo %TEST%"},
                stdout = strings.to_stream(&out),
                env = []string{"TEST=test_env"},
            )
            if !expect_value(t, err, nil) do return

            expect_value(t, strings.to_string(out), "test_env\r\n")
        }

        {
            out: strings.Builder
            strings.builder_init(&out)
            defer strings.builder_destroy(&out)

            os.set_env("TEST", "testy")

            _, err := command(
                "cmd",
                {"/c", "echo %TEST%"},
                stdout = strings.to_stream(&out),
                env = Env.None,
            )
            if !expect_value(t, err, nil) do return

            expect_value(t, strings.to_string(out), "%TEST%\r\n")
        }

    }

    @(test)
    test_lookup_path :: proc(t: ^testing.T) {
        using testing

        {
            path, ok := lookup_path("cmd")
            if !expect(t, ok) do return

            expect(
                t,
                strings.equal_fold(path, "C:\\windows\\system32\\cmd.exe"),
            )
        }
    }
}
