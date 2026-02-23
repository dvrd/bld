#+feature global-context

package bld

// Odin bindings for the bld build system library.
// Loads libbld at runtime via core:dynlib and exposes the full API through wrapper procs.

import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

// ── Metadata ─────────────────────────────────────────────────────

BLD_VERSION :: "0.1.0"

// ── Types ────────────────────────────────────────────────────────

Log_Level :: enum {
    Info,
    Warning,
    Error,
    No_Logs,
}

File_Type :: enum {
    Regular,
    Directory,
    Symlink,
    Other,
}

Opt_Level :: enum {
    Default,
    None,
    Minimal,
    Size,
    Speed,
    Aggressive,
}

Build_Mode :: enum {
    Default,   // Executable (compiler default, no flag emitted).
    Exe,       // Explicitly request executable.
    Dll,       // Dynamically linked library.
    Lib,       // Statically linked library.
    Obj,       // Object file.
    Asm,       // Assembly file.
    LLVM_IR,   // LLVM IR file.
}

Vet_Flag :: enum {
    Unused,
    Unused_Variables,
    Unused_Imports,
    Unused_Procedures,
    Shadowing,
    Using_Stmt,
    Using_Param,
    Style,
    Semicolon,
    Cast,
    Tabs,
    All,  // Shorthand for the standard -vet set.
}

Vet_Flags :: bit_set[Vet_Flag]

Sanitize_Flag :: enum {
    Address,
    Memory,
    Thread,
}

Sanitize_Flags :: bit_set[Sanitize_Flag]

Error_Pos_Style :: enum {
    Default,
    Unix,
    Odin,
}

Collection :: struct {
    name: string,
    path: string,
}

Define :: struct {
    name:  string,
    value: string,
}

Build_Config :: struct {
    // Required: package path or file path.
    package_path:              string,

    // Output path (-out:).
    out:                       string,

    // Optimization level (-o:).
    opt:                       Opt_Level,

    // Build mode (-build-mode:).
    build_mode:                Build_Mode,

    // Enable debug info (-debug).
    debug:                     bool,

    // Single file mode (-file).
    file_mode:                 bool,

    // Target triple (-target:).
    target:                    string,

    // Microarchitecture (-microarch:).
    microarch:                 string,

    // Collections (-collection:name=path).
    collections:               []Collection,

    // Defines (-define:name=value).
    defines:                   []Define,

    // Ignore unused defineables (-ignore-unused-defineables).
    // Useful when passing defines that only some packages consume.
    ignore_unused_defineables: bool,

    // Vet flags.
    vet:                       Vet_Flags,

    // Sanitizers.
    sanitize:                  Sanitize_Flags,

    // Error position style.
    error_pos_style:           Error_Pos_Style,

    // Thread count (-thread-count:). 0 = compiler default.
    thread_count:              int,

    // Extra linker flags (-extra-linker-flags:).
    extra_linker_flags:        string,

    // Extra assembler flags (-extra-assembler-flags:).
    extra_assembler_flags:     string,

    // Show timings (-show-timings).
    show_timings:              bool,

    // Show more timings (-show-more-timings).
    show_more_timings:         bool,

    // Warnings as errors (-warnings-as-errors).
    warnings_as_errors:        bool,

    // Terse errors (-terse-errors).
    terse_errors:              bool,

    // Disable assertions (-disable-assert).
    disable_assert:            bool,

    // Default to nil allocator (-default-to-nil-allocator).
    default_to_nil_allocator:  bool,

    // Default to panic allocator (-default-to-panic-allocator).
    default_to_panic_allocator: bool,

    // Keep temp files (-keep-temp-files).
    keep_temp_files:           bool,

    // Strict style (-strict-style).
    strict_style:              bool,

    // Custom attributes (-custom-attribute:).
    custom_attributes:         []string,

    // Vet specific packages (-vet-packages:).
    vet_packages:              []string,

    // Additional raw flags passed verbatim.
    extra_flags:               []string,
}

Cmd :: struct {
    items:     [dynamic]string,
    allocator: mem.Allocator,
}

Cmd_Run_Opt :: struct {
    // Run asynchronously, appending the process to this list.
    async:       ^Procs,
    // Maximum concurrent processes (0 = nprocs + 1).
    max_procs:   int,
    // Do not reset the command after execution.
    dont_reset:  bool,
    // Redirect stdin from this file path.
    stdin_path:  string,
    // Redirect stdout to this file path.
    stdout_path: string,
    // Redirect stderr to this file path.
    stderr_path: string,
}

Tracked_Process :: struct {
    process:     os.Process,
    stdin_file:  ^os.File,
    stdout_file: ^os.File,
    stderr_file: ^os.File,
}

