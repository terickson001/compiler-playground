package parse

import "core:fmt"
import "core:os"
import sconv "core:strconv"

syntax_error :: proc(using token: Token, fmt_str: string, args: ..any)
{
    fmt.eprintf("%s(%d:%d): \x1b[31mSYNTAX ERROR:\x1b[0m %s\n",
                loc.filename, loc.line, loc.column,
                fmt.tprintf(fmt_str, ..args));
}

File :: struct
{
    path: string,
    using scope: ^Scope,
}

Parser :: struct
{
    lexer: Lexer,
    tokens: Ring(Token, 4),
    
    files: [dynamic]File,
    curr_file: File,
    
    scope: ^Scope,
}

Ring :: struct(T: typeid, N: int)
{
    count: int,
    start: int,
    buf: [N]T,
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

make_node :: proc(using parser: ^Parser, variant: $T) -> ^Node
{
    node := new(Node);
    node.scope = parser.scope;
    node.variant = variant;
    return node;
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

expect_one :: proc(using parser: ^Parser, kinds: ..Token_Kind) -> Token
{
    val := peek(parser);
    for k in kinds
    {
        if val.kind == k do
            return consume(parser);
    }
    
    fmt.eprintf("%s(%d): ERROR: Expected one of %v, got %v(%q)\n",
                val.loc.filename, val.loc.line, kinds, val.kind, val.text);
    os.exit(1);
    // return {};
}

expect :: proc(using parser: ^Parser, kind: Token_Kind) -> Token
{
    val := consume(parser);
    if val.kind != kind
    {
        fmt.eprintf("%s(%d): ERROR: Expected %v, got %v(%q)\n",
                    val.loc.filename, val.loc.line, kind, val.kind, val.text);
        os.exit(1);
    }
    
    return val;
}

consume :: proc(using parser: ^Parser) -> Token
{
    val := peek(parser);
    tokens.start = (tokens.start + 1) % len(tokens.buf);
    tokens.count -= 1;
    
    return val;
}

allow :: proc(using parser: ^Parser, kind: Token_Kind) -> bool
{
    if peek(parser).kind == kind
    {
        consume(parser);
        return true;
    }
    return false;
}

peek :: proc(using parser: ^Parser, idx := 0) -> Token
{
    assert(idx < len(tokens.buf), "Index exceeds size of ring buffer");
    for tokens.count <= idx
    {
        val, ok := lex_token(&lexer);
        for val.kind == .Comment do
            val, ok = lex_token(&lexer);
        ring_add(&tokens, val);
    }
    
    tok := ring_get(tokens, idx);
    return tok;
}

make_parser :: proc(path: string) -> (parser: Parser)
{
    parser.lexer = make_lexer(path);
    parser.curr_file = File{path, make_scope(parser.scope)};
    parser.scope = parser.curr_file.scope;
    return parser;
}

parse_file :: proc(path: string) -> Parser
{
    parser := make_parser(path);
    run_parser(&parser);
    append(&parser.files, parser.curr_file);
    return parser;
}

run_parser :: proc(using parser: ^Parser)
{
    for peek(parser).kind != .EOF
    {
        stmt := parse_statement(parser);
        if stmt == nil do continue; // Empty Statement
        if stmt_requires_semicolon(stmt) do expect(parser, .Semi_Colon);
        // scope_statement(curr_file.scope, stmt);
    }
}

parse_ident_list :: proc(using parser: ^Parser) -> []^Node
{
    idents := make([dynamic]^Node);
    append(&idents, make_node(parser, Ident{expect(parser, .Ident)}));
    for peek(parser).kind == .Comma
    {
        consume(parser);
        append(&idents, make_node(parser, Ident{consume(parser)}));
    }
    return idents[:];
}

parse_block :: proc(using parser: ^Parser) -> ^Node
{
    new_scope := make_scope(scope);
    scope = new_scope;
    defer scope = scope.parent;
    
    open := expect_one(parser, .Open_Brace, ._do);
    close: Token;
    if open.kind == .Open_Brace
    {
        for peek(parser).kind != .Close_Brace
        {
            statement := parse_statement(parser);
            if stmt_requires_semicolon(statement) do expect(parser, .Semi_Colon);
        }
        close = expect(parser, .Close_Brace);
    }
    else
    {
        statement := parse_statement(parser);
        if stmt_requires_semicolon(statement) do expect(parser, .Semi_Colon);
    }
    
    return make_node(parser, Block_Stmt{open, close, scope});
}

stmt_requires_semicolon :: proc(stmt: ^Node) -> bool
{
    if stmt == nil do return false;
    
    #partial switch v in stmt.variant
    {
        case If_Stmt: return false;
        case For_Stmt: return false;
        case Block_Stmt: return false;
        
        case Var: 
        if v.value != nil
        {
            #partial switch v in v.value.variant
            {
                case Proc: return false;
            }
        }
        return true;
        
        case: return true;
    }
}

parse_statement :: proc(using parser: ^Parser) -> ^Node
{
    statement: ^Node;
    defer if statement != nil do scope_statement(scope, statement);
    #partial switch peek(parser).kind
    {
        case .Open_Brace:
        statement = parse_block(parser);
        
        case .Ident:
        #partial switch peek(parser, 1).kind
        {
            case .Colon:
            statement = parse_var_decl(parser);
            
            case (.__ASSIGN_BEGIN)..(.__ASSIGN_END):
            statement = parse_assign(parser);
            
            case /*(.__OP_BEGIN)..(.__OP_END)*/:
            expr := parse_expr(parser);
            statement = make_node(parser, Expr_Stmt{expr, nil});
        }
        
        case ._return:
        tok := consume(parser);
        val := parse_expr(parser);
        // expect(parser, .Semi_Colon);
        statement = make_node(parser, Return_Stmt{tok, val});
        
        case ._break, ._continue:
        statement = make_node(parser, Jump_Stmt{consume(parser)});
        
        case ._if:
        tok := consume(parser);
        cond := parse_expr(parser);
        block := parse_block(parser);
        _else: ^Node;
        if allow(parser, ._else)
        {
            #partial switch peek(parser).kind
            {
                case ._if:
                _else = parse_statement(parser);
                case .Open_Brace, ._do:
                _else = parse_block(parser);
            }
        }
        statement = make_node(parser, If_Stmt{tok, cond, block, _else});
        
        case ._for:
        
        new_scope := make_scope(scope);
        scope = new_scope;
        defer scope = scope.parent;
        
        init, cond, post: ^Node;
        tok := consume(parser);
        has_parens := allow(parser, .Open_Paren);
        init = parse_statement(parser);
        expect(parser, .Semi_Colon);
        cond = parse_statement(parser);
        expect(parser, .Semi_Colon);
        if peek(parser).kind != ._do && peek(parser).kind != .Open_Brace
            && !(has_parens && peek(parser).kind == .Close_Paren)
        {
            post = parse_statement(parser);
        }
        if has_parens do expect(parser, .Close_Paren);
        block := parse_block(parser);
        scope_statement(scope, block);
        
        statement = make_node(parser, For_Stmt{tok, new_scope, init, cond, post, block});
        
        case .Semi_Colon: // Empty Statement
        expect(parser, .Semi_Colon);
        
        case:
        fmt.eprintf("INVALID TOKEN: %v\n", peek(parser));
        os.exit(1);
    }
    
    return statement;
}

parse_assign :: proc(using parser: ^Parser) -> ^Node
{
    lhs := parse_expr(parser);
    op := expect_one(parser,
                     .Eq, .AddEq, .SubEq,
                     .QuoEq, .MulEq, .ModEq,
                     .ShlEq, .ShrEq, .AndEq,
                     .OrEq, .XorEq);
    rhs := parse_expr(parser);
    // expect(parser, .Semi_Colon);
    return make_node(parser, Assign_Stmt{op, lhs, rhs});
}

parse_var_decl :: proc(using parser: ^Parser) -> ^Node
{
    lhs := parse_ident_list(parser);
    #partial switch peek(parser).kind
    {
        case .Colon: // :: / :=
        consume(parser);
        
        type: ^Node = nil;
        if peek(parser).kind != .Colon && peek(parser).kind != .Eq do
            type = parse_type(parser);
        
        rhs: ^Node = nil;
        is_const := false;
        #partial switch peek(parser).kind
        {
            case .Colon: // ::
            is_const = true;
            consume(parser);
            rhs = parse_expr(parser);
            
            case .Eq:    // :=
            consume(parser);
            rhs = parse_expr(parser);
            
            case: break;  // : (Not explicitly initialized)
        }
        
        var := make_node(parser, Var{lhs, type, rhs, is_const});
        for name in lhs
        {
            if existing, found := scope.declarations[ident_str(name)]; found
            {
                token := node_token(name);
                prev_token := node_token(existing);
                fmt.eprintf("%s(%d): \e[31mERROR\e[0m: Redeclaration of %q in this scope\n",
                            token.filename, token.line, ident_str(name));
                fmt.eprintf("    at %s(%d)\n", prev_token.filename, prev_token.line);
                os.exit(1);
            }
            scope.declarations[ident_str(name)] = name;
        }
        return var;
    }
    return nil;
}

parse_var_list :: proc(using parser: ^Parser) -> []^Node
{
    vars := make([dynamic]^Node);
    append(&vars, parse_var_decl(parser));
    for peek(parser).kind == .Comma
    {
        consume(parser);
        append(&vars, parse_var_decl(parser));
    }
    
    return vars[:];
}

parse_type :: proc(using parser: ^Parser) -> ^Node
{
    ident := make_node(parser, Ident{expect(parser, .Ident)});
    return ident;
}

parse_expr :: proc(using parser: ^Parser) -> ^Node
{
    return parse_binary_expr(parser, 0+1);
}

parse_expr_list :: proc(using parser: ^Parser) -> []^Node
{
    list := make([dynamic]^Node);
    append(&list, parse_expr(parser));
    for allow(parser, .Comma) do
        append(&list, parse_expr(parser));
    
    return list[:];
}

precedence :: proc(token: Token) -> int
{
    #partial switch token.kind
    {
        case .Mul, .Quo, .Mod:       return 13;
        case .Add, .Sub:             return 12;
        case .Shl, .Shr:             return 11;
        case .Lt, .Gt, .LtEq, .GtEq: return 10;
        case .CmpEq, .NotEq:         return 9;
        case .Bit_And:               return 8;
        case .Xor:                   return 7;
        case .Bit_Or:                return 6;
        case .And:                   return 5;
        case .Or:                    return 4;
        case .Question:              return 3;
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
            
            if op.kind == .Question
            {
                then := parse_expr(parser);
                expect(parser, .Colon);
                _else := parse_expr(parser);
                expr = make_node(parser, Ternary_Expr{expr, then, _else});
            }
            else
            {
                rhs := parse_binary_expr(parser, prec +1);
                if rhs == nil do
                    syntax_error(op, "Expected expression after binary operator");
                expr = make_node(parser, Binary_Expr{op, expr, rhs});
            }
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
        case .Add, .Sub, .Not, .Bit_Not:
        op := consume(parser);
        return make_node(parser, Unary_Expr{op, parse_unary_expr(parser)});
        case: break;
    }
    
    return parse_postfix_expr(parser);
}

parse_postfix_expr :: proc(using parser: ^Parser) -> ^Node
{
    expr := parse_operand(parser);
    
    #partial switch peek(parser).kind
    {
        case .Open_Paren:
        open  := expect(parser, .Open_Paren);
        args  := parse_expr_list(parser);
        close := expect(parser, .Close_Paren);
        return make_node(parser, Call_Expr{expr, args, open, close});
    }
    
    return expr;
}

parse_operand :: proc(using parser: ^Parser) -> ^Node
{
    #partial switch peek(parser).kind
    {
        case .Ident:
        ident := make_node(parser, Ident{consume(parser)});
        return ident;
        
        case .Integer:
        tok := expect(parser, .Integer);
        res, ok := sconv.parse_i64(tok.text);
        return make_node(parser, Literal{tok, res});
        
        case .Float:
        tok := expect(parser, .Float);
        res, ok := sconv.parse_f64(tok.text);
        return make_node(parser, Literal{tok, res});
        
        case .Open_Paren:
        open  := expect(parser, .Open_Paren);
        expr  := parse_expr(parser);
        close := expect(parser, .Close_Paren);
        return make_node(parser, Paren_Expr{open, close, expr});
        
        case ._proc:
        tok := expect(parser, ._proc);
        
        // Wrapping scope
        new_scope := make_scope(scope);
        scope = new_scope;
        defer scope = scope.parent;
        
        expect(parser, .Open_Paren);
        
        params: []^Node;
        if peek(parser).kind != .Close_Paren
        {
            params = parse_var_list(parser);
            for p in params do scope_statement(scope, p);
        }
        expect(parser, .Close_Paren);
        ret: ^Node;
        if allow(parser, .Arrow) do
            ret = parse_type(parser);
        
        block := parse_block(parser);
        scope_statement(scope, block);
        
        proc_type := make_node(parser, Proc_Type{tok, params, ret});
        return make_node(parser, Proc{new_scope, proc_type, block});
        
        case: break;
    }
    
    return nil;
}
