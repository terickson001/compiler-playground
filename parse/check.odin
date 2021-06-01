package parse

import "core:fmt"
import "core:os"

Checker_Flag :: enum u8
{
    Allow_Break,
    Allow_Continue,
}
Checker_Flags :: bit_set[Checker_Flag];

Checker :: struct
{
    parser: Parser,
    current_proc: ^Node,
    curr_scope: ^Scope,
    builtins: map[string]^Symbol,
    flags: Checker_Flags,
    next_local_sym_id: u64,
    next_global_sym_id: u64,
}

Symbol_Kind :: enum u8
{
    Var,
    Type,
    Proc,
}

Symbol_Flag :: enum u8
{
    Builtin,
}

Symbol_Flags :: bit_set[Symbol_Flag];

Symbol :: struct
{
    local_uid: u64,
    global_uid: u64,
    name: string,
    decl: ^Node,
    type: ^Type,
    kind: Symbol_Kind,
    flags: Symbol_Flags,
    state: enum u8
    {
        Unresolved,
        Resolving,
        Resolved,
    },
    
    location: int,
}

checker_error :: proc(node: ^Node, fmt_str: string, args: ..any)
{
    tok := node_token(node);
    fmt.eprintf("%s(%d:%d): ERROR: %s\n", fmt.tprintf(fmt_str, args));
    os.exit(1);
}

install_builtins :: proc(using checker: ^Checker)
{
    for t in primitive_types
    {
        p := t.variant.(Type_Primitive);
        symbol := make_symbol(p.name, nil);
        symbol.type = t;
        symbol.flags |= {.Builtin};
        builtins[p.name] = symbol;
    }
}

make_symbol :: proc(name: string, node: ^Node) -> ^Symbol
{
    symbol := new(Symbol);
    symbol.name = name;
    symbol.decl = node;
    if node != nil do node.symbol = symbol;
    return symbol;
}

make_checker :: proc(parser: Parser) -> (checker: Checker)
{
    checker.parser = parser;
    install_builtins(&checker);
    return checker;
}

check_scope :: proc(using checker: ^Checker, scope: ^Scope)
{
    prev_scope := checker.curr_scope;
    defer checker.curr_scope = prev_scope;
    checker.curr_scope = scope;
    for stmt in scope.statements 
    {
        check_statement(checker, stmt);
    }
}

check_statement :: proc(using checker: ^Checker, stmt: ^Node)
{
    #partial switch v in stmt.variant
    {
        case Expr_Stmt:
        check_expr(checker, v.expr);
        stmt.type = v.expr.type;
        
        case Assign_Stmt:
        check_expr(checker, v.lhs);
        check_expr(checker, v.rhs);
        assert(v.lhs.type == v.rhs.type);
        
        case Block_Stmt:
        check_scope(checker, v.scope);
        
        case Return_Stmt:
        check_expr(checker, v.expr);
        
        case Jump_Stmt:
        #partial switch v.token.kind
        {
            case ._break:
            if .Allow_Break not_in flags 
            {
                checker_error(stmt, "'break' not allowed in this scope");
            }
            
            case ._continue:
            if .Allow_Continue not_in flags 
            {
                checker_error(stmt, "'continue' not allowed in this scope");
            }
        }
        
        case If_Stmt:
        check_expr(checker, v.cond);
        assert(type_is_boolean(v.cond.type), "If statement condition must be a boolean expression");
        
        check_statement(checker, v.block);
        if v._else!= nil 
        {
            check_statement(checker, v._else);
        }
        
        case For_Stmt:
        // Enter Scope
        prev_scope := checker.curr_scope;
        checker.curr_scope = v.scope;
        defer checker.curr_scope = prev_scope;
        
        // Set Flags
        prev_flags := checker.flags;
        checker.flags |= {.Allow_Break, .Allow_Continue};
        defer checker.flags = prev_flags;
        
        check_statement(checker, v.init);
        check_statement(checker, v.cond);
        assert(type_is_boolean(v.cond.type), "For statement condition must be a boolean expression");
        check_statement(checker, v.post);
        
        check_statement(checker, v.block);
        
        case Var: 
        check_declaration(checker, stmt);
    }
}


check_declaration :: proc(using checker: ^Checker, decl: ^Node)
{
    assert(decl != nil);
    #partial switch v in &decl.variant
    {
        case Var:
        assert(v.type != nil || v.value != nil, "Variable declaration must have a type or value");
        if v.type != nil 
        {
            check_type(checker, v.type);
        }
        if v.value != nil 
        {
            check_expr(checker, v.value);
        }
        if v.type != nil && v.value != nil 
        {
            assert(v.type.type == v.value.type);
        }
        if v.type == nil do v.type = v.value;
        decl.type = v.type.type;
        
        if v.value != nil
        {
            if _proc, ok := v.value.variant.(Proc); ok 
            {
                check_statement(checker, _proc.block);
            }
        }
        
        case: 
        unreachable();
    }
}

check_type :: proc(using checker: ^Checker, type: ^Node)
{
    #partial switch v in type.variant
    {
        case Ident:
        symbol := check_name(checker, type);
        type.type = symbol.type;
        
        case Proc_Type:
        param_types: []^Type;
        if v.params != nil
        {
            temp_param_types := make([dynamic]^Type);
            for p in v.params
            {
                check_declaration(checker, p);
                append(&temp_param_types, p.type);
            }
            param_types = temp_param_types[:];
        }
        ret_type: ^Type;
        if v._return != nil
        {
            check_type(checker, v._return);
            ret_type = v._return.type;
        }
        type.type = proc_type(param_types, ret_type);
    }
}

