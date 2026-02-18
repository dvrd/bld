package main

import "core:testing"

@(test)
test_add :: proc(t: ^testing.T) {
    testing.expect_value(t, add(2, 3), 5)
    testing.expect_value(t, add(0, 0), 0)
    testing.expect_value(t, add(-1, 1), 0)
}

@(test)
test_greet :: proc(t: ^testing.T) {
    result := greet("World")
    testing.expect(t, result == "Hello, World!", "Expected greeting to match")
}
