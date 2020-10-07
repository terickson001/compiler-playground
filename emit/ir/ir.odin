package ir

import "../../parse"
import "core:fmt"

Statement :: struct
{
    scope: ^Scope,
    block: ^Block,
    variant: union
    {
        Op,
        Call,
        Return,
        Jump,
        CJump,
        Label,
        ^Scope, 
        ProcExtern,
    },
    
    next: ^Statement,
    prev: ^Statement,
}


/**** OPERANDS ****/
Operand :: union
{
    Immediate,
    Variable,
    Procedure,
    Label_Name,
}

Type :: parse.Type;

Procedure :: struct
{
    name:     string,
    params:   []^Operand,
    ret_type: ^Type,
}

Value :: union
{
    i64,
    f64,
}

Immediate :: struct
{
    val:  Value,
    type: ^Type,
}

Variable :: struct
{
    scope: ^Scope,
    name:  string,
    type:  ^Type,
    symbol: ^parse.Symbol,
}

Label_Name :: struct
{
    scope: ^Scope,
    name: string,
    idx: u64,
}

/**** STATEMENTS ****/

Call :: struct
{
    _proc:    ^Operand,
    args:     []^Operand,
    dest:     ^Operand,
}

Op :: struct
{
    kind: Op_Kind,
    dest: ^Operand,
    operands: [2]^Operand,
}

Op_Kind :: enum u8
{
    None,
    
    // Unary
    Identity,
    Parameter,
    Neg,
    Not,
    BitNot,
    
    // Binary
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    
    Xor,
    And,
    Or,
    Shl,
    Shr,
    
    CmpAnd,
    CmpOr,
    Eq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    
    _UN_OP_BEGIN  = Identity,
    _UN_OP_END    = BitNot,
    _BIN_OP_BEGIN = Add,
    _BIN_OP_END   = GtEq,
    _REL_OP_BEGIN = CmpAnd,
    _REL_OP_END   = GtEq,
}

Return :: struct
{
    var: ^Operand
}

Jump :: struct
{
    label: ^Operand,
}

CJump :: struct
{
    kind:  Op_Kind,
    ops: [2]^Operand,
    then:  ^Operand,
    _else: ^Operand,
}

Label :: struct
{
    name: ^Operand,
}

Scope :: struct
{
    // vars: map[string]^Operand,
    parent: ^Scope,
    vars: [dynamic]^Operand,
    statements: Statement_List,
}

make_scope :: proc(scope: ^Scope) -> ^Scope
{
    new_scope := new(Scope);
    new_scope.parent = scope;
    return new_scope;
}

ProcDef :: struct
{
    decl: ^Operand,
    scope: ^Statement,
}

ProcExtern :: struct
{
    decl: ^Operand,
}

Emitter :: struct
{
    file_scope: ^parse.Scope,
    
    break_label: string,
    continue_label: string,
    
    label_counts: map[string]int,
    _procs: [dynamic]ProcDef,
    curr_scope: ^Scope,
    var_counter: u64,
    
    indent_level: u8,
}

make_emitter :: proc(file_scope: ^parse.Scope) -> (emitter: Emitter)
{
    emitter.file_scope = file_scope;
    return emitter;
}

ir_op_kind :: proc(token: parse.Token, unary := false) -> Op_Kind
{
    #partial switch token.kind
    {
        case .Add: return unary ? .None : .Add;
        case .Sub: return unary ? .Neg  : .Sub;
        case .Mul: return unary ? .None : .Mul;
        case .Quo: return unary ? .None : .Div;
        case .Mod: return unary ? .None : .Mod;
        
        case .Bit_Not: return unary ? .BitNot : .None;
        case .Bit_And: return unary ? .None : .And;
        case .Bit_Or:  return unary ? .None : .Or;
        case .Xor:     return unary ? .None : .Xor;
        case .Shl:     return unary ? .None : .Shl;
        case .Shr:     return unary ? .None : .Shr;
        
        case .Not: return unary ? .Not  : .None;
        case .And: return unary ? .None : .CmpAnd;
        case .Or: return unary ? .None : .CmpOr;
        case .CmpEq: return unary ? .None : .Eq;
        case .NotEq: return unary ? .None : .NotEq;
        case .Lt: return unary ? .None : .Lt;
        case .LtEq: return unary ? .None : .LtEq;
        case .Gt: return unary ? .None : .Gt;
        case .GtEq: return unary ? .None : .GtEq;
    }
    return .None;
}

ir_type :: proc(using emitter: ^Emitter, node: ^parse.Node) -> ^Type
{
    if node == nil do return nil;
    return node.type;
}

