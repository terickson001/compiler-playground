package main

import "core:fmt"
import "parse"
import "emit/x64"

main :: proc()
{
    decls := parse.parse_file("test.sm");
    emitter := x64.make_emitter("test.s", decls);
    x64.emit_file(&emitter);
}
