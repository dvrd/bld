package main

import "core:fmt"
import "core:os"

add :: proc(a, b: int) -> int {
    return a + b
}

greet :: proc(name: string) -> string {
    return fmt.tprintf("Hello, %s!", name)
}

main :: proc() {
    fmt.println(greet("bld"))
    fmt.println("2 + 3 =", add(2, 3))

    // Print args if any.
    if len(os.args) > 1 {
        fmt.print("Args:")
        for arg in os.args[1:] {
            fmt.printf(" %s", arg)
        }
        fmt.println()
    }
}
