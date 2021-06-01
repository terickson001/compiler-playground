package ir

Statement_List :: struct
{
    head: ^Statement,
    tail: ^Statement,
    // count: u32,
}

push_statement :: proc(list: ^Statement_List, tail: ^Statement)
{
    if list.head == nil
    {
        list.head = tail;
        list.tail = tail;
    }
    else
    {
        list.tail.next = tail;
        tail.prev = list.tail;
        list.tail = tail;
    }
    // list.count += 1;
}

remove_statement :: proc(list: ^Statement_List, stmt: ^Statement)
{
    if stmt == list.head do list.head = stmt.next;
    else do stmt.prev.next = stmt.next;
    if stmt == list.tail do list.tail = stmt.prev;
    else do stmt.next.prev = stmt.prev;
    
}

insert_statements :: insert_statements_after;
insert_statements_after :: proc(dest_list: ^Statement_List, at: ^Statement, src_list: ^Statement_List)
{
    if at == dest_list.tail 
    {
        dest_list.tail = src_list.tail;
    }
    else 
    {
        at.next.prev = src_list.tail;
    }
    
    src_list.head.prev = at;
    src_list.tail.next = at.next;
    at.next = src_list.head;
}

insert_statements_before :: proc(dest_list: ^Statement_List, at: ^Statement, src_list: ^Statement_List)
{
    if at == dest_list.head 
    {
        dest_list.head = src_list.head;
    }
    else 
    {
        at.prev.next = src_list.head;
    }
    
    src_list.tail.next = at;
    src_list.head.prev = at.prev;
    at.prev = src_list.tail;
}

insert_statement_before :: proc(list: ^Statement_List, at: ^Statement, stmt: ^Statement)
{
    if at == list.head 
    {
        list.head = stmt;
    }
    else 
    {
        at.prev.next = stmt;
    }
    stmt.next = at;
    at.prev = stmt;
}

first_non_label_statement :: proc(list: ^Statement_List) -> ^Statement
{
    for stmt := list.head; stmt != nil; stmt = stmt.next
    {
        if _, ok := stmt.variant.(Label); !ok 
        {
            return stmt;
        }
    }
    return nil;
}