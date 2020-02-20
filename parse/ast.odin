package parse

Node :: struct
{
    variant: union
    {
        Ident,
        Literal,

        Unary_Expr,
        Binary_Expr,
        Ternary_Expr,
        Paren_Expr,

        Assign_Stmt,
        Block_Stmt,
        Return_Stmt,
        If_Stmt,
        Proc,
        Var,
        Var_List,
    }
}

Ident :: struct
{
    token: Token,
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
    lhs, rhs : ^Node
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

Assign_Stmt :: struct
{
    op: Token,
    lhs, rhs: ^Node,
}

Block_Stmt :: struct
{
    open, close : Token,
    statements  : []^Node,
}

Return_Stmt :: struct
{
    tok: Token,
    expr: ^Node
}

If_Stmt :: struct
{
    tok: Token,
    cond: ^Node,
    block: ^Node,
    _else: ^Node,
}

Proc :: struct
{
    token: Token,
    params: ^Node,
    ret:    ^Node,
    block:  ^Node,
}

Var :: struct
{
    names: []^Node,
    type: ^Node,
    value: ^Node,
    is_const: bool,
}

Var_List :: struct
{
    list: []^Node,
}