ir_params :: proc(using emitter: ^Emitter, nodes: []^parse.Node) -> []^Operand
{
    if len(nodes) == 0 do return nil;
    ops:= make([dynamic]^Operand, 0, len(nodes));
    
    for n in nodes
    {
        var := n.variant.(parse.Var);
        for name in var.names do
            append(&ops, ir_var_operand(emitter, name));
    }
    
    return ops[:];
}

@static cached_proc_types: map[string]^Operand;
ir_proc_type :: proc(using emitter: ^Emitter, name: string, node: ^parse.Node) -> ^Operand
{
    if proc_type, ok := cached_proc_types[name]; ok do
        return proc_type;
    
    type    := node.variant.(parse.Proc_Type);
    params  := ir_params(emitter, type.params);
    _return := ir_type(emitter, type._return);
    operand := new(Operand);
    operand^ = Procedure{name, params, _return};
    cached_proc_types[name] = operand;
    return operand;
}

ir_lit :: proc(using emitter: ^Emitter, node: ^parse.Node) -> ^Operand
{
    lit_node := node.variant.(parse.Literal);
    imm := Immediate{{}, ir_type(emitter, node)};
    switch v in lit_node.value
    {
        case i64: imm.val = v;
        case f64: imm.val = v;
    }
    op := new(Operand);
    op^ = imm;
    return op;
}

ir_var_operand :: proc(using emitter: ^Emitter, node: ^parse.Node, require_new := false) -> ^Operand
{
    /*
        recent_var: ^Operand;
        for scope := curr_scope; scope != nil; scope = scope.parent
        {
            for v in scope.vars
            {
                var := v.(Variable);
                if var.name == parse.ident_str(node)
                {
                    if recent_var == nil do
                        recent_var = v;
                    else do
                        recent_var = recent_var.(Variable).idx < var.idx ? v : recent_var;
                }
            }
        }
        
        if recent_var != nil
        {
            
                    if require_new
                    {
                        op := new(Operand);
                        new_var := recent_var.(Variable);
                        new_var.idx = emitter.var_counter;
                        op^ = new_var;
                        emitter.var_counter += 1;
                        if require_new do
                            append(&curr_scope.vars, op);
                        return op;
                    }
            
            return recent_var;
        }
    */
    
    op := new(Operand);
    op^ = Variable{
        curr_scope, 
        parse.ident_str(node), 
        ir_type(emitter, node.symbol.decl),
        node.symbol};
    // emitter.var_counter += 1;
    if require_new do
        append(&curr_scope.vars, op);
    return op;
}

ir_temp_var :: proc(using emitter: ^Emitter, type: ^Type) -> ^Operand
{
    op := new(Operand);
    op^ = Variable{emitter.curr_scope, fmt.aprintf(".t.%d", emitter.var_counter), type, nil};
    append(&curr_scope.vars, op);
    emitter.var_counter += 1;
    return op;
}

ir_new_label :: proc(using emitter: ^Emitter, name: string) -> ^Operand
{
    op := new(Operand);
    op^ = Label_Name{curr_scope, name, emitter.var_counter};
    emitter.var_counter += 1;
    return op;
}

ir_arg :: proc(using emitter: ^Emitter, node: ^parse.Node) -> ^Operand
{
    return ir_expr(emitter, node);
}

ir_expr :: proc(using emitter: ^Emitter, node: ^parse.Node, dest: ^Operand = nil) -> ^Operand
{
    dest := dest;
    using parse;
    stmt: Statement;
    #partial switch v in node.variant
    {
        case Literal: 
        op := ir_lit(emitter, node);
        if dest != nil do
            stmt.variant = Op{.Identity, dest, {op, nil}};
        else do 
            return op;
        case Ident: return ir_var_operand(emitter, node);
        
        case Unary_Expr:
        operand := ir_expr(emitter, v.expr);
        if dest == nil do
            dest = ir_temp_var(emitter, ir_type(emitter, node));
        stmt.variant = Op{ir_op_kind(v.op, true), dest, {operand, nil}};
        
        case Binary_Expr:
        lhs := ir_expr(emitter, v.lhs);
        rhs := ir_expr(emitter, v.rhs);
        if dest == nil do
            dest = ir_temp_var(emitter, ir_type(emitter, node));
        stmt.variant = Op{ir_op_kind(v.op), dest, {lhs, rhs}};
        
        case Paren_Expr:
        operand := ir_expr(emitter, v.expr, dest);
        return operand;
        
        case Call_Expr:
        proc_type := ir_proc_type(emitter, ident_str(v._proc), v._proc.symbol.decl.variant.(Var).value.variant.(Proc).type);
        args := make([]^Operand, len(proc_type.(Procedure).params));
        for arg, i in v.args do
            args[i] = ir_arg(emitter, arg);
        if dest == nil do
            dest = ir_temp_var(emitter, ir_type(emitter, node));
        stmt.variant = Call{proc_type, args, dest};
    }
    push_statement(&curr_scope.statements, new_clone(stmt));
    return dest;
}

