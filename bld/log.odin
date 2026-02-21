package bld

// Logging subsystem for build scripts.

import "core:fmt"
import "core:os"

Log_Level :: enum {
    Info,
    Warning,
    Error,
    No_Logs,
}

// Any messages with a level below this are suppressed.
@(export, link_name="bld_minimal_log_level")
minimal_log_level: Log_Level = .Info

// Whether to echo actions like command execution, mkdir, copy, etc.
@(export, link_name="bld_echo_actions")
echo_actions: bool = true

log_info :: proc(format: string, args: ..any) {
    _log_impl(.Info, format, ..args)
}

log_warn :: proc(format: string, args: ..any) {
    _log_impl(.Warning, format, ..args)
}

log_error :: proc(format: string, args: ..any) {
    _log_impl(.Error, format, ..args)
}

// Exported companions for dynlib — take slice instead of variadic.
@(export, link_name="bld_log_info")
_bld_log_info :: proc(format: string, args: []any) {
    _log_impl(.Info, format, ..args)
}

@(export, link_name="bld_log_warn")
_bld_log_warn :: proc(format: string, args: []any) {
    _log_impl(.Warning, format, ..args)
}

@(export, link_name="bld_log_error")
_bld_log_error :: proc(format: string, args: []any) {
    _log_impl(.Error, format, ..args)
}

@(private = "file")
_log_impl :: proc(level: Log_Level, format: string, args: ..any) {
    if level < minimal_log_level do return

    switch level {
    case .Info:    fmt.fprint(os.stderr, "[INFO] ")
    case .Warning: fmt.fprint(os.stderr, "[WARNING] ")
    case .Error:   fmt.fprint(os.stderr, "[ERROR] ")
    case .No_Logs: return
    }

    fmt.fprintf(os.stderr, format, ..args)
    fmt.fprintln(os.stderr)
}
