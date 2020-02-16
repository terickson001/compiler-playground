package main

import "core:fmt"
import "parse"
import "asm/x64"

main :: proc()
{
    nodes := parse.parse_file("test.sm");
    parse.print_expr(nodes);
    emitter := x64.make_emitter("test.s", nodes);
    x64.emit_file(&emitter);
}