Procs :: struct {
    items:     [dynamic]Tracked_Process,
    allocator: mem.Allocator,
}

Chain :: struct {
    // Previous read-end of the pipe (feeds into the next command's stdin).
    pipe_read:   ^os.File,
    // The last command added (not yet started).
    pending:     Cmd,
    // Whether the pending command should merge stderr into stdout.
    err2out:     bool,
    // Whether we have a pending command.
    has_pending: bool,
    // Intermediate processes that need to be waited on at chain_end.
    processes:   [dynamic]os.Process,
}

Chain_Begin_Opt :: struct {
    stdin_path: string,
}

Chain_Cmd_Opt :: struct {
    err2out:    bool,
    dont_reset: bool,
}

Chain_End_Opt :: struct {
    async:       ^Procs,
    max_procs:   int,
    stdout_path: string,
    stderr_path: string,
}

Walk_Action :: enum {
    Continue,  // Continue into directories.
    Skip,      // Skip this directory (don't recurse into it).
    Stop,      // Stop the entire walk.
}

Walk_Entry :: struct {
    path:  string,
    type:  File_Type,
    level: int,
}

Walk_Proc :: proc(entry: Walk_Entry, user_data: rawptr) -> Walk_Action

Walk_Opt :: struct {
    user_data:  rawptr,
    post_order: bool,   // Visit children before parents.
}

// ── API Struct ───────────────────────────────────────────────────

@(private = "file")
_Bld_API :: struct {
    // From log.odin (companions — take []any):
    log_info:  proc(format: string, args: []any),
    log_warn:  proc(format: string, args: []any),
    log_error: proc(format: string, args: []any),

    // From path.odin:
    path_name: proc(path: string) -> string,
    dir_name:  proc(path: string, allocator: mem.Allocator) -> string,
    file_ext:  proc(path: string) -> string,
    file_stem: proc(path: string) -> string,
    path_join: proc(parts: []string) -> string,
    get_cwd:   proc() -> (string, bool),
    set_cwd:   proc(path: string) -> bool,

    // From procs.odin:
    procs_create:  proc(allocator: mem.Allocator) -> Procs,
    procs_destroy: proc(procs: ^Procs),
    procs_wait:    proc(procs: Procs) -> bool,
    procs_flush:   proc(procs: ^Procs) -> bool,
    nprocs:        proc() -> int,

    // From cmd.odin (cmd_append companion takes []string):
    cmd_create:      proc(allocator: mem.Allocator) -> Cmd,
    cmd_append:      proc(cmd: ^Cmd, args: []string),
    cmd_extend:      proc(cmd: ^Cmd, other: Cmd),
    cmd_reset:       proc(cmd: ^Cmd),
    cmd_destroy:     proc(cmd: ^Cmd),
    cmd_render:      proc(cmd: Cmd, allocator: mem.Allocator) -> string,
    cmd_run:         proc(cmd: ^Cmd, opt: Cmd_Run_Opt) -> bool,
    cmd_run_capture: proc(cmd: ^Cmd, allocator: mem.Allocator) -> (output: []u8, ok: bool),

    // From walk.odin:
    walk_dir: proc(root: string, callback: Walk_Proc, opt: Walk_Opt) -> bool,

    // From odin.odin (run companion takes []string):
    lib_odin_version: proc() -> string,
    build:            proc(config: Build_Config) -> bool,
    run:              proc(config: Build_Config, args: []string) -> bool,
    test:             proc(config: Build_Config) -> bool,
    check:            proc(config: Build_Config) -> bool,
    release_config:   proc(package_path: string, out: string) -> Build_Config,
    debug_config:     proc(package_path: string, out: string) -> Build_Config,

    // From rebuild.odin (go_rebuild_urself companion takes []string):
    needs_rebuild:     proc(output_path: string, input_paths: []string) -> (rebuild: bool, ok: bool),
    needs_rebuild1:    proc(output_path: string, input_path: string) -> (rebuild: bool, ok: bool),
    go_rebuild_urself: proc(source_path: string, extra_sources: []string),

    // From time.odin:
    nanos_now:     proc() -> i64,
    timer_start:   proc() -> time.Tick,
    timer_elapsed: proc(start: time.Tick) -> f64,

    // From chain.odin:
    chain_begin: proc(chain: ^Chain, opt: Chain_Begin_Opt) -> bool,
    chain_cmd:   proc(chain: ^Chain, cmd: ^Cmd, opt: Chain_Cmd_Opt) -> bool,
    chain_end:   proc(chain: ^Chain, opt: Chain_End_Opt) -> bool,

    // From fs.odin:
    mkdir_if_not_exists:        proc(path: string) -> bool,
    mkdir_all:                  proc(path: string) -> bool,
    copy_file:                  proc(src_path: string, dst_path: string) -> bool,
    read_entire_file:           proc(path: string, allocator: mem.Allocator) -> (data: []u8, ok: bool),
    write_entire_file:          proc(path: string, data: []u8) -> bool,
    write_entire_file_string:   proc(path: string, content: string) -> bool,
    delete_file:                proc(path: string) -> bool,
    remove_all:                 proc(path: string) -> bool,
    rename_file:                proc(old_path: string, new_path: string) -> bool,
    get_file_type:              proc(path: string) -> (File_Type, bool),
    file_exists:                proc(path: string) -> bool,
    read_entire_dir:            proc(dir_path: string, allocator: mem.Allocator) -> (names: []string, ok: bool),
    copy_directory_recursively: proc(src_path: string, dst_path: string) -> bool,

    __handle: dynlib.Library,
}

