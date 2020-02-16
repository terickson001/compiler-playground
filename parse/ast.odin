package parse

Node :: struct
{
    variant: union
    {
        Ident,
        Literal,

        Unary_Expr,
        Binary_Expr,
        Paren_Expr,
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

Paren_Expr :: struct
{
    open, close : Token,
    expr        : ^Node,
}
