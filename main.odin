package main

import "core:fmt"
import "core:strings"
import "parse"
import "emit/ir"
import "emit/x64"

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
        assert (stmt != nil);
        #partial switch s in stmt.variant
        {
            case parse.Var:
            if s.value == nil do continue;
            if p, ok := s.value.variant.(parse.Proc); ok 
            {
                print_scope(p.scope, level + 1);
            }
            
            case parse.If_Stmt:
            print_scope(s.block.variant.(parse.Block_Stmt).scope, level + 1);
            
            case parse.For_Stmt:
            print_scope(s.scope, level + 1);
            
            case parse.Block_Stmt: 
            print_scope(s.scope, level + 1);
        }
    }
}

main :: proc()
{
    parser := parse.parse_file("test.sm");
    for file in parser.files
    {
        fmt.printf("\nFILE: %s\n\n", file.path);
        print_scope(file.scope);
    }
    checker := parse.make_checker(parser);
    parse.check_file(&checker);
    
    emitter_ir := ir.make_emitter(parser.files[0].scope);
    ir.emit_file(&emitter_ir);
    
    emitter := x64.make_emitter("test.s", parser.files[0].scope);
    x64.emit_file(&emitter);
}
