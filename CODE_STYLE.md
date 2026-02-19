# Code Style

Conventions observed in the `bld` codebase. Follow these when contributing.

## Naming Conventions

| Element | Convention | Examples |
|---------|-----------|----------|
| Files | `snake_case.odin` | `cmd.odin`, `rebuild.odin`, `main_test.odin` |
| Types (structs, enums) | `Ada_Case` | `Build_Config`, `Opt_Level`, `Walk_Action` |
| Enum variants | `Ada_Case` | `.Unused_Variables`, `.LLVM_IR`, `.Speed` |
| Bit set types | Plural of flag enum | `Vet_Flag` → `Vet_Flags` |
| Option structs | `{Noun}_Opt` | `Cmd_Run_Opt`, `Chain_Begin_Opt` |
| Procedures | `snake_case` | `cmd_create`, `file_exists`, `go_rebuild_urself` |
| Method-like procs | `{noun}_{verb}` | `cmd_run`, `procs_wait`, `chain_begin` |
| Top-level API procs | Short single words | `build`, `run`, `test`, `check` |
| Variables / fields | `snake_case` | `package_path`, `all_ok`, `start_err` |
| Constants | `SCREAMING_SNAKE_CASE` | `NANOS_PER_SEC`, `COPY_BUF_SIZE` |
| Private procs/constants | `_underscore_prefix` | `_run_odin`, `_log_impl`, `_walk_dir_impl` |
| Acronyms in types | ALL_CAPS within Ada_Case | `LLVM_IR`, not `LlvmIr` |

## File Organization

- **One file per concern** — each file in `bld/` covers a single domain (cmd, fs, log, etc.)
- **Flat package** — no nested directories within the library
- **File header** — every file starts with `package bld` followed by a brief `//` comment describing its purpose:
  ```odin
  package bld

  // Command builder and execution.
  ```
- **Import block** — immediately after the header comment, alphabetically sorted, no blank line separators:
  ```odin
  import "core:fmt"
  import "core:mem"
  import "core:os"
  import "core:strings"
  ```
- **Test files** — use `_test.odin` suffix, same package as code under test

## Import Style

- Standard library: `import "core:..."` and `import "base:..."`
- External packages: relative paths with aliases — `import bld "../bld"`
- Alphabetically sorted within the import block
- Single import block, no blank line separators between groups

## Code Patterns

### Error Handling — `bool` return + `log_error`

The dominant pattern: return `bool` (`true` = success), log errors internally.

```odin
mkdir_if_not_exists :: proc(path: string) -> bool {
    err := os.mkdir(path)
    if err != nil {
        if err == .Exist {
            if echo_actions do log_info("directory '%s' already exists", path)
            return true
        }
        log_error("Could not create directory '%s': %v", path, err)
        return false
    }
    if echo_actions do log_info("created directory '%s'", path)
    return true
}
```

- Error messages start with `"Could not {verb} '{path}': %v"`
- For data-returning procs, use `(data, ok: bool)` tuple pattern
- **Never panic** — all errors are logged and propagated as `false`
- Tri-state: `needs_rebuild` returns `int` (-1 error / 0 no / 1 yes)

### Allocator Passing

```odin
// Allocator is always the LAST parameter with a default
cmd_create :: proc(allocator := context.allocator) -> Cmd { ... }

// Use context.allocator for data the caller owns
read_entire_file :: proc(path: string, allocator := context.allocator) -> ([]u8, bool) { ... }

// Use context.temp_allocator for ephemeral/render data
cmd_render :: proc(cmd: Cmd, allocator := context.temp_allocator) -> string { ... }
```

- Recursive functions use `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()` to prevent unbounded temp growth

### Private Procedures

Always pair `_underscore_prefix` with `@(private = "file")`:

```odin
@(private = "file")
_run_odin :: proc(verb: string, config: Build_Config, run_args: []string = nil) -> bool {
    ...
}
```

### Single-Line Conditionals

Use `if ... do` for simple one-liners:

```odin
if echo_actions do log_info("created directory '%s'", path)
if err != nil do return false
```

### Struct Literals — Aligned Fields

```odin
ok := bld.build({
    package_path = "example/src",
    out          = "target/testapp",
    opt          = .Speed,
})
```

- Column-aligned `=` for readability
- Trailing comma on last field
- Opening `{` on same line as call
- Closing `}` on its own line when multi-line

### Struct Field Declarations — Aligned Types

```odin
Build_Config :: struct {
    package_path:              string,
    out:                       string,
    opt:                       Opt_Level,
    warnings_as_errors:        bool,
    default_to_nil_allocator:  bool,
}
```

- Column-aligned `:` and type names
- Trailing comma on every field

## Logging

- All logging goes to **stderr**
- Three levels: `log_info`, `log_warn`, `log_error`
- Prefixes: `[INFO]`, `[WARNING]`, `[ERROR]`
- Controlled by `minimal_log_level` (filter threshold) and `echo_actions` (action echo)
- `fmt.fprintf(os.stderr, format, ..args)` pattern

## Testing

### Unit Tests — `@(test)` attribute

```odin
// example/src/main_test.odin
import "core:testing"

@(test)
test_add :: proc(t: ^testing.T) {
    testing.expect_value(t, add(2, 3), 5)
}

@(test)
test_greet :: proc(t: ^testing.T) {
    result := greet("World")
    testing.expect(t, result == "Hello, World!", "Expected greeting to match")
}
```

- Test files: `_test.odin` suffix
- Test procs: `test_` prefix + `@(test)` attribute
- `testing.expect_value` for equality, `testing.expect` for boolean with message
- Run with: `odin test example/src`

### Integration Tests — Custom Harness

```odin
Pass_Count :: struct { passed, failed, total: int }

check_result :: proc(pc: ^Pass_Count, name: string, ok: bool) { ... }
```

- Used in `example/build.odin` to exercise all library features
- Tests organized in numbered sections with `=====` banner comments
- Run with: `odin build example/build.odin -file -out:target/test_build && ./target/test_build`

## Do's and Don'ts

### Do

- Return `bool` for success/failure, log errors internally
- Pass allocator as last parameter with sensible default
- Use `context.temp_allocator` for ephemeral data
- Use `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()` in recursive functions
- Use `Ada_Case` for types, `snake_case` for everything else
- Prefix private procs with `_` and annotate `@(private = "file")`
- Keep one file per concern, flat package structure
- Column-align struct fields and struct literals
- Use `if ... do` for simple single-line conditionals
- Write a brief `//` comment at the top of every file

### Don't

- Don't panic — always return errors as `bool` or `(data, bool)`
- Don't use nested packages — keep everything in `bld/`
- Don't introduce external dependencies — standard library only
- Don't use global mutable state beyond `minimal_log_level` and `echo_actions`
- Don't forget trailing commas in struct fields and literals
- Don't use doc-comment blocks (`/** */`) — use `//` comments
