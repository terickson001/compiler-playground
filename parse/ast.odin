package parse

node_token :: proc(node: ^Node) -> Token
{
    assert(node != nil);
    switch v in node.variant
    {
        case Ident:        return v.token;
        
        case Literal:      return v.token;
        case Unary_Expr:   return v.op;
        case Binary_Expr:  return node_token(v.lhs);
        case Ternary_Expr: return node_token(v.cond);
        case Paren_Expr:   return v.open;
        case Call_Expr:    return node_token(v._proc);
        
        case Expr_Stmt:    return node_token(v.expr);
        case Assign_Stmt:  return node_token(v.lhs);
        case Block_Stmt:   return v.open;
        case Return_Stmt:  return v.token;
        case Jump_Stmt:    return v.token;
        case If_Stmt:      return v.token;
        case For_Stmt:     return v.token;
        
        case Proc_Type:    return v.token;
        case Proc:         return node_token(v.type);
        case Var:          return node_token(v.names[0]);
    }
    return {};
}

Node :: struct
{
    scope:  ^Scope,
    type:   ^Type,
    symbol: ^Symbol,
    
    variant: union
    {
        Ident,
        Literal,
        
        Unary_Expr,
        Binary_Expr,
        Ternary_Expr,
        Paren_Expr,
        Call_Expr,
        
        Expr_Stmt,
        Assign_Stmt,
        Block_Stmt,
        Return_Stmt,
        Jump_Stmt,
        If_Stmt,
        For_Stmt,
        
        Proc,
        Var,
        // Var_List,
        
        Proc_Type,
    }
}


Scope :: struct
{
    parent: ^Scope,
    statements: [dynamic]^Node,
    declarations: map[string]^Node,
    symbols: map[string]^Symbol,
}

make_scope :: inline proc(parent: ^Scope) -> ^Scope
{
    return new_clone(Scope{parent, make([dynamic]^Node), make(map[string]^Node), make(map[string]^Symbol)});
}

scope_statement :: inline proc(scope: ^Scope, stmt: ^Node)
{
    append(&scope.statements, stmt);
}


Ident :: struct
{
    token: Token,
}

ident_str :: inline proc(node: ^Node) -> string
{
    return node.variant.(Ident).token.text;
}

Value :: union
{
    i64,
    u64,
}

Literal :: struct
{
    token : Token,
    value : union
    {
        i64,
        f64,
    },
}

Unary_Expr :: struct
{
    op   : Token,
    expr : ^Node,
}

Binary_Expr :: struct
{
    op       : Token,
    lhs, rhs : ^Node,
}

Ternary_Expr :: struct
{
    cond  : ^Node,
    then  : ^Node,
    _else : ^Node,
}

Paren_Expr :: struct
{
    open, close : Token,
    expr        : ^Node,
}

Call_Expr :: struct
{
    _proc: ^Node,
    args: []^Node,
    open, close: Token,
}

Expr_Stmt :: struct
{
    expr: ^Node,
    test: ^Node,
}

Assign_Stmt :: struct
{
    op: Token,
    lhs, rhs: ^Node,
}

Block_Stmt :: struct
{
    open, close: Token,
    using scope: ^Scope,
}

Return_Stmt :: struct
{
    token: Token,
    expr:  ^Node,
}

Jump_Stmt :: struct
{
    token: Token,
}

If_Stmt :: struct
{
    token: Token,
    cond:  ^Node,
    block: ^Node,
    _else: ^Node,
}

For_Stmt :: struct
{
    token: Token,
    scope: ^Scope,
    init:  ^Node,
    cond:  ^Node,
    post:  ^Node,
    block: ^Node,
}

Proc_Type :: struct
{
    token: Token,
    params:  []^Node,
    _return: ^Node,
}

Proc :: struct
{
    scope: ^Scope,
    type:  ^Node,
    block: ^Node,
}

Var :: struct
{
    names:    []^Node,
    type:     ^Node,
    value:    ^Node,
    is_const: bool,
}

/*
Var_List :: struct
{
    list: []^Node,
}
*/
