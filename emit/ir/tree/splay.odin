package tree

Node :: struct(T: typeid)
{
    parent: ^Node(T),
    left, right: ^Node(T),
    key: T,
}

rotate_left :: proc(x: ^Node($T))
{
    r := x.right;
    if r != nil
    {
        x.right = r.left;
        if r.left != nil 
        {
            r.left.parent = x;
        }
        r.parent = x.parent;
        r.left = x;
    }
    
    if x.parent != nil
    {
        if x.parent.left == x do 
            x.parent.left = r;
        else 
        {
            x.parent.right = r;
        }
    }
    x.parent = r;
}

rotate_right :: proc(x: ^Node($T))
{
    l:= x.left;
    if l != nil
    {
        x.left = l.right;
        if l.right != nil 
        {
            l.right.parent = x;
        }
        l.parent = x.parent;
        l.right = x;
    }
    
    if x.parent != nil
    {
        if x.parent.left == x do 
            x.parent.left = l;
        else 
        {
            x.parent.right = l;
        }
    }
    x.parent = l;
}

// Bring node X to root of the tree
splay :: proc(x: ^Node($T))
{
    for x.parent != nil
    {
        grandparent := x.parent.parent;
        
        x_is_left := x.parent.left == x;
        parent_is_left := grandparent != nil && grandparent.left == x.parent;
        
        switch
        {
            /* is_left(x) && is_root(x.parent) */
            case x_is_left && grandparent == nil:
            rotate_right(x.parent); // Zig
            
            /* is_right(x) && is_root(x.parent) */
            case !x_is_left && grandparent == nil:
            rotate_left(x.parent); // Zag
            
            /* is_left(x) && is_left(x.parent) */
            case x_is_left && parent_is_left:
            rotate_right(x.parent.parent); // Zig
            rotate_right(x.parent);        // Zig
            
            /* is_right(x) && is_right(x.parent) */
            case !x_is_left && !parent_is_left:
            rotate_left(x.parent.parent); // Zag
            rotate_left(x.parent);        // Zag
            
            /* is_left(x) && is_right(x.parent) */
            case x_is_left && !parent_is_left:
            rotate_right(x.parent); // Zig
            rotate_left(x.parent);  // Zag
            
            /* is_right(x) && is_left(x.parent) */
            case: 
            rotate_left(x.parent);  // Zag
            rotate_right(x.parent); // Zig
        }
    }
}
