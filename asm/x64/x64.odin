package x64

import "core:fmt"
import "core:os"

import "../../parse"

Emitter :: struct
{
    file: os.Handle,
    nodes: ^parse.Node,
}

make_emitter :: proc(path: string, nodes: ^parse.Node) -> (emitter: Emitter)
{
    ok: os.Errno;
    emitter.file, ok = os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH);
    if ok != 0
    {
        fmt.eprintf("ERROR: %v: Could not open output file %q\n", ok, path);
        os.exit(1);
    }
    
    emitter.nodes = nodes;
    
    return emitter;
}

emit_fmt :: inline proc(using emitter: ^Emitter, fmt_str: string, args: ..any)
{
    os.write_string(file, "    ");
    os.write_string(file, fmt.tprintf(fmt_str, ..args));
}

emit_expr :: proc(using emitter: ^Emitter, expr: ^parse.Node)
{
    #partial switch e in expr.variant
    {
    case parse.Literal:
        switch v in e.value
        {
            case i64: emit_fmt(emitter, "mov  $%d, %%rax\n", v);
            case f64: break;
        }
        
    case parse.Unary_Expr:
        emit_expr(emitter, e.expr);
        #partial switch e.op.kind
        {
            case .Add: break;
            case .Sub: emit_fmt(emitter, "neg  %%rax\n");
            case .Not:
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "mov  $0, %%rax\n");
            emit_fmt(emitter, "sete $0, %%al\n");

            case: emit_fmt(emitter, "INV  %%rax\n");
        }
        
    case parse.Binary_Expr:
        emit_expr(emitter, e.rhs);
        emit_fmt(emitter, "push %%rax\n");
        emit_expr(emitter, e.lhs);
        emit_fmt(emitter, "pop  %%rcx\n");
        #partial switch e.op.kind
        {
            case .Add: emit_fmt(emitter, "add  %%rcx, %%rax\n");
            case .Sub: emit_fmt(emitter, "sub  %%rcx, %%rax\n");
            case .Mul: emit_fmt(emitter, "imul %%rcx, %%rax\n");
            case .Quo: emit_fmt(emitter, "idiv %%rcx, %%rax\n");
            case: emit_fmt(emitter, "INV  %%rcx, %%rax\n");
        }
        
    case parse.Paren_Expr:
        emit_expr(emitter, e.expr);
    }
}

emit_section :: proc(using emitter: ^Emitter, name: string)
{
    emit_fmt(emitter, ".%s\n", name);
}

emit_export :: proc(using emitter: ^Emitter, label: string)
{
    emit_fmt(emitter, "    .global %s\n", label);
}

emit_file :: proc(using emitter: ^Emitter)
{
    emit_section(emitter, "text");
    emit_export(emitter, "main");

    os.write_string(file, "main:\n");
    emit_expr(emitter, nodes);
}
