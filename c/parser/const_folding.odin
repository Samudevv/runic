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

import "core:fmt"
import "core:strings"

OperatorPriority :: [Operator]int {
    .Add    = 5,
    .Sub    = 5,
    .Mul    = 6,
    .Div    = 6,
    .Mod    = 6,
    .LShift = 4,
    .RShift = 4,
    .Or     = 1,
    .And    = 3,
    .Xor    = 2,
}

OperatorExpression :: struct {
    left:  ^Expression,
    op:    Operator,
    right: ^Expression,
}

Expression :: union {
    OperatorExpression,
    NumberExpression,
}

parse_expression :: proc(
    s: string,
    allocator := context.allocator,
) -> (
    Expression,
    bool,
) #optional_ok {
    etz := create_expression_tokenizer(s)
    return parse_expression_token(&etz, 0, allocator)
}

parse_expression_token :: proc(
    etz: ^ExpressionTokenizer,
    priority: int,
    allocator := context.allocator,
) -> (
    Expression,
    bool,
) #optional_ok {
    @(static)
    operator_priority := OperatorPriority

    left: Expression
    op: Operator
    right: Expression

    token := expr_next_token(etz)
    #partial switch t in token {
    case NumberExpression:
        left = t
    case OpenParenthesis:
        ok: bool = ---
        left, ok = parse_expression_token(etz, 0, allocator)
        if !ok do return nil, false
    case:
        return nil, false
    }

    last_token := token
    last_cursor := etz.cursor
    token = expr_next_token(etz)

    for {
        #partial switch t in token {
        case Operator:
            op = t
        case ExpressionEnd:
            return left, true
        case:
            return nil, false
        }

        if operator_priority[op] > priority {
            ok: bool = ---
            right, ok = parse_expression_token(
                etz,
                operator_priority[op],
                allocator,
            )
            if !ok do return nil, false

            left = OperatorExpression {
                left  = new_clone(left, allocator),
                op    = op,
                right = new_clone(right, allocator),
            }

            e: ExpressionEnd = ---
            if e, ok = etz.last_token.(ExpressionEnd);
               ok && e == .Parenthesis {
                return left, true
            }

            last_token = token
            last_cursor = etz.cursor
            token = expr_next_token(etz)
        } else {
            etz.last_token = last_token
            etz.cursor = last_cursor
            return left, true
        }
    }
}

evaluate_expression :: proc(expr: Expression) -> (value: i64) {
    switch e in expr {
    case OperatorExpression:
        using e

        value_l: i64
        switch l in left {
        case NumberExpression:
            value_l += l
        case OperatorExpression:
            value_l += evaluate_expression(l)
        }

        value_r: i64
        switch r in right {
        case NumberExpression:
            value_r += r
        case OperatorExpression:
            value_r += evaluate_expression(r)
        }

        switch op {
        case .Add:
            return value_l + value_r
        case .Sub:
            return value_l - value_r
        case .Mul:
            return value_l * value_r
        case .Div:
            return value_l / value_r
        case .Mod:
            return value_l % value_r
        case .LShift:
            return value_l << u64(value_r)
        case .RShift:
            return value_l >> u64(value_r)
        case .Or:
            return value_l | value_r
        case .And:
            return value_l & value_r
        case .Xor:
            return value_l ~ value_r
        }
    case NumberExpression:
        return e
    }

    return 0
}

expression_to_string :: proc(expr: Expression) -> string {
    out: strings.Builder
    strings.builder_init_none(&out)

    switch e in expr {
    case NumberExpression:
        fmt.sbprint(&out, e)
    case OperatorExpression:
        fmt.sbprintf(
            &out,
            "({} {} {})",
            expression_to_string(e.left^),
            e.op,
            expression_to_string(e.right^),
        )
    }

    return strings.to_string(out)
}
