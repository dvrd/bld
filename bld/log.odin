package bld

// Logging subsystem for build scripts.
// Mirrors nob.h log levels with idiomatic Odin style.

import "core:fmt"
import "core:io"
import "core:os"

Log_Level :: enum {
    Info,
    Warning,
    Error,
    No_Logs,
}

// Any messages with a level below this are suppressed.
minimal_log_level: Log_Level = .Info

// Whether to echo actions like command execution, mkdir, copy, etc.
echo_actions: bool = true

log_info :: proc(format: string, args: ..any) {
    nob_log(.Info, format, ..args)
}

log_warn :: proc(format: string, args: ..any) {
    nob_log(.Warning, format, ..args)
}

log_error :: proc(format: string, args: ..any) {
    nob_log(.Error, format, ..args)
}

nob_log :: proc(level: Log_Level, format: string, args: ..any) {
    if level < minimal_log_level do return

    w := io.to_writer(os.stream_from_handle(os.stderr))

    switch level {
    case .Info:    fmt.wprint(w, "[INFO] ")
    case .Warning: fmt.wprint(w, "[WARNING] ")
    case .Error:   fmt.wprint(w, "[ERROR] ")
    case .No_Logs: return
    }

    fmt.wprintf(w, format, ..args)
    fmt.wprintln(w)
}