// ── Package-Level State ──────────────────────────────────────────

@(private = "file")
_api: _Bld_API

// Global variable pointers (into DLL memory).
minimal_log_level: ^Log_Level
echo_actions:      ^bool

// ── Init ─────────────────────────────────────────────────────────

@(init)
@(private = "file")
_load_bld :: proc() {
    LIB_DIR :: #directory

    when ODIN_OS == .Darwin {
        DYLIB_NAME :: "libbld.dylib"
    } else when ODIN_OS == .Linux {
        DYLIB_NAME :: "libbld.so"
    } else {
        #panic("Unsupported OS")
    }

    dylib_path := fmt.tprintf("%s%s", LIB_DIR, DYLIB_NAME)

    count, ok := dynlib.initialize_symbols(&_api, dylib_path, "bld_")
    if !ok {
        fmt.eprintfln("[bld] Could not load library at '%s': %s", dylib_path, dynlib.last_error())
        os.exit(1)
    }

    // Load global variable pointers.
    ml_ptr, ml_ok := dynlib.symbol_address(_api.__handle, "bld_minimal_log_level")
    if !ml_ok {
        fmt.eprintfln("[bld] Could not load 'minimal_log_level' from library")
        os.exit(1)
    }
    minimal_log_level = (^Log_Level)(ml_ptr)

    ea_ptr, ea_ok := dynlib.symbol_address(_api.__handle, "bld_echo_actions")
    if !ea_ok {
        fmt.eprintfln("[bld] Could not load 'echo_actions' from library")
        os.exit(1)
    }
    echo_actions = (^bool)(ea_ptr)

    // Version mismatch warning: compare the dylib's baked-in version against
    // the user's compiler version (baked when they compile the bindings).
    lib_version := _api.lib_odin_version()
    if lib_version != ODIN_VERSION {
        fmt.eprintfln(
            "[bld] Warning: library compiled with Odin %s, you are using %s. ABI mismatch may cause crashes.",
            lib_version, ODIN_VERSION,
        )
    }
}

// ── Wrapper Procs ────────────────────────────────────────────────

// -- Logging (variadic) --

log_info :: proc(format: string, args: ..any) {
    _api.log_info(format, args)
}

log_warn :: proc(format: string, args: ..any) {
    _api.log_warn(format, args)
}

log_error :: proc(format: string, args: ..any) {
    _api.log_error(format, args)
}

// -- Path utilities --

path_name :: proc(path: string) -> string {
    return _api.path_name(path)
}

dir_name :: proc(path: string, allocator := context.temp_allocator) -> string {
    return _api.dir_name(path, allocator)
}

file_ext :: proc(path: string) -> string {
    return _api.file_ext(path)
}

file_stem :: proc(path: string) -> string {
    return _api.file_stem(path)
}

path_join :: proc(parts: ..string) -> string {
    return _api.path_join(parts)
}

get_cwd :: proc() -> (string, bool) {
    return _api.get_cwd()
}

set_cwd :: proc(path: string) -> bool {
    return _api.set_cwd(path)
}

// -- Process management --

procs_create :: proc(allocator := context.allocator) -> Procs {
    return _api.procs_create(allocator)
}

procs_destroy :: proc(procs: ^Procs) {
    _api.procs_destroy(procs)
}

procs_wait :: proc(procs: Procs) -> bool {
    return _api.procs_wait(procs)
}

procs_flush :: proc(procs: ^Procs) -> bool {
    return _api.procs_flush(procs)
}

nprocs :: proc() -> int {
    return _api.nprocs()
}

// -- Command builder --

cmd_create :: proc(allocator := context.allocator) -> Cmd {
    return _api.cmd_create(allocator)
}

