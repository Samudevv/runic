package ini

import "core:bufio"
import "core:io"
import "core:os"
import "core:strings"
import "root:errors"
import om "root:ordered_map"

parse_file :: proc(
    file_name: string,
    allocator := context.allocator,
) -> (
    ini: map[string]om.OrderedMap(string, string),
    err: errors.Error,
) {
    file, os_err := os.open(file_name)
    errors.wrap(os_err) or_return
    defer os.close(file)
    return parse_reader(os.stream_from_handle(file), file_name, allocator)
}

parse_reader :: proc(
    rd: io.Reader,
    file_name := "runestone",
    allocator := context.allocator,
) -> (
    ini: map[string]om.OrderedMap(string, string),
    err: errors.Error,
) {
    line_reader: bufio.Reader
    bufio.reader_init(&line_reader, rd)
    defer bufio.reader_destroy(&line_reader)

    ini = make(map[string]om.OrderedMap(string, string), allocator = allocator)
    ini[""] = om.make(string, string, allocator = allocator)
    current_section := &ini[""]

    line: []u8 = ---
    bufio_err: io.Error = ---
    line_count: uint = 1
    line_loop: for line, bufio_err = bufio.reader_read_slice(
            &line_reader,
            '\n',
        );
        bufio_err == .None || bufio_err == .EOF;
        line, bufio_err = bufio.reader_read_slice(&line_reader, '\n') {
        defer line_count += 1
        if bufio_err == .EOF && len(line) == 0 do break line_loop

        line_str := strings.trim_space(string(line))
        if len(line_str) == 0 do continue line_loop

        if strings.has_prefix(line_str, "[") {
            if !strings.has_suffix(line_str, "]") {
                return ini, errors.message(
                    "{}:{}: invalid section statement; \"]\" expected",
                    file_name,
                    line_count,
                )
            }

            section_name := strings.clone(
                strings.trim_prefix(strings.trim_suffix(line_str, "]"), "["),
                allocator,
            )

            ini[section_name] = om.make(string, string)
            current_section = &ini[section_name]
        } else {
            // Retreive the first '=' rune that is not inside a string
            inside_string: bool
            equals_pos: int = -1
            rune_loop: for r, idx in line_str {
                switch r {
                case '"':
                    if inside_string && idx != 0 && line_str[idx - 1] == '\\' {
                        continue
                    }
                    inside_string = !inside_string
                case '=':
                    equals_pos = idx
                    if !inside_string {
                        break rune_loop
                    }
                }
            }

            if equals_pos == -1 {
                err = errors.message(
                    "{}:{}: \"=\" expected",
                    file_name,
                    line_count,
                )
                return
            }

            key_str := strings.clone(
                strings.trim_right_space(line_str[:equals_pos]),
                allocator,
            )
            value_str := strings.clone(
                strings.trim_left_space(line_str[equals_pos + 1:]),
                allocator,
            )

            om.insert(current_section, key_str, value_str)
        }
    }

    return
}

parse :: proc {
    parse_file,
    parse_reader,
}
