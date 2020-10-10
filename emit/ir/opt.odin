package ir

import "tree"

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
    count: u64,
}

Block :: struct
{
    predicates, successors: [dynamic]^Edge,
    prev, next: ^Block,
    statements: Statement_List,
    idx: u64,
}

Flow_Graph :: struct
{
    blocks: Block_List,
    doms: []^Block,
    frontiers: [][dynamic]^Block,
}

import "core:reflect"
import "core:fmt"

opt :: proc(using o: ^Optimizer)
{
    flatten_scopes(o);
    build_flow_graph(o);
    to_ssa(o);
}

// Passes
flatten_scopes :: proc(using o: ^Optimizer)
{
    statements := &o.current_proc.scope.variant.(^Scope).statements;
    for stmt := statements.head; stmt != nil; stmt = stmt.next
    {
        #partial switch v in stmt.variant
        {
            case ^Scope:
            insert_statements(statements, stmt, &v.statements);
            remove_statement(statements, stmt);
        }
    }
}

build_flow_graph :: proc(using o: ^Optimizer)
{
    statements := o.current_proc.scope.variant.(^Scope).statements;
    make_blocks(o, statements);
    trim_labels(o);
    make_edges(o);
}

to_ssa :: proc(using o: ^Optimizer)
{
    init_dominators(o);
    find_frontiers(o);
}

// to_ssa subroutines
find_frontiers :: proc(using o: ^Optimizer)
{
    fg := &current_proc.flow;
    fg.frontiers = make([][dynamic]^Block, fg.blocks.count);
    for b := fg.blocks.head; b != nil; b = b.next
    {
        if len(b.predicates) < 2 do
            continue;
        for edge in b.predicates
        {
            pred := edge.from;
            runner := pred;
            for runner != fg.doms[b.idx]
            {
                append(&fg.frontiers[b.idx], runner);
                runner = fg.doms[runner.idx];
            }
        }
    }
}

init_dominators :: proc(using o: ^Optimizer)
{
    fg := &current_proc.flow;
    fg.doms = make([]^Block, fg.blocks.count);
    
    start_node := fg.blocks.head;
    fg.doms[start_node.idx] = start_node;
    
    Search_State :: struct 
    {
        block: ^Block,
        eidx: int,
    };
    
    sp := 0;
    stack := make([]Search_State, fg.blocks.count);
    curr_node := start_node;
    
    changed := true;
    for changed
    {
        changed = false;
        eidx := 0;
        for
        {
            for eidx < len(curr_node.successors)
            {
                block := curr_node.successors[eidx].to;
                idom := find_idom(o, block);
                if idom != fg.doms[block.idx]
                {
                    fg.doms[block.idx] = idom;
                    changed = true;
                }
                
                stack[sp] = {curr_node, eidx+1};
                sp += 1;
                eidx = 0;
                curr_node = block;
            }
            if sp == 0 do 
                break;
            sp -= 1;
            curr_node, eidx = expand_to_tuple(stack[sp]);
        }
    }
    
    fmt.printf("DOMS: %#v\n", fg.doms);
}

find_idom :: proc(using o: ^Optimizer, block: ^Block) -> ^Block
{
    fg := &current_proc.flow;
    
    new_idom: ^Block;
    for edge in block.predicates
    {
        pred := edge.from;
        if fg.doms[pred.idx] == nil do
            continue;
        if new_idom == nil
        {
            new_idom = pred;
            continue;
        }
        
        new_idom = dom_intersect(fg, pred, new_idom);
    }
    return new_idom;
}

dom_intersect :: proc(flow: ^Flow_Graph, a, b: ^Block) -> ^Block
{
    finger1 := a;
    finger2 := b;
    
    for finger1 != finger2
    {
        for finger1.idx > finger2.idx do
            finger1 = flow.doms[finger1.idx];
        for finger2.idx > finger1.idx do
            finger2 = flow.doms[finger2.idx];
    }
    
    return finger1;
}

