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

package parser

import "core:strconv"
import "core:strings"

Operator :: enum i64 {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    LShift,
    RShift,
    Or,
    And,
    Xor,
}

ExpressionEnd :: enum i64 {
    Semicolon,
    Colon,
    Parenthesis,
    EOF,
}

OpenParenthesis :: enum i64 {
    OpenParenthesis,
}

InvalidExpressionToken :: enum i64 {
    InvalidExpressionToken,
}

NumberExpression :: i64

ExpressionTokenizer :: struct {
    cursor:     string,
    last_token: ExpressionToken,
}

ExpressionToken :: union {
    NumberExpression,
    Operator,
    OpenParenthesis,
    ExpressionEnd,
    InvalidExpressionToken,
}

create_expression_tokenizer :: proc(s: string) -> ExpressionTokenizer {
    return {cursor = s}
}

expr_next_token :: proc(
    etz: ^ExpressionTokenizer,
) -> (
    token: ExpressionToken,
) {
    using etz
    defer last_token = token

    c: int
    defer if len(cursor) != 0 do cursor = cursor[c + 1:]

    last_rune: rune
    for r, idx in cursor {
        defer last_rune = r

        switch r {
        case '(':
            c = idx
            token = cast(OpenParenthesis)0
            return
        case ')':
            c = idx
            token = ExpressionEnd.Parenthesis
            return
        case ';':
            c = idx
            token = ExpressionEnd.Semicolon
            return
        case ',':
            c = idx
            token = ExpressionEnd.Colon
            return
        case '+', '-':
            was_not_number := true
            if last_token != nil {
                _, ok := last_token.(NumberExpression)
                was_not_number = !ok
            }

            if was_not_number {
                if idx != len(cursor) - 1 {
                    switch cursor[idx + 1] {
                    case '0' ..= '9':
                        n, nidx, ok := expr_parse_number_token(cursor[idx:])
                        nidx += idx
                        c = nidx - 1
                        if !ok {
                            token = cast(InvalidExpressionToken)0
                            return
                        }
                        token = n
                        return
                    }
                }
            }

            c = idx
            switch r {
            case '+':
                token = Operator.Add
                return
            case '-':
                token = Operator.Sub
                return
            }
        case '*':
            c = idx
            token = Operator.Mul
            return
        case '/':
            c = idx
            token = Operator.Div
            return
        case '%':
            c = idx
            token = Operator.Mod
            return
        case '&':
            c = idx
            token = Operator.And
            return
        case '|':
            c = idx
            token = Operator.Or
            return
        case '^':
            c = idx
            token = Operator.Xor
            return
        case '<':
            if last_rune == '<' {
                c = idx
                token = Operator.LShift
                return
            }
        case '>':
            if last_rune == '>' {
                c = idx
                token = Operator.RShift
                return
            }
        case '0' ..= '9':
            n, nidx, ok := expr_parse_number_token(cursor[idx:])
            nidx += idx
            c = nidx - 1
            if !ok {
                token = cast(InvalidExpressionToken)0
                return
            }
            token = n
            return
        case ' ', '\n', '\r':
        case:
            token = cast(InvalidExpressionToken)0
            return
        }
    }

    token = ExpressionEnd.EOF
    return
}

expr_parse_number_token :: proc(
    cursor: string,
) -> (
    n: NumberExpression,
    idx: int,
    ok: bool,
) {
    number: strings.Builder
    strings.builder_init_none(&number)
    defer strings.builder_destroy(&number)

    for nr, _nidx in cursor {
        nidx := _nidx
        defer idx = nidx + 1

        switch nr {
        case '0' ..= '9', 'A' ..= 'F', 'a' ..= 'f':
            strings.write_rune(&number, nr)
        case 'x', 'b':
            ns := strings.to_string(number)
            if !((len(ns) == 1 && ns[0] == '0') || (len(ns) == 2 && (ns[0] == '+' || ns[0] == '-') && ns[1] == '0')) do return

            strings.write_rune(&number, nr)
        case '+', '-':
            if nidx != 0 {
                nidx -= 1
                n, ok = strconv.parse_i64(strings.to_string(number))
                return
            }
            strings.write_rune(&number, nr)
        case:
            nidx -= 1
            n, ok = strconv.parse_i64(strings.to_string(number))
            return
        }
    }

    idx = len(cursor)
    n, ok = strconv.parse_i64(strings.to_string(number))
    return
}

