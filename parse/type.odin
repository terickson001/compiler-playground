package parse

import "core:fmt"
import hash "core:hash"
import rt "core:runtime"
import "core:mem"

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
        Type_Named,
        Type_Proc,
    },
    size: int,
}

Type_Primitive :: struct
{
    kind: Primitive_Kind,
    name: string,
    flags: Primitive_Flags,
    size: int,
}

Type_Named :: struct
{
    name: string,
    base: ^Type,
}

Type_Proc :: struct
{
    params:   []^Type,
    _return: ^Type,
}

@static type__i8  := Type{Type_Primitive{.i8,  "i8" , {.Integer},  1}, 1};
@static type__i16 := Type{Type_Primitive{.i16, "i16", {.Integer},  2}, 2};
@static type__i32 := Type{Type_Primitive{.i32, "i32", {.Integer},  4}, 4};
@static type__i64 := Type{Type_Primitive{.i64, "i64", {.Integer},  8}, 8};
@static type__int := Type{Type_Primitive{.int, "int", {.Integer}, -1}, -1};

@static type__u8   := Type{Type_Primitive{.u8,   "u8" ,  {.Integer},  1}, 1};
@static type__u16  := Type{Type_Primitive{.u16,  "u16",  {.Integer},  2}, 2};
@static type__u32  := Type{Type_Primitive{.u32,  "u32",  {.Integer},  4}, 4};
@static type__u64  := Type{Type_Primitive{.u64,  "u64",  {.Integer},  8}, 8};
@static type__uint := Type{Type_Primitive{.uint, "uint", {.Integer}, -1}, -1};

@static type__b8   := Type{Type_Primitive{.b8,   "b8" ,  {.Boolean}, 1}, 1};
@static type__b16  := Type{Type_Primitive{.b16,  "b16",  {.Boolean}, 2}, 2};
@static type__b32  := Type{Type_Primitive{.b32,  "b32",  {.Boolean}, 4}, 4};
@static type__b64  := Type{Type_Primitive{.b64,  "b64",  {.Boolean}, 8}, 8};
@static type__bool := Type{Type_Primitive{.bool, "bool", {.Boolean}, 1}, 1};

@static primitive_types := [?]^Type
{
    &type__i8,
    &type__i16,
    &type__i32,
    &type__i64,
    &type__int,
    
    &type__u8,
    &type__u16,
    &type__u32,
    &type__u64,
    &type__uint,
    
    &type__b8,
    &type__b16,
    &type__b32,
    &type__b64,
    &type__bool,
};

type_is_primitive_class :: proc(type: ^Type, flag: Primitive_Flag) -> bool
{
    #partial switch v in type.variant
    {
        case Type_Primitive:
        return flag in v.flags;
    }
    
    return false;
}

type_is_boolean :: proc(type: ^Type) -> bool
{
    return type_is_primitive_class(type, .Boolean);
}

type_is_integer :: proc(type: ^Type) -> bool
{
    return type_is_primitive_class(type, .Integer);
}

type_is_float :: proc(type: ^Type) -> bool
{
    return type_is_primitive_class(type, .Float);
}

type_is_string :: proc(type: ^Type) -> bool
{
    return type_is_primitive_class(type, .String);
}

type_is_untyped :: proc(type: ^Type) -> bool
{
    return type_is_primitive_class(type, .Untyped);
}

hash_mix :: proc(a, b: u64) -> u64
{
    data := transmute([16]u8)[2]u64{a, b};
    return hash.crc64(data[:]);
}

hash_multi :: proc(args: ..any) -> u64
{
    res: u64;
    for a, i in args
    {
        new_hash: u64;
        ti := rt.type_info_base(type_info_of(a.id));
        #partial switch v in ti.variant
        {
            case rt.Type_Info_Slice: 
            slice := cast(^rt.Raw_Slice)a.data;
            bytes := mem.slice_ptr(cast(^byte)slice.data, slice.len * v.elem_size);
            new_hash = hash.crc64(bytes);
            
            case:
            bytes := mem.slice_ptr(cast(^byte)a.data, ti.size);
            new_hash = hash.crc64(bytes);
        }
        
        if i != 0 
        {
            res = hash_mix(res, new_hash);
        }
        else 
        {
            res = new_hash;
        }
    }
    
    return res;
}

cache_type :: proc(type_map: ^map[u64]^Type, type: ^Type, args: ..any)
{
    key := hash_multi(args);
    type_map[key] = type;
}

get_cached_type :: proc(type_map: map[u64]^Type, args: ..any) -> ^Type
{
    key := hash_multi(args);
    type, ok := type_map[key];
    if !ok 
    {
        return nil;
    }
    return type;
}


make_type :: proc(variant: $T) -> ^Type
{
    type := new(Type);
    type.variant = variant;
    return type;
}

@static cached_proc_types: map[u64]^Type;
proc_type :: proc(params: []^Type, ret: ^Type) -> ^Type
{
    type := get_cached_type(cached_proc_types, params, ret);
    if type != nil 
    {
        return type;
    }
    
    type = make_type(Type_Proc{params, ret});
    type.size = 8; // @hack(tyler): Actually determine pointer size
    cache_type(&cached_proc_types, type, params, ret);
    return type;
}