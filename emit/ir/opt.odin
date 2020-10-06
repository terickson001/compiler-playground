package ir

Optimizer :: struct
{
    current_proc: ^ProcDef,
}

Edge :: struct
{
    from, to: ^Block,
}

Block_List :: struct
{
    head, tail: ^Block,
    count: u32,
}
Block :: struct
{
    predicates, successors: [dynamic]^Edge,
    prev, next: ^Block,
    statements: Statement_List,
}

Flow_Graph :: struct
{
    
}

build_flow_graph :: proc(using o: ^Optimizer)
{
    statements := o.current_proc.scope.variant.(^Scope).statements;
    make_blocks(o, statements);
}

import "core:reflect"
import "core:fmt"

make_block_and_push :: proc(blocks: ^Block_List, stmts: Statement_List, stmt_head: ^Statement) -> ^Block
{
    tail := new(Block);
    tail.statements = stmts;
    tail.statements.head = stmt_head;
    
    fmt.printf("Making new block with head: %v\n", reflect.union_variant_typeid(stmt_head.variant));
    if blocks.head == nil
    {
        blocks.head = tail;
        blocks.tail = tail;
    }
    else
    {
        blocks.tail.next = tail;
        tail.prev = blocks.tail;
        blocks.tail = tail;
    }
    blocks.count += 1;
    return tail;
}

make_blocks :: proc(using o: ^Optimizer, list: Statement_List) -> Block_List
{
    blocks: Block_List;
    block: ^Block;
    prev: ^Statement;
    start_new_block := true;
    for stmt := list.head; stmt != nil; stmt = stmt.next
    {
        fmt.printf("TEST: %v\n", reflect.union_variant_typeid(stmt.variant));
        if start_new_block || statement_starts_block(stmt, prev)
        {
            start_new_block = false;
            prev = nil;
            block = make_block_and_push(&blocks, list, stmt);
        }
        
        stmt.block = block;
        
        if statement_ends_block(stmt) do
            start_new_block = true;
        
        prev = stmt;
    }
    return blocks;
}

statement_starts_block :: proc(stmt, prev: ^Statement) -> bool
{
    #partial switch v in stmt.variant
    {
        case Label: 
        if prev == nil do return true;
        #partial switch pv in prev.variant
        {
            case Label: return false;
            case: return true;
        }
        
        case: return false;
    }
}

statement_ends_block :: proc(stmt: ^Statement) -> bool
{
    #partial switch v in stmt.variant
    {
        case Jump:   return true;
        case CJump:  return true;
        case Return: return true;
        
        case: return false;
    }
}