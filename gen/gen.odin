package gen

import "core:fmt"

import "../parse"
Value :: parse.Value;

Generator :: struct
{
    decls: []^parse.Node,

    using scope: ^Scope,
    scopes: [dynamic]Scope,
}

Variable :: struct
{
    offset: int,
    val: Value,
}

Scope :: struct
{
    parent: ^Scope,
    
    variables: map[string]Variable,
    stack_offset: int,
}

push_scope :: proc(using gen: ^Generator, inherit := true)
{
    new_scope := Scope{};
    if inherit
    {
        new_scope.parent = scope;
        new_scope.stack_offset = scope.stack_offset;
    }

    new_scope.variables = make(map[string]Variable);
    append(&scopes, new_scope);
}

pop_scope :: proc(using gen: ^Generator)
{
    delete(scope.variables);
    resize(&scopes, len(scopes)-1);
    scope = &scopes[len(scopes)-1];
}

Var_Status :: enum
{
    Not_Found,
    Current_Scope,
    Parent_Scope,
}

find_var :: proc(using gen: ^Generator, name: string) -> (var: Variable, status: Var_Status)
{
    curr_scope := scope;
    for scope != nil
    {
        ok: bool;
        var, ok = curr_scope.variables[name];
        if ok
        {
            status = (curr_scope == scope) ? .Current_Scope : .Parent_Scope;
            return var, status;
        }

        curr_scope = curr_scope.parent;
    }
    return var, status;
}

make_generator :: proc(decls: []^parse.Node) -> Generator
{
    gen := Generator{};
    
    gen.decls = decls;
    gen.scopes = make([dynamic]Scope);
    
    return gen;
}

generate_rtl :: proc(using gen: ^Generator)
{
    
}
