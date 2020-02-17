package x64

import "core:fmt"
import "core:os"
import "core:strings"

import "../../parse"

Emitter :: struct
{
    file: os.Handle,
    label_counts: map[string]int,
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
    emitter.label_counts = make(map[string]int);
    
    return emitter;
}

emit_fmt :: inline proc(using emitter: ^Emitter, fmt_str: string, args: ..any)
{
    os.write_string(file, "    ");
    os.write_string(file, fmt.tprintf(fmt_str, ..args));
}

emit_cmp :: proc(using emitter: ^Emitter, set: string)
{
    emit_fmt(emitter, "cmp  %%rcx, %%rax\n");
    emit_fmt(emitter, "mov  $0, %%rax\n");
    emit_fmt(emitter, "%s %%al\n", set);
}

emit_label :: proc(using emitter: ^Emitter, label: string)
{
    os.write_string(file, fmt.tprintf("%s:\n", label)); 
}

create_label :: proc(using emitter: ^Emitter, label: string) -> string
{
    count, ok := label_counts[label];
    if !ok do
        label_counts[label] = 1;
    else do
        label_counts[label] += 1;

    return strings.clone(fmt.tprintf("_%s%d", label, count));
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
        case .Sub:     emit_fmt(emitter, "neg  %%rax\n");
        case .Bit_Not: emit_fmt(emitter, "not  %%rax\n");
        case .Not:
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "mov  $0, %%rax\n");
            emit_fmt(emitter, "sete %%al\n");
            
        case: emit_fmt(emitter, "INV  %%rax\n");
        }
        
    case parse.Binary_Expr:

        
        #partial switch e.op.kind
        {
        case .Or:
            skip := create_label(emitter, "skip");
            end := create_label(emitter, "end");
            defer
            {
                delete(skip);
                delete(end);
            }
            
            emit_expr(emitter, e.lhs);
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "je   %s\n", skip);
            emit_fmt(emitter, "mov  $1, %%rax\n");
            emit_fmt(emitter, "jmp  %s\n", end);
            
            emit_label(emitter, skip);
            
            emit_expr(emitter, e.rhs);
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "mov  $0, %%rax\n");
            emit_fmt(emitter, "setne %%al\n");
            emit_label(emitter, end);

        case .And:
            rhs := create_label(emitter, "rhs");
            end := create_label(emitter, "end");
            defer
            {
                delete(rhs);
                delete(end);
            }
            
            emit_expr(emitter, e.lhs);
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "jne   %s\n", rhs);
            emit_fmt(emitter, "jmp  %s\n", end);
            
            emit_label(emitter, rhs);
            
            emit_expr(emitter, e.rhs);
            emit_fmt(emitter, "cmp  $0, %%rax\n");
            emit_fmt(emitter, "mov  $0, %%rax\n");
            emit_fmt(emitter, "setne %%al\n");
            emit_label(emitter, end);
            
        case:
            emit_expr(emitter, e.rhs);
            emit_fmt(emitter, "push %%rax\n");
            emit_expr(emitter, e.lhs);
            emit_fmt(emitter, "pop  %%rcx\n");
            
            #partial switch e.op.kind
            {
            case .Add: emit_fmt(emitter, "add  %%rcx, %%rax\n");
            case .Sub: emit_fmt(emitter, "sub  %%rcx, %%rax\n");
            case .Mul: emit_fmt(emitter, "imul %%rcx, %%rax\n");
            case .Quo:
                emit_fmt(emitter, "cdq\n");
                emit_fmt(emitter, "idiv %%rcx\n");
                emit_fmt(emitter, "idiv %%rcx, %%rax\n");
                
            case .Mod:
                emit_fmt(emitter, "cdq\n");
                emit_fmt(emitter, "idiv %%rcx\n");
                emit_fmt(emitter, "mov  %%rdx, %%rax\n");
                
            case .Bit_Or:  emit_fmt(emitter, "or   %%rcx, %%rax\n");
            case .Bit_And: emit_fmt(emitter, "and  %%rcx, %%rax\n");
            case .Xor:     emit_fmt(emitter, "xor  %%rcx, %%rax\n");
            case .Shl: emit_fmt(emitter, "shl  %%cl, %%rax\n");
            case .Shr: emit_fmt(emitter, "shr  %%cl, %%rax\n");

            case .CmpEq: emit_cmp(emitter, "sete");
            case .NotEq: emit_cmp(emitter, "setne");
            case .Lt: emit_cmp(emitter, "setl");
            case .LtEq: emit_cmp(emitter, "setle");
            case .Gt: emit_cmp(emitter, "setg");
            case .GtEq: emit_cmp(emitter, "setge");
                
            case: emit_fmt(emitter, "INV  %%rcx, %%rax\n");
            }
            
            
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
