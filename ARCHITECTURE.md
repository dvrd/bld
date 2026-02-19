# Architecture

## Overview

**bld** is an Odin build system library. It wraps the Odin compiler with a type-safe `Build_Config` struct and provides build-script utilities (file ops, process management, piping, directory walking, self-rebuilding). Inspired by [nob.h](https://github.com/tsoding/nob.h) but designed Odin-first.

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | [Odin](https://odin-lang.org/) |
| Dependencies | Odin standard library only (`core:*`, `base:*`) |
| External tools | `odin` compiler binary (shelled out via `os.process_start`) |
| Package manager | None — copy/symlink the `bld/` directory |
| CI/CD | None configured |
| Linter/Formatter | None configured (Odin has built-in `-strict-style` and `-vet` flags) |

## Directory Structure

```
bld/                          <- Root (git repo)
├── README.md                 <- Comprehensive API reference (324 lines)
├── ARCHITECTURE.md           <- This file
├── CODE_STYLE.md             <- Coding conventions
├── .gitignore                <- Ignores target/, thoughts/, .logs/
│
├── bld/                      <- THE LIBRARY — single Odin package (10 files)
│   ├── odin.odin             <- Core: Build_Config struct, build/run/test/check
│   ├── cmd.odin              <- Command builder and synchronous/async execution
│   ├── procs.odin            <- Async process pool, nprocs() CPU detection
│   ├── fs.odin               <- File system: mkdir, copy, read, write, delete
│   ├── path.odin             <- Path utilities: join, split, ext, stem, cwd
│   ├── walk.odin             <- Recursive directory tree walker with callback
│   ├── chain.odin            <- Unix-style command pipes (cmd1 | cmd2 | cmd3)
│   ├── rebuild.odin          <- "Go Rebuild Urself" self-rebuilding pattern
│   ├── time.odin             <- Timer/stopwatch utilities
│   └── log.odin              <- Logging subsystem (info/warn/error to stderr)
│
├── example/                  <- Working example / integration test suite
│   ├── build.odin            <- Custom test harness exercising all bld features (53 checks)
│   └── src/
│       ├── main.odin         <- Tiny sample app (add, greet procs)
│       └── main_test.odin    <- Unit tests for the sample app (not the library)
│
├── target/                   <- Build output directory (gitignored)
├── thoughts/                 <- Development notes/ledgers (gitignored)
└── .logs/                    <- Log files (gitignored)
```

## Core Components

All 10 `.odin` files in `bld/` declare `package bld`. In Odin, a package is a directory — all files compile as one unit. There are no sub-packages.

| Module | File | Responsibility |
|--------|------|----------------|
| **Compiler Integration** | `odin.odin` | `Build_Config` struct (30+ typed fields mapping 1:1 to `odin` CLI flags). Public API: `build()`, `run()`, `test()`, `check()`. Presets: `release_config()`, `debug_config()`. Private `_run_odin()` assembles a `Cmd` from config fields. |
| **Command Execution** | `cmd.odin` | `Cmd` struct (dynamic string array). Create/append/run/capture/render/reset/destroy. Supports sync and async execution, stdin/stdout/stderr file redirection. |
| **Process Management** | `procs.odin` | `Procs` (tracked process pool). `procs_wait()` / `procs_flush()`. `nprocs()` via POSIX `sysconf` with platform constants for Darwin/Linux/BSD. |
| **Piping** | `chain.odin` | `Chain` struct for Unix-style pipelines. `chain_begin()` → `chain_cmd()` (N times) → `chain_end()`. Supports stdin/stdout redirection at boundaries. |
| **File System** | `fs.odin` | `mkdir_if_not_exists`, `mkdir_all`, `copy_file` (streaming 64KB buffer), `copy_directory_recursively`, `read_entire_file`, `write_entire_file`, `delete_file`, `remove_all`, `rename_file`, `file_exists`, `get_file_type`, `read_entire_dir`. |
| **Path Utilities** | `path.odin` | `path_name`, `dir_name`, `file_ext`, `file_stem`, `path_join`, `get_cwd`, `set_cwd`. |
| **Directory Walking** | `walk.odin` | `walk_dir()` with `Walk_Proc` callback, `Walk_Entry` (path, type, level), `Walk_Action` (Continue/Skip/Stop). Pre-order and post-order traversal. |
| **Self-Rebuilding** | `rebuild.odin` | `go_rebuild_urself()` — detects if build script source is newer than running binary, rebuilds, renames old binary to `.old`, re-executes with original args. `needs_rebuild()` compares file modification times. |
| **Timing** | `time.odin` | `timer_start()` / `timer_elapsed()` returning `f64` seconds. `nanos_now()`. |
| **Logging** | `log.odin` | `log_info` / `log_warn` / `log_error` writing to stderr with `[INFO]`/`[WARNING]`/`[ERROR]` prefixes. Two globals: `minimal_log_level`, `echo_actions`. |

## Data Flow

```
User Build Script (e.g., example/build.odin)
    │
    ├── bld.build(Build_Config{...})
    │       │
    │       └── _run_odin("build", config)     [odin.odin]
    │               │
    │               ├── cmd_create()            [cmd.odin]
    │               ├── cmd_append(flags...)     [cmd.odin]
    │               └── cmd_run(cmd)            [cmd.odin]
    │                       │
    │                       └── os.process_start()  → shells out to `odin` binary
    │
    ├── bld.cmd_create() / cmd_run()   ← direct command execution
    │
    ├── bld.chain_begin/cmd/end()      ← piped commands
    │       └── procs_wait()            [procs.odin]
    │
    ├── bld.mkdir_if_not_exists()      ← file system ops
    ├── bld.copy_file()
    ├── bld.walk_dir()
    │
    └── bld.go_rebuild_urself()        ← self-rebuild check
            ├── needs_rebuild()         [rebuild.odin]
            ├── bld.build(self)         [odin.odin]
            └── os.execvp(self)         ← re-exec with same args
```

## External Integrations

| Integration | Location | Mechanism |
|-------------|----------|-----------|
| Odin compiler | `cmd.odin:113,131` | `os.process_start()` — shells out to `odin` binary |
| POSIX sysconf | `procs.odin:76` | `posix.sysconf(_SC_NPROCESSORS_ONLN)` for CPU count |
| Process info | `rebuild.odin:121` | `os.current_process_info()` for self-exe path |

## Configuration

No config files. Configuration is entirely programmatic via the `Build_Config` struct.

Two package-level globals control runtime behavior:
- `minimal_log_level: Log_Level = .Info` — filter log output
- `echo_actions: bool = true` — controls CMD/PIPE echo to stderr

## Build & Run

```sh
# Build the example/integration test
odin build example/build.odin -file -out:target/test_build
./target/test_build

# Run unit tests for the example app
odin test example/src

# Consumer usage: copy bld/ into your project, write a build script, compile and run it
odin build build -out:build_it
./build_it
```

## Distribution Model

The library is distributed by copying or symlinking the `bld/` directory into a consumer project. The consumer writes a build script that `import bld "../bld"`, compiles it with `odin build`, then runs the resulting binary. There is no package manager or build manifest.
