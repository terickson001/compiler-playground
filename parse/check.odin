package parse

import "core:fmt"
import "core:os"

Checker :: struct
{
    parser: Parser,
}

make_checker :: proc(parser: Parser) -> (checker: Checker)
{
    checker.parser = parser;
    return checker;
}

check_scope :: proc(using checker: ^Checker, scope: ^Scope)
{
    for stmt in scope.statements do
        check_statement(checker, stmt);
}

#partial check_statement :: proc(using checker: ^Checker, stmt: ^Node)
{
    switch v in stmt.variant
    {
    case Assign_Stmt:
        check_expr(checker, v.lhs);
        check_expr(checker, v.rhs);
        
    case Block_Stmt:
        check_scope(checker, v.scope);
        
    case Return_Stmt:
        check_expression(checker, v.exp);
        
    case If_Stmt:
        check_expression(checker, v.cond);
        check_statement(checker, v.block);
        check_statement(checker, v._else);

    case Var: check_declaration(checker, stmt);
    }
}

check_declaration :: proc(using checker: ^Checker, decl: ^Node)
{
    
}

check_expression :: proc(using checker: ^Checker, expr: ^Node)
{

}

resolve_symbols :: proc(using checker: ^Checker)
{
    for _, i in &parser.symbols
    {
        sym := &parser.symbols[i];
        name := ident_str(sym.node);
        scope := sym.node.scope;
        for scope != nil
        {
            if _, ok := scope.declarations[name]; ok
            {
                sym.state = .Resolved;
                break;
            }
            scope = scope.parent;
        }
        if sym.state != .Resolved
        {
            token := node_token(sym.node);
            fmt.eprintf("%s(%d): \e[31mERROR\e[0m: Unresolved identifier %q\n", token.filename, token.line, name);
            os.exit(1);
        }
    }
}