ir_cjump :: proc(using emitter: ^Emitter, node: ^parse.Node) -> CJump
{
    assert(parse.type_is_boolean(node.type));
    jump: CJump;
    jump.then  = ir_new_label(emitter, ".THEN");
    jump._else = ir_new_label(emitter, ".ELSE");
    #partial switch v in node.variant
    {
        case parse.Literal:
        jump.ops[0] = ir_expr(emitter, node);
        imm:= new(Operand);
        imm^ = Immediate{i64(0), &parse.type__i64};
        jump.ops[1] = imm;
        jump.kind = .NotEq;
        
        case parse.Unary_Expr:
        jump.ops[0] = ir_expr(emitter, v.expr);
        jump.kind = ir_op_kind(v.op);
        
        case parse.Binary_Expr:
        jump.ops[0] = ir_expr(emitter, v.lhs);
        jump.ops[1] = ir_expr(emitter, v.rhs);
        jump.kind = ir_op_kind(v.op);
    }
    return jump;
}

ir_label_statement :: proc(using emitter: ^Emitter, lbl: ^Operand)
{
    stmt := new(Statement);
    stmt.scope = curr_scope;
    stmt.variant = Label{lbl};
    push_statement(&curr_scope.statements, stmt);
}

import "core:reflect"
ir_statement :: proc(using emitter: ^Emitter, node: ^parse.Node)
{
    using parse;
    //fmt.printf("Check Statement: %v\n", reflect.union_variant_typeid(node.variant));
    #partial switch v in node.variant
    {
        case Var:
        for name in v.names
        {
            dest := ir_var_operand(emitter, name, true);
            src := ir_expr(emitter, v.value, dest);
        }
        
        case Assign_Stmt:
        dest := ir_var_operand(emitter, v.lhs, true);
        src  := ir_expr(emitter, v.rhs, dest);
        
        case Return_Stmt:
        ret := new(Statement);
        ret.scope = curr_scope;
        ret.variant = Return{ir_expr(emitter, v.expr)};
        push_statement(&curr_scope.statements, ret);
        
        case If_Stmt:
        cond := ir_cjump(emitter, v.cond);
        stmt := new(Statement);
        stmt.scope = curr_scope;
        stmt.variant = cond;
        push_statement(&curr_scope.statements, stmt);
        ir_label_statement(emitter, cond.then);
        ir_statement(emitter, v.block);
        ir_label_statement(emitter, cond._else);
        if v._else != nil do
            ir_statement(emitter, v._else);
        
        case Block_Stmt:
        stmt := ir_scope(emitter, v.scope);
        push_statement(&curr_scope.statements, stmt);
        
        case Expr_Stmt:
        ir_expr(emitter, v.expr);
    }
}

ir_scope :: proc(using emitter: ^Emitter, scope: ^parse.Scope) -> ^Statement
{
    new_scope := make_scope(curr_scope);
    curr_scope = new_scope;
    for stmt in scope.statements do
        ir_statement(emitter, stmt);
    curr_scope = curr_scope.parent;
    stmt := new(Statement);
    stmt.scope = curr_scope;
    stmt.variant = new_scope;
    return stmt;
}

ir_proc_def :: proc(using emitter: ^Emitter, node: ^parse.Node) -> ProcDef
{
    var := node.variant.(parse.Var);
    assert(len(var.names) == 1);
    _proc := var.value.variant.(parse.Proc);
    
    new_scope := make_scope(curr_scope);
    curr_scope = new_scope;
    
    decl := ir_proc_type(emitter, parse.ident_str(var.names[0]), _proc.type);
    #partial switch v in decl
    {
        case Procedure:
        for p in v.params do
            append(&curr_scope.vars, p);
        case: unreachable();
    }
    block := ir_scope(emitter, _proc.block.variant.(parse.Block_Stmt).scope);
    push_statement(&curr_scope.statements, block);
    
    curr_scope = curr_scope.parent;
    outer_block := new(Statement);
    outer_block.scope = curr_scope;
    outer_block.variant = new_scope;
    
    return ProcDef{decl, outer_block};
}

emit_file :: proc(using emitter: ^Emitter)
{
    for stmt in file_scope.statements
    {
        #partial switch v in stmt.variant
        {
            case parse.Var:
            if v.value == nil do continue;
            if _, ok := v.value.variant.(parse.Proc); ok do
                append(&_procs, ir_proc_def(emitter, stmt));
        }
    }
    
    o := Optimizer{};
    for p in &_procs
    {
        fmt.printf("CURRENT PROC: %v\n", p);
        o.current_proc = &p;
        flatten_scopes(&o);
        build_flow_graph(&o);
    }
    ir_print(emitter);
}