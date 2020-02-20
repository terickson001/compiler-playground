package parse

import "core:fmt"
import "core:os"
import s "core:strings"
import "core:runtime"

Token_Kind :: enum
{
    Invalid,
    EOF,

    Comment,
    
    // Delimiters
    Semi_Colon,
    Comma,
    Open_Paren,
    Close_Paren,
    Open_Brace,
    Close_Brace,
    Open_Bracket,
    Close_Bracket,
    
    // Literals
    Ident,
    Integer,
    Float,
    Char,
    String,

    // Operators
    // - Arithmetic
    Add,
    Sub,
    Mul,
    Quo,
    Mod,
    Inc,
    Dec,

    // - Bitwise
    Bit_Not,
    Bit_And,
    Bit_Or,
    Xor,
    Shl,
    Shr,
    
    // - Logical
    Not,
    And,
    Or,

    // - Comparison
    CmpEq,
    NotEq,
    Lt,
    Gt,
    LtEq,
    GtEq,

    // - Assignment
    Colon,
    Eq,
    AddEq,
    SubEq,
    MulEq,
    QuoEq,
    ModEq,
    ShlEq,
    ShrEq,
    AndEq,
    OrEq,
    XorEq,

    Question,
    // Keywords
    _proc,
    _return,
    _if,
    _else,
    _do,
    
    __ASSIGN_BEGIN = Eq,
    __ASSIGN_END   = XorEq,
    __KEYWORD_BEGIN = _proc,
    __KEYWORD_END   = _do,
}

Location :: struct
{
    filename     : string,
    column, line : int,
}

Token :: struct
{
    kind      : Token_Kind,
    text      : string,
    
    using loc : Location,
}

Lexer :: struct
{
    data      : []byte,
    idx       : int,
    using loc : Location,
}

make_lexer :: proc(path: string) -> (lexer: Lexer)
{
    using lexer;
    filename = path;
    ok: bool;
    data, ok = os.read_entire_file(filename);
    if !ok
    {
        fmt.eprintf("Couldn't open file %q\n", path);
        os.exit(1);
    }
    
    column = 0;
    line   = 1;
    return lexer;
}

try_increment_line :: proc(using lexer: ^Lexer) -> bool
{
    if data[idx] == '\n'
    {
        line += 1;
        column = 0;
        idx += 1;
        return true;
    }
    return false;
}

skip_space :: proc(using lexer: ^Lexer) -> bool
{
    for
    {
        if idx >= len(data) do
            return false;
        
        if s.is_space(rune(data[idx])) && data[idx] != '\n' do
            idx+=1;
        else if data[idx] == '\n' do
            try_increment_line(lexer);
        else do
            return true;
    }
    return true;
}

@private
is_digit :: proc(c: byte, base := 10) -> bool
{
    switch c
    {
        case '0'..'1': return base >= 2;
        case '2'..'7': return base >= 8;
        case '8'..'9': return base >= 10;
        case 'a'..'f',
             'A'..'F':
                   return base == 16;
        case:      return false;
    }
}

@private
lex_error :: proc(using lexer: ^Lexer, fmt_str: string, args: ..any)
{
    fmt.eprintf("%s(%d): ERROR: %s\n",
                filename, line,
                fmt.tprintf(fmt_str, args));
    os.exit(1);
}

@private
tokenize_number :: proc(using lexer: ^Lexer) -> (token: Token)
{
    token.loc = loc;
    token.kind = .Integer;

    start := idx;

    base := 10;
    if data[idx] == '0' && idx + 1 < len(data)
    {
        idx += 1;
        switch data[idx]
        {
            case 'b': base = 2;  idx += 1;
            case 'x': base = 16; idx += 1;
            case 'o': base = 8;  idx += 1;
            case '.': break;
        }
    }

    for idx < len(data) && (is_digit(data[idx], base) || data[idx] == '.')
    {
        if data[idx] == '.'
        {
            if token.kind == .Float do
                lex_error(lexer, "Multiple '.' in constant");
            token.kind = .Float;
        }

        idx += 1;
    }

    token.text = string(data[start:idx]);
    return token;
}