literal_type :: proc(lit: Literal) -> ^Type
{
    switch v in lit.value
    {
        case i64: return &type__i64;
        case f64: return nil;
    }
    return nil;
}

check_expr :: proc(using checker: ^Checker, expr: ^Node)
{
    #partial switch v in expr.variant
    {
        case Literal:
        expr.type = literal_type(v);
        
        case Ident:
        symbol := check_name(checker, expr);
        expr.type = symbol.type;
        
        case Unary_Expr:
        check_expr(checker, v.expr);
        if v.op.kind == .Not 
        {
            expr.type = &type__bool;
        }
        else 
        {
            expr.type = v.expr.type;
        }
        
        case Binary_Expr:
        check_expr(checker, v.lhs);
        check_expr(checker, v.rhs);
        assert(v.lhs.type == v.rhs.type);
        #partial switch v.op.kind
        {
            case (.__CMP_BEGIN)..(.__CMP_END):
            expr.type = &type__b64;
            case:
            expr.type = v.lhs.type;
        }
        
        case Ternary_Expr:
        check_expr(checker, v.cond);
        assert(type_is_boolean(v.cond.type), "Ternary expression condition must be a boolean");
        
        check_expr(checker, v.then);
        check_expr(checker, v._else);
        assert(v.then.type == v._else.type, "Type mismatch in ternary results");
        expr.type = v.then.type;
        
        case Paren_Expr:
        check_expr(checker, v.expr);
        expr.type = v.expr.type;
        
        case Proc:
        check_type(checker, v.type);
        expr.type = v.type.type;
        assert(expr.type != nil);
        
        case Call_Expr:
        symbol := check_name(checker, v._proc);
        for arg in v.args 
        {
            check_expr(checker, arg);
        }
        // @todo(tyler): Check parameter types
        expr.type = symbol.type.variant.(Type_Proc)._return;
        
    }
}

check_name :: proc(using checker: ^Checker, ident: ^Node) -> ^Symbol
{
    symbol := lookup_symbol(checker, checker.curr_scope, ident);
    if .Builtin not_in symbol.flags 
    {
        resolve_symbol(checker, symbol);
    }
    ident.symbol = symbol;
    return symbol;
}

lookup_symbol :: proc(using checker: ^Checker, scope: ^Scope, ident: ^Node) -> ^Symbol
{
    name := ident_str(ident);
    for curr := scope; curr != nil; curr = curr.parent
    {
        if symbol, ok := curr.symbols[name]; ok 
        {
            sym_loc := node_token(symbol.decl).loc;
            ident_loc := node_token(ident).loc;
            
            if curr.parent != nil && loc_cmp(sym_loc, ident_loc) < 0 
            {
                continue;
            }
            return symbol;
        }
    }
    if symbol, ok := checker.builtins[name]; ok 
    {
        return symbol;
    }
    fmt.eprintf("Symbol %q not found\n", name);
    os.exit(1);
}

resolve_symbol :: proc(using checker: ^Checker, symbol: ^Symbol)
{
    fmt.printf("Resolving symbol: %q(%d)\n", symbol.name, node_token(symbol.decl).line);
    if symbol.state == .Resolved do return;
    if symbol.state == .Resolving
    {
        fmt.eprintf("Cyclic dependency for symbol %q\n", symbol.name);
        os.exit(1);
    }
    symbol.state = .Resolving;
    check_declaration(checker, symbol.decl);
    symbol.state = .Resolved;
    symbol.type = symbol.decl.type;
}


install_symbols :: proc(using checker: ^Checker, scope: ^Scope)
{
    for stmt in scope.statements
    {
        #partial switch v in stmt.variant
        {
            case Block_Stmt:
            install_symbols(checker, v.scope);
            
            case For_Stmt:
            install_symbols(checker, v.scope);
            
            case If_Stmt:
            install_symbols(checker, v.block.variant.(Block_Stmt).scope);
            
            case Var:
            for name in v.names
            {
                str_name := ident_str(name);
                symbol := make_symbol(str_name, stmt);
                symbol.global_uid = checker.next_global_sym_id;
                checker.next_global_sym_id += 1;
                if checker.current_proc != nil
                {
                    symbol.local_uid = checker.next_local_sym_id;
                    checker.next_local_sym_id += 1;
                }
                name.symbol = symbol;
                symbol.kind = .Var;
                fmt.printf("Adding symbol: %q(%d:%d)\n", str_name, symbol.global_uid, symbol.local_uid);
                if v.value != nil
                {
                    #partial switch v in v.value.variant
                    {
                        case Proc:
                        checker.current_proc = stmt;
                        checker.next_local_sym_id = 0;
                        symbol.kind = .Proc;
                        install_symbols(checker, v.scope);
                    }
                }
                scope.symbols[str_name] = symbol;
            }
        }
    }
}

check_file :: proc(using checker: ^Checker)
{
    install_symbols(checker, parser.files[0].scope);
    check_scope(checker, parser.files[0].scope);
}
