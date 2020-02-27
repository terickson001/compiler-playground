package parse

import "core:fmt"

Primitive_Flag :: enum
{
    Integer = 1<<0,
    Float   = 1<<1,
    String  = 1<<2,
    Boolean = 1<<3,
    Untyped = 1<<4,
}
Primitive_Flags :: bit_set[Primitive_Flag];

Primitive_Kind :: enum
{
    i8,
    i16,
    i32,
    i64,
    int,
    
    u8,
    u16,
    u32,
    u64,
    uint,

    b8,
    b16,
    b32,
    b64,
    bool,
}

Type :: struct
{
    variant: union
    {
        Type_Primitive,
    },size: int,
}

Type_Primitive :: struct
{
    kind: Primitive_Kind,
    name: string,
    flags: Primitive_Flags,
    size: int,
}
@static primitive_types: [?]Type
{
    Type{Type_Primitive{.i8,  "i8" , {.Integer},  1}},
    Type{Type_Primitive{.i16, "i16", {.Integer},  2}},
    Type{Type_Primitive{.i32, "i32", {.Integer},  4}},
    Type{Type_Primitive{.i64, "i64", {.Integer},  8}},
    Type{Type_Primitive{.int, "int", {.Integer}, -1}},

    Type{Type_Primitive{.u8,   "u8" ,  {.Integer},  1}},
    Type{Type_Primitive{.u16,  "u16",  {.Integer},  2}},
    Type{Type_Primitive{.u32,  "u32",  {.Integer},  4}},
    Type{Type_Primitive{.u64,  "u64",  {.Integer},  8}},
    Type{Type_Primitive{.uint, "uint", {.Integer}, -1}},

    Type{Type_Primitive{.b8,   "b8" ,  {.Boolean},  1}},
    Type{Type_Primitive{.b16,  "b16",  {.Boolean}, 2}},
    Type{Type_Primitive{.b32,  "b32",  {.Boolean}, 4}},
    Type{Type_Primitive{.b64,  "b64",  {.Boolean}, 8}},
    Type{Type_Primitive{.bool, "bool", {.Boolean}, 1}},
}

type_is_boolean :: proc(type: ^Type)
{
    #partial switch v in type.variant
    {
    case Type_Primitive:
        return .Boolean in v.flags;
    }

    return false;
}