multi_tok :: inline proc(using lexer: ^Lexer, single : Token_Kind,
                         double    := Token_Kind.Invalid,
                         eq        := Token_Kind.Invalid,
                         double_eq := Token_Kind.Invalid) -> (token: Token)
{
    c := data[idx];
    
    token.loc = loc;
    token.kind = single;
    
    start := idx;

    idx += 1;
    if data[idx] == c && double != .Invalid
    {
        idx += 1;
        token.kind = double;
        if double_eq != .Invalid && data[idx] == '='
        {
            idx += 1;
            token.kind = double_eq;
        }
    }
    else if eq != .Invalid && data[idx] == '='
    {
        idx += 1;
        token.kind = eq;
    }

    token.text = string(data[start:idx]);
    return token;
}

enum_name :: proc(value: $T) -> string
{
    tinfo := runtime.type_info_base(type_info_of(typeid_of(T)));
    return tinfo.variant.(runtime.Type_Info_Enum).names[value];
}

lex_token :: proc(using lexer: ^Lexer) -> (token: Token, ok: bool)
{
    if !skip_space(lexer)
    {
        token.kind = .EOF;
        token.loc = loc;
        return token, false;
    }
    
    token.kind = .Invalid;
    token.loc = loc;
    start := idx;
    
    switch data[idx]
    {
    case 'a'..'z', 'A'..'Z', '_':
        idx += 1;
        token.kind = .Ident;
        for
        {
            switch data[idx]
            {
            case 'a'..'z', 'A'..'Z', '0'..'9', '_':
                idx += 1;
                continue;
            }
            break;
        }
        token.text = string(data[start:idx]);
        for k in (Token_Kind.__KEYWORD_BEGIN)..(Token_Kind.__KEYWORD_END)
        {
            name := enum_name(Token_Kind(k));
            if token.text == name[1:]
            {
                fmt.printf("KEYWORD: %v\n", k);
                token.kind = k;
                break;
            }
            
        }
        
    case '0'..'9': token = tokenize_number(lexer);
        
    case '+': token = multi_tok(lexer, .Add, .Inc, .AddEq);
    case '-': token = multi_tok(lexer, .Sub, .Dec, .SubEq);
    case '*': token = multi_tok(lexer, .Mul, .Invalid, .MulEq);
    case '/': token = multi_tok(lexer, .Quo, .Invalid, .QuoEq);
    case '%': token = multi_tok(lexer, .Mod, .Invalid, .ModEq);
    
    case '~': token = multi_tok(lexer, .Bit_Not);
    case '&': token = multi_tok(lexer, .Bit_And, .And, .AndEq);
    case '|': token = multi_tok(lexer, .Bit_Or,  .Or,  .OrEq);
    case '^': token = multi_tok(lexer, .Xor, .Invalid, .XorEq);
    case '?': token = multi_tok(lexer, .Question);

    case '!': token = multi_tok(lexer, .Not, .Invalid, .NotEq);
    
    case ';': token.kind = .Semi_Colon;    idx += 1;
    case ',': token.kind = .Comma;         idx += 1;
    case '(': token.kind = .Open_Paren;    idx += 1;
    case ')': token.kind = .Close_Paren;   idx += 1;
    case '{': token.kind = .Open_Brace;    idx += 1;
    case '}': token.kind = .Close_Brace;   idx += 1;
    case '[': token.kind = .Open_Bracket;  idx += 1;
    case ']': token.kind = .Close_Bracket; idx += 1;
        
    case '=': token = multi_tok(lexer, .Eq, .CmpEq);
    case ':': token = multi_tok(lexer, .Colon);

    case '>': token = multi_tok(lexer, .Gt, .Shr, .GtEq);
    case '<': token = multi_tok(lexer, .Lt, .Shl, .LtEq);
    }

    if token.text == "" do
        token.text = string(data[start:idx]);
    
    return token, token.kind != .Invalid;
}

lex_file :: proc(filename: string) -> []Token
{
    lexer  := make_lexer(filename);
    tokens := make([dynamic]Token);
    
    token, ok := lex_token(&lexer);
    for ok
    {
        append(&tokens, token);
        token, ok = lex_token(&lexer);
    }
    
    return tokens[:];
}
