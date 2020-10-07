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
    if at == dest_list.tail do
        dest_list.tail = src_list.tail;
    else do
        at.next.prev = src_list.tail;
    
    src_list.head.prev = at;
    src_list.tail.next = at.next;
    at.next = src_list.head;
}

insert_statements_before :: proc(dest_list: ^Statement_List, at: ^Statement, src_list: ^Statement_List)
{
    if at == dest_list.head do
        dest_list.head = src_list.head;
    else do
        at.prev.next = src_list.head;
    
    src_list.tail.next = at;
    src_list.head.prev = at.prev;
    at.prev = src_list.tail;
}