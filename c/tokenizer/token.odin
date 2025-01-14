package c_frontend_tokenizer

Pos :: struct {
    file:   string,
    line:   int,
    column: int,
    offset: int,
}

Token_Kind :: enum {
    Invalid,
    Ident,
    Punct,
    Keyword,
    Char,
    String,
    Number,
    PP_Number,
    Comment,
    EOF,
}

File :: struct {
    name:         string,
    id:           int,
    src:          []byte,
    display_name: string,
    line_delta:   int,
}


Token_Type_Hint :: enum u8 {
    None,
    Int,
    Long,
    Long_Long,
    Unsigned_Int,
    Unsigned_Long,
    Unsigned_Long_Long,
    Float,
    Double,
    Long_Double,
    UTF_8,
    UTF_16,
    UTF_32,
    UTF_Wide,
}

Token_Value :: union {
    i64,
    f64,
    string,
    []u16,
    []u32,
}

Token :: struct {
    kind:       Token_Kind,
    next:       ^Token,
    lit:        string,
    pos:        Pos,
    file:       ^File,
    line_delta: int,
    at_bol:     bool,
    has_space:  bool,
    type_hint:  Token_Type_Hint,
    val:        Token_Value,
    prefix:     string,

    // Preprocessor values
    hide_set:   ^Hide_Set,
    origin:     ^Token,
}

Is_Keyword_Proc :: #type proc(tok: ^Token) -> bool

copy_token :: proc(tok: ^Token) -> ^Token {
    t, _ := new_clone(tok^)
    t.next = nil
    return t
}

new_eof :: proc(tok: ^Token) -> ^Token {
    t, _ := new_clone(tok^)
    t.kind = .EOF
    t.lit = ""
    return t
}

default_is_keyword :: proc(tok: ^Token) -> bool {
    if tok.kind == .Keyword {
        return true
    }
    if len(tok.lit) > 0 {
        switch tok.lit {
        case "auto",
             "break",
             "case",
             "char",
             "const",
             "continue",
             "default",
             "do",
             "double",
             "else",
             "enum",
             "extern",
             "float",
             "for",
             "goto",
             "if",
             "int",
             "long",
             "register",
             "restrict",
             "return",
             "short",
             "signed",
             "sizeof",
             "static",
             "struct",
             "switch",
             "typedef",
             "union",
             "unsigned",
             "void",
             "volatile",
             "while",
             "_Alignas",
             "_Alignof",
             "_Atomic",
             "_Bool",
             "_Generic",
             "_Noreturn",
             "_Thread_local",
             "__restrict",
             "typeof",
             "asm",
             "__restrict__",
             "__thread",
             "__attribute__":
            return true
        }
    }
    return false
}


token_name := [Token_Kind]string {
    .Invalid   = "invalid",
    .Ident     = "ident",
    .Punct     = "punct",
    .Keyword   = "keyword",
    .Char      = "char",
    .String    = "string",
    .Number    = "number",
    .PP_Number = "preprocessor number",
    .Comment   = "comment",
    .EOF       = "eof",
}