// build_flow_graph subroutines
make_edges :: proc(using o: ^Optimizer)
{
    blocks := &current_proc.blocks;
    for block := blocks.head; block != nil; block = block.next
    {
        last := block.statements.tail;
        #partial switch v in last.variant
        {
            case Jump:
            dest := current_proc.label_to_block[label_index(v.label)];
            edge := new(Edge);
            edge^ = Edge{block, dest};
            append(&block.successors, edge);
            append(&dest.predicates, edge);
            
            case CJump:
            // Then
            {
                dest := current_proc.label_to_block[label_index(v.then)];
                if edge_between(block, dest) == nil
                {
                    edge := new(Edge);
                    edge^ = Edge{block, dest};
                    append(&block.successors, edge);
                    append(&dest.predicates, edge);
                }
            }
            // Else
            {
                dest := current_proc.label_to_block[label_index(v._else)];
                if edge_between(block, dest) == nil
                {
                    edge := new(Edge);
                    edge^ = Edge{block, dest};
                    append(&block.successors, edge);
                    append(&dest.predicates, edge);
                }
            }
            
            case Return: // @todo(tyler): Where does a return jump to?
        }
    }
}

edge_between :: proc(src, dest: ^Block) -> ^Edge
{
    if len(src.successors) < len(dest.predicates)
    {
        for e in src.successors do
            if e.to == dest do return e;
    }
    else
    {
        for e in dest.predicates do
            if e.from == src do return e;
    }
    return nil;
}

trim_labels :: proc(using o: ^Optimizer)
{
    blocks := &current_proc.blocks;
    dominant_label := make([]^Operand, blocks.count);
    defer delete(dominant_label);
    
    // Determine dominant label for each block
    for block := blocks.head; block != nil; block = block.next
    {
        STATEMENTS:
        for stmt := block.statements.head; stmt != nil; stmt = stmt.next
        {
            #partial switch v in stmt.variant
            {
                case Label:
                dominant_label[block.idx] = v.name;
                break STATEMENTS;
            }
        }
    }
    
    for block := blocks.head; block != nil; block = block.next
    {
        for stmt := block.statements.head; stmt != nil; stmt = stmt.next
        {
            #partial switch v in &stmt.variant
            {
                case Jump:
                dest_block := current_proc.label_to_block[label_index(v.label)];
                v.label = dominant_label[dest_block.idx];
                
                case CJump:
                {
                    dest_block := current_proc.label_to_block[label_index(v.then)];
                    v.then = dominant_label[dest_block.idx];
                }
                {
                    dest_block := current_proc.label_to_block[label_index(v._else)];
                    v._else = dominant_label[dest_block.idx];
                }
            }
        }
    }
    
    for block := blocks.head; block != nil; block = block.next
    {
        for stmt := block.statements.head; stmt != nil; stmt = stmt.next
        {
            #partial switch v in stmt.variant
            {
                case Label:
                if v.name != dominant_label[block.idx] do
                    remove_statement(&block.statements, stmt);
            }
        }
    }
}

make_blocks :: proc(using o: ^Optimizer, list: Statement_List)
{
    blocks := &current_proc.flow.blocks;
    block: ^Block;
    prev: ^Statement;
    start_new_block := true;
    for stmt := list.head; stmt != nil; stmt = stmt.next
    {
        if start_new_block || statement_starts_block(stmt, prev)
        {
            start_new_block = false;
            prev = nil;
            block = make_block_and_push(blocks, list, stmt);
        }
        
        stmt.block = block;
        #partial switch v in stmt.variant
        {
            case Label:
            current_proc.label_to_block[label_index(v.name)] = block;
        }
        
        if statement_ends_block(stmt) do
            start_new_block = true;
        
        prev = stmt;
    }
}

make_block_and_push :: proc(blocks: ^Block_List, stmts: Statement_List, stmt_head: ^Statement) -> ^Block
{
    tail := new(Block);
    tail.statements = stmts;
    tail.statements.head = stmt_head;
    
    if blocks.head != nil do
        blocks.tail.statements.tail = stmt_head.prev;
    if stmt_head.prev != nil
    {
        stmt_head.prev.next = nil;
        stmt_head.prev = nil;
    }
    
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
    tail.idx = blocks.count;
    blocks.count += 1;
    return tail;
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