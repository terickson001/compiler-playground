package main

import "core:fmt"
import "core:strings"
import "parse"
// import "emit/x64"

print_scope :: proc(scope: ^parse.Scope, level := 0)
{
    b := strings.make_builder();
    for _ in 0..<level do strings.write_string(&b, "  ");
    indent := strings.to_string(b);
    
    fmt.printf("%sScope(%d):\n%s  statements: %d\n%s  declarations: %d\n\n",
               indent, level,
               indent, len(scope.statements),
               indent, len(scope.declarations));

    for stmt in scope.statements
    {
        #partial switch s in stmt.variant
        {
        case parse.Var:
            if p, ok := s.value.variant.(parse.Proc); ok do
                print_scope(p.block.variant.(parse.Block_Stmt).scope, level + 1);
            
        case parse.If_Stmt:
            print_scope(s.block.variant.(parse.Block_Stmt).scope, level + 1);
            
        case parse.Block_Stmt: print_scope(s.scope, level+1);
            
        }
    }
}

main :: proc()
{
    parser := parse.parse_file("test.sm");
    fmt.printf("SYMBOLS: %#v\n", parser.symbols);
    checker := parse.make_checker(parser);
    // parse.resolve_symbols(&checker);
    
    /* emitter := x64.make_emitter("test.s", decls); */
    /* x64.emit_file(&emitter); */

    for file in parser.files
    {
        fmt.printf("\nFILE: %s\n\n", file.path);
        print_scope(file.scope);
    }
    
}
