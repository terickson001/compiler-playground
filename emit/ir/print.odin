package ir

import "core:fmt"

ir_indent :: proc(using emitter: ^Emitter)
{
    for i in 0..<indent_level do
        fmt.printf("    ");
}

ir_print :: proc(using emitter: ^Emitter)
{
    for _proc in &_procs
    {
        ir_print_proc_type(emitter, _proc.decl);
        fmt.printf(" ");
        if _proc.blocks.count > 0 do
            ir_print_proc_def(emitter, &_proc);
        else do
            ir_print_scope(emitter, _proc.scope);
        fmt.printf("\n\n");
    }
}

ir_print_proc_def :: proc(using emitter: ^Emitter, _proc: ^ProcDef)
{
    fmt.printf("{{\n");
    emitter.indent_level += 1;
    for block := _proc.blocks.head; block != nil; block = block.next
    {
        for stmt := block.statements.head; stmt != nil; stmt = stmt.next
        {
            ir_print_statement(emitter, stmt);
            fmt.printf("\n");
        }
    }
    emitter.indent_level -= 1;
    fmt.printf("}}\n");
}

ir_print_proc_type :: proc(using emitter: ^Emitter, op: ^Operand)
{
    proc_type := op.(Procedure);
    fmt.printf("$%s(", proc_type.name);
    for p, i in proc_type.params
    {
        if i != 0 do
            fmt.printf(", ");
        ir_print_var(emitter, p);
    }
    fmt.printf(")");
    if proc_type.ret_type != nil 
    {
        fmt.printf(" ");
        ir_print_type(emitter, proc_type.ret_type);
    }
}

ir_print_scope :: proc(using emitter: ^Emitter, stmt: ^Statement)
{
    indent_level += 1;
    scope := stmt.variant.(^Scope);
    fmt.printf("{{\n");
    for v in scope.vars
    {
        ir_indent(emitter);
        ir_print_var(emitter, v);
        fmt.printf("\n");
    }
    if scope.vars != nil do
        fmt.printf("\n");
    for s := scope.statements.head; s != nil; s = s.next
    {
        ir_print_statement(emitter, s);
        fmt.printf("\n");
    }
    indent_level -= 1;
    ir_indent(emitter);
    fmt.printf("}}");
}

ir_print_statement :: proc(using emitter: ^Emitter, stmt: ^Statement)
{
    #partial switch v in stmt.variant
    {
        case Op:
        ir_indent(emitter);
        fmt.printf("op [%v, ", v.kind);
        ir_print_var(emitter, v.dest);
        fmt.printf(", ");
        ir_print_operand(emitter, v.operands[0]);
        fmt.printf(", ");
        ir_print_operand(emitter, v.operands[1]);
        fmt.printf("]");
        
        case Call:
        ir_indent(emitter);
        fmt.printf("call [");
        _proc := v._proc.(Procedure);
        ir_print_type(emitter, _proc.ret_type);
        fmt.printf(" $%s, ", _proc.name);
        ir_print_var(emitter, v.dest);
        fmt.printf(", [");
        for a, i in v.args
        {
            if i > 0 do
                fmt.printf(", ");
            ir_print_operand(emitter, a);
        }
        fmt.printf("]]");
        
        case Return:
        ir_indent(emitter);
        fmt.printf("ret [");
        ir_print_operand(emitter, v.var);
        fmt.printf("]");
        
        case ^Scope:
        ir_indent(emitter);
        ir_print_scope(emitter, stmt);
        
        case Label:
        fmt.printf("label [");
        ir_print_operand(emitter, v.name);
        fmt.printf("]:");
        
        case Jump:
        // ir_indent(emitter);
        unreachable();
        
        case CJump:
        ir_indent(emitter);
        fmt.printf("cjump [%v, ", v.kind);
        ir_print_operand(emitter, v.ops[0]);
        fmt.printf(", ");
        ir_print_operand(emitter, v.ops[1]);
        fmt.printf(", ");
        ir_print_operand(emitter, v.then);
        fmt.printf(", ");
        ir_print_operand(emitter, v._else);
        fmt.printf("]");
    }
}

ir_print_operand :: proc(using emitter: ^Emitter, op: ^Operand)
{
    if op == nil do return;
    #partial switch v in op
    {
        case Variable: ir_print_var(emitter, op);
        case Immediate: 
        switch t in v.val
        {
            case i64: fmt.printf("#%d", t);
            case f64: fmt.printf("#%f", t);
        }
        
        case Label_Name:
        fmt.printf("%s.%d", v.name, v.idx);
    }
}

ir_print_var :: proc(using emitter: ^Emitter, op: ^Operand)
{
    if op == nil do return;
    var := op.(Variable);
    ir_print_type(emitter, var.type);
    fmt.printf(" !%s", var.name);
}

ir_print_type :: proc(using emitter: ^Emitter, type: ^Type)
{
    if type == nil
    {
        fmt.printf("@void");
        return;
    }
    fmt.printf("@i%d", type.size*8);
}
