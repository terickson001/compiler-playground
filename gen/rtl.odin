package gen

import "core:fmt"
import "../parse"

Program :: [dynamic]Instruction;

Instruction :: union
{
    Label,
    Assign,
    Assign_Unary,
    Assign_Binary,
    Mem_Load,
    Mem_Store,
    Jump,
    Cond_Jump,
    Call,
}

Register :: int;

Unary_Op :: enum
{
    Sub,
    Inc,
    Dec,
    Not,
    Bit_Not,
}

Binary_Op :: enum
{
    Add,
    Sub,
    Mul,
    Quo,
    Mod,
    
    Bit_And,
    Bit_Or,
    Xor,
    Shl,
    Shr,

    And,
    Or,
}

Rel_Op :: struct
{
    EQ,
    NE,
    LT,
    GT,
    LE,
    GE,
}

Atom :: union
{
    Value,
    Register,
}

Label :: struct
{
    name: string,
}

Assign :: struct
{
    id: Register,
    op: Atom,
}

Assign_Unary :: struct
{
    store: Register,
    op: Unary_Op,
    operand: Atom,
}

Assign_Binary :: struct
{
    id: Register,
    op: Binary_Op,
    lhs: Register,
    rhs: Atom,
}

Mem_Load :: struct
{
    store: Register,
    location: Atom,
}

Mem_Store :: struct
{
    source: Register,
    location: Atom,
}

Jump :: struct
{
    label: string,
}

Cond_Jump :: struct
{
    op: Rel_Op,
    lhs: Register,
    rhs: Atom,

    then: string,
    _else: string,
}

Call :: struct
{
    store: Register,
    _proc: string,
    args: []Register,
}
