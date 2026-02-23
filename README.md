# bld

An Odin build system as a library. Write your build scripts in Odin with type-safe compiler flag configuration.

Inspired by [nob.h](https://github.com/tsoding/nob.h) but designed Odin-first — the primary abstraction is a `Build_Config` struct that maps 1:1 to Odin compiler flags, not a generic shell command runner.

## Quick Start

### 1. Add bld to your project

Copy or symlink the `bld/` directory into your project:

```
my_project/
  src/
    main.odin
  bld/              ← this package
  build/
    build.odin      ← your build script
```

### 2. Write a build script

```odin
// build/build.odin
package main

import bld "../bld"

main :: proc() {
    bld.mkdir_if_not_exists("out")

    if !bld.build({
        package_path = "src",
        out          = "out/myapp",
        opt          = .Speed,
    }) {
        bld.log_error("Build failed!")
    }
}
```

### 3. Bootstrap and run

```sh
odin build build -out:build_it
./build_it
```

## Core API

### Build_Config

Every Odin compiler flag has a typed field. Zero values mean "don't emit that flag" (use compiler defaults).

```odin
bld.build({
    package_path       = "src",
    out                = "out/myapp",
    opt                = .Speed,
    debug              = true,
    vet                = {.Shadowing, .Unused_Imports, .Style},
    warnings_as_errors = true,
    defines            = {{name = "VERSION", value = "1.0.0"}},
    collections        = {{name = "shared", path = "libs/shared"}},
})
```

| Field | Type | Compiler Flag |
|-------|------|---------------|
| `package_path` | `string` | Positional arg (required) |
| `out` | `string` | `-out:` |
| `opt` | `Opt_Level` | `-o:none\|minimal\|size\|speed\|aggressive` |
| `build_mode` | `Build_Mode` | `-build-mode:exe\|dll\|lib\|obj\|asm\|llvm-ir` |
| `debug` | `bool` | `-debug` |
| `file_mode` | `bool` | `-file` |
| `target` | `string` | `-target:` |
| `microarch` | `string` | `-microarch:` |
| `collections` | `[]Collection` | `-collection:name=path` |
| `defines` | `[]Define` | `-define:name=value` |
| `vet` | `Vet_Flags` | `-vet-shadowing`, `-vet-unused`, etc. |
| `sanitize` | `Sanitize_Flags` | `-sanitize:address\|memory\|thread` |
| `thread_count` | `int` | `-thread-count:` |
| `extra_linker_flags` | `string` | `-extra-linker-flags:` |
| `extra_assembler_flags` | `string` | `-extra-assembler-flags:` |
| `show_timings` | `bool` | `-show-timings` |
| `show_more_timings` | `bool` | `-show-more-timings` |
| `warnings_as_errors` | `bool` | `-warnings-as-errors` |
| `terse_errors` | `bool` | `-terse-errors` |
| `disable_assert` | `bool` | `-disable-assert` |
| `default_to_nil_allocator` | `bool` | `-default-to-nil-allocator` |
| `default_to_panic_allocator` | `bool` | `-default-to-panic-allocator` |
| `keep_temp_files` | `bool` | `-keep-temp-files` |
| `strict_style` | `bool` | `-strict-style` |
| `custom_attributes` | `[]string` | `-custom-attribute:` |
| `vet_packages` | `[]string` | `-vet-packages:` |
| `ignore_unused_defineables` | `bool` | `-ignore-unused-defineables` |
| `extra_flags` | `[]string` | Raw flags passed verbatim |

### Compiler Verbs

```odin
bld.build(config)                    // odin build
bld.run(config, "arg1", "arg2")      // odin run ... -- arg1 arg2
bld.test(config)                     // odin test
bld.check(config)                    // odin check (type-check only)
```

All return `bool` — `true` on success.

### Presets

```odin
config := bld.release_config("src", "out/myapp")   // opt = .Speed
config := bld.debug_config("src", "out/myapp")      // debug = true

// Then customize:
config.vet = {.All}
config.warnings_as_errors = true
bld.build(config)
```

## Full Example

A build script with type-check gate, tests, debug build, and release build:

```odin
package main

import bld "../bld"

main :: proc() {
    bld.go_rebuild_urself("build")  // Auto-rebuild when this file changes
    start := bld.timer_start()
    bld.mkdir_if_not_exists("out")

    // Fast type-check gate.
    if !bld.check({package_path = "src"}) {
        bld.log_error("Type check failed")
        return
    }

    // Run tests.
    if !bld.test({package_path = "src", vet = {.All}}) {
        bld.log_error("Tests failed")
        return
    }

    // Debug build.
    if !bld.build({
        package_path = "src",
        out          = "out/myapp-debug",
        debug        = true,
        vet          = {.Shadowing, .Unused_Imports},
    }) {
        bld.log_error("Debug build failed")
        return
    }

    // Release build.
    if !bld.build({
        package_path       = "src",
        out                = "out/myapp",
        opt                = .Speed,
        disable_assert     = true,
        warnings_as_errors = true,
    }) {
        bld.log_error("Release build failed")
        return
    }

    bld.log_info("All done in %.2fs", bld.timer_elapsed(start))
}
```

## Utilities

### File Operations

```odin
bld.mkdir_if_not_exists("dist")
bld.mkdir_all("dist/linux/amd64")
bld.copy_file("out/myapp", "dist/myapp")
bld.copy_directory_recursively("assets", "dist/assets")
bld.write_entire_file_string("out/version.txt", "1.0.0")
data, ok := bld.read_entire_file("config.json", context.temp_allocator)
bld.delete_file("out/temp.bin")
bld.rename_file("out/old", "out/new")
bld.file_exists("out/myapp")
```

### Needs Rebuild

Check if output is older than inputs (like `make` dependency tracking):

```odin
rebuild, ok := bld.needs_rebuild1("out/myapp", "src/main.odin")
if !ok {
    bld.log_error("Error checking")
} else if rebuild {
    bld.log_info("Rebuild needed")
} else {
    bld.log_info("Up to date")
}

// Multiple inputs:
rebuild, ok = bld.needs_rebuild("out/myapp", {"src/main.odin", "src/game.odin", "src/render.odin"})
```

### Go Rebuild Urself

Put this at the top of your build script's `main()`. If the build script source is newer than the running binary, it rebuilds and re-executes itself:

```odin
main :: proc() {
    bld.go_rebuild_urself("build")
    // ... rest of build logic ...
}
```

### Arbitrary Commands (Escape Hatch)

For anything outside Odin compilation:

```odin
cmd := bld.cmd_create(context.temp_allocator)
bld.cmd_append(&cmd, "strip", "out/myapp")
bld.cmd_run(&cmd)
```

### Parallel Execution

```odin
procs := bld.procs_create(context.temp_allocator)

cmd1 := bld.cmd_create(context.temp_allocator)
bld.cmd_append(&cmd1, "echo", "task 1")
bld.cmd_run(&cmd1, {async = &procs})

cmd2 := bld.cmd_create(context.temp_allocator)
bld.cmd_append(&cmd2, "echo", "task 2")
bld.cmd_run(&cmd2, {async = &procs})

bld.procs_flush(&procs)  // Wait for all
```

### Command Pipes

```odin
chain: bld.Chain
bld.chain_begin(&chain)

cmd1 := bld.cmd_create(context.temp_allocator)
bld.cmd_append(&cmd1, "cat", "input.txt")
bld.chain_cmd(&chain, &cmd1)

cmd2 := bld.cmd_create(context.temp_allocator)
bld.cmd_append(&cmd2, "grep", "pattern")
bld.chain_cmd(&chain, &cmd2)

bld.chain_end(&chain)
```

### Directory Walking

```odin
bld.walk_dir("src", proc(entry: bld.Walk_Entry, _: rawptr) -> bld.Walk_Action {
    if entry.type == .Regular {
        bld.log_info("  %s", entry.path)
    }
    return .Continue
})
```

### Timing

```odin
start := bld.timer_start()
// ... work ...
bld.log_info("Took %.2fs", bld.timer_elapsed(start))
```

### Logging

```odin
bld.log_info("Building %s", name)
bld.log_warn("Deprecated flag used")
bld.log_error("Build failed!")

bld.minimal_log_level = .Warning  // Suppress info messages
bld.echo_actions = false           // Suppress CMD/PIPE echo
```

## Working Example

See `example/` for a complete working example:

- `example/src/main.odin` — a small Odin app with `add` and `greet` procs
- `example/src/main_test.odin` — tests for the app
- `example/build.odin` — comprehensive build script that exercises every bld feature (53 tests)

Run it:

```sh
odin build example/build.odin -file -out:target/test_build
./target/test_build
```

## Package Files

| File | Purpose |
|------|---------|
| `odin.odin` | Core — `Build_Config` struct, `build`/`run`/`test`/`check` |
| `cmd.odin` | Command builder and execution |
| `procs.odin` | Async process management, `nprocs()` |
| `fs.odin` | File system operations |
| `path.odin` | Path utilities |
| `walk.odin` | Directory tree walker |
| `chain.odin` | Command pipes |
| `rebuild.odin` | Go Rebuild Urself, `needs_rebuild` |
| `time.odin` | Timing utilities |
| `log.odin` | Logging |

## License

Public domain / Unlicense — do whatever you want.
