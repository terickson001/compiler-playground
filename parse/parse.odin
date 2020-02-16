package parse

import "core:fmt"
import "core:os"
import sconv "core:strconv"

syntax_error :: proc(using token: Token, fmt_str: string, args: ..any)
{
    fmt.eprintf("%s(%d:%d_: \x1b[31mSYNTAX ERROR:\x1b[0m %s\n",
                loc.filename, loc.line, loc.column,
                fmt.tprintf(fmt_str, ..args));
}

Parser :: struct
{
    lexer: Lexer,

    tokens: Ring(Token, 4),
}

Ring :: struct(T: typeid, N: int)
{
    count: int,
    start: int,
    buf: [N]T,
}

print_expr :: proc(expr: ^Node, first := true)
{
    #partial switch e in expr.variant
    {
    case Literal:
        switch v in e.value
        {
            case i64: fmt.printf("%d", v);
            case f64: fmt.printf("%f", v);
        }
        
    case Unary_Expr:
        fmt.printf("%s", e.op.text);
        print_expr(e.expr, false);
        
    case Binary_Expr:
        print_expr(e.lhs, false);
        fmt.printf(" %s ", e.op.text);
        print_expr(e.rhs, false);
        
    case Paren_Expr:
        fmt.printf("%s", e.open.text);
        print_expr(e.expr, false);
        fmt.printf("%s", e.close.text);
    }

    if first do fmt.printf("\n");
}

ring_get :: proc(using ring: Ring($T, $N), idx: int) -> T
{
    idx := idx;
    assert(idx < count, "index exceeds size of ring buffer");
    idx = (start + idx) % N;
    return buf[idx];
}

ring_add :: proc(using ring: ^Ring($T, $N), val: T)
{
    if count == N do start += 1;
    if count <  N do count += 1;
    idx := (start + count - 1) % N;
    
    buf[idx] = val;
}

expect :: proc(using parser: ^Parser, kind: Token_Kind) -> Token
{
    val := consume(parser);
    if val.kind != kind
    {
        fmt.eprintf("ERROR: Expected %v, got %v\n", kind, val.kind);
        os.exit(1);
    }
    
    return val;
}

consume :: proc(using parser: ^Parser) -> Token
{
    val := peek(parser);
    tokens.start = (tokens.start + 1) % len(tokens.buf);
    tokens.count -= 1;
    
    // fmt.printf("CONSUME: %v\n", val);
    return val;
}

peek :: proc(using parser: ^Parser) -> Token
{
    if tokens.count == 0
    {
        val, ok := lex_token(&lexer);
        ring_add(&tokens, val);
    }

    tok := ring_get(tokens, 0);
    return tok;
}

make_parser :: proc(path: string) -> (parser: Parser)
{
    parser.lexer = make_lexer(path);
    return parser;
}

parse_file :: proc(path: string) -> ^Node
{
    parser := make_parser(path);
    return run_parser(&parser);
}

run_parser :: proc(using parser: ^Parser) -> ^Node
{
    return parse_expr(parser);
}

parse_expr :: proc(using parser: ^Parser) -> ^Node
{
    return parse_binary_expr(parser, 0+1);
}

precedence :: proc(token: Token) -> int
{
    #partial switch token.kind
    {
    case .Mul, .Quo: return 13;
    case .Add, .Sub: return 12;    
    case .Eq:        return 2;
    }

    return 0;
}

parse_binary_expr :: proc(using parser: ^Parser, max_prec: int) -> ^Node
{
    expr := parse_unary_expr(parser);
    prec := precedence(peek(parser));
    for prec >= max_prec
    {
        for
        {
            op := peek(parser);
            op_prec := precedence(op);
            if op_prec != prec do break;
            consume(parser);
            
            rhs := parse_binary_expr(parser, prec +1);
            if rhs == nil do
                syntax_error(op, "Expected expression after binary operator");
            expr = new_clone(Node{Binary_Expr{op, expr, rhs}});
        }
        prec -= 1;
    }
    
    return expr;
}

parse_unary_expr :: proc(using parser: ^Parser) -> ^Node
{
    expr: ^Node;

    #partial switch peek(parser).kind
    {
    case .Add:
    case .Sub:
        op := consume(parser);
        return new_clone(Node{Unary_Expr{op, parse_unary_expr(parser)}});
    case: break;
    }

    return parse_operand(parser);
}

parse_operand :: proc(using parser: ^Parser) -> ^Node
{
    #partial switch peek(parser).kind
    {
    case .Integer:
        tok := expect(parser, .Integer);
        return new_clone(Node{Literal{tok, sconv.parse_i64(tok.text)}});
        
    case .Float:
        tok := expect(parser, .Float);
        return new_clone(Node{Literal{tok, sconv.parse_f64(tok.text)}});

    case .Open_Paren:
        open  := expect(parser, .Open_Paren);
        expr  := parse_expr(parser);
        close := expect(parser, .Close_Paren);
        return new_clone(Node{Paren_Expr{open, close, expr}});
        
    case: break;
    }

    return nil;
}