cmd_append :: proc(cmd: ^Cmd, args: ..string) {
    _api.cmd_append(cmd, args)
}

cmd_extend :: proc(cmd: ^Cmd, other: Cmd) {
    _api.cmd_extend(cmd, other)
}

cmd_reset :: proc(cmd: ^Cmd) {
    _api.cmd_reset(cmd)
}

cmd_destroy :: proc(cmd: ^Cmd) {
    _api.cmd_destroy(cmd)
}

cmd_render :: proc(cmd: Cmd, allocator := context.temp_allocator) -> string {
    return _api.cmd_render(cmd, allocator)
}

cmd_run :: proc(cmd: ^Cmd, opt: Cmd_Run_Opt = {}) -> bool {
    return _api.cmd_run(cmd, opt)
}

cmd_run_capture :: proc(cmd: ^Cmd, allocator := context.allocator) -> (output: []u8, ok: bool) {
    return _api.cmd_run_capture(cmd, allocator)
}

// -- Directory walking --

walk_dir :: proc(root: string, callback: Walk_Proc, opt: Walk_Opt = {}) -> bool {
    return _api.walk_dir(root, callback, opt)
}

// -- Odin compiler verbs --

build :: proc(config: Build_Config) -> bool {
    return _api.build(config)
}

run :: proc(config: Build_Config, args: ..string) -> bool {
    return _api.run(config, args)
}

test :: proc(config: Build_Config) -> bool {
    return _api.test(config)
}

check :: proc(config: Build_Config) -> bool {
    return _api.check(config)
}

release_config :: proc(package_path: string, out: string) -> Build_Config {
    return _api.release_config(package_path, out)
}

debug_config :: proc(package_path: string, out: string) -> Build_Config {
    return _api.debug_config(package_path, out)
}

// -- Rebuild --

needs_rebuild :: proc(output_path: string, input_paths: []string) -> (rebuild: bool, ok: bool) {
    return _api.needs_rebuild(output_path, input_paths)
}

needs_rebuild1 :: proc(output_path: string, input_path: string) -> (rebuild: bool, ok: bool) {
    return _api.needs_rebuild1(output_path, input_path)
}

go_rebuild_urself :: proc(source_path: string, extra_sources: ..string) {
    _api.go_rebuild_urself(source_path, extra_sources)
}

// -- Timing --

nanos_now :: proc() -> i64 {
    return _api.nanos_now()
}

timer_start :: proc() -> time.Tick {
    return _api.timer_start()
}

timer_elapsed :: proc(start: time.Tick) -> f64 {
    return _api.timer_elapsed(start)
}

// -- Command chains --

chain_begin :: proc(chain: ^Chain, opt: Chain_Begin_Opt = {}) -> bool {
    return _api.chain_begin(chain, opt)
}

chain_cmd :: proc(chain: ^Chain, cmd: ^Cmd, opt: Chain_Cmd_Opt = {}) -> bool {
    return _api.chain_cmd(chain, cmd, opt)
}

chain_end :: proc(chain: ^Chain, opt: Chain_End_Opt = {}) -> bool {
    return _api.chain_end(chain, opt)
}

// -- File system operations --

mkdir_if_not_exists :: proc(path: string) -> bool {
    return _api.mkdir_if_not_exists(path)
}

mkdir_all :: proc(path: string) -> bool {
    return _api.mkdir_all(path)
}

copy_file :: proc(src_path: string, dst_path: string) -> bool {
    return _api.copy_file(src_path, dst_path)
}

read_entire_file :: proc(path: string, allocator := context.allocator) -> (data: []u8, ok: bool) {
    return _api.read_entire_file(path, allocator)
}

write_entire_file :: proc(path: string, data: []u8) -> bool {
    return _api.write_entire_file(path, data)
}

write_entire_file_string :: proc(path: string, content: string) -> bool {
    return _api.write_entire_file_string(path, content)
}

delete_file :: proc(path: string) -> bool {
    return _api.delete_file(path)
}

remove_all :: proc(path: string) -> bool {
    return _api.remove_all(path)
}

rename_file :: proc(old_path: string, new_path: string) -> bool {
    return _api.rename_file(old_path, new_path)
}

get_file_type :: proc(path: string) -> (File_Type, bool) {
    return _api.get_file_type(path)
}

file_exists :: proc(path: string) -> bool {
    return _api.file_exists(path)
}

read_entire_dir :: proc(dir_path: string, allocator := context.allocator) -> (names: []string, ok: bool) {
    return _api.read_entire_dir(dir_path, allocator)
}

copy_directory_recursively :: proc(src_path: string, dst_path: string) -> bool {
    return _api.copy_directory_recursively(src_path, dst_path)
}
