package bld

// Directory walking utilities.

import "base:runtime"
import "core:os"
import "core:strings"

// Action to take during directory walking.
Walk_Action :: enum {
    Continue,  // Continue into directories.
    Skip,      // Skip this directory (don't recurse into it). Only meaningful in pre-order mode.
    Stop,      // Stop the entire walk.
}

// Entry passed to the walk callback.
// NOTE: entry.path is temp-allocated and valid only for the duration of the callback.
// Do NOT store it — clone it with strings.clone if you need it to outlive the call.
Walk_Entry :: struct {
    path:  string,
    type:  File_Type,
    level: int,
}

// Callback for directory walking.
// Return .Continue to keep going, .Skip to skip a directory, .Stop to halt.
// entry.path is valid only during this invocation — clone if you need to keep it.
Walk_Proc :: proc(entry: Walk_Entry, user_data: rawptr) -> Walk_Action

// Walk options.
Walk_Opt :: struct {
    user_data:  rawptr,
    post_order: bool,   // Visit children before parents.
}

// Recursively walk a directory tree.
@(export, link_name="bld_walk_dir")
walk_dir :: proc(root: string, callback: Walk_Proc, opt: Walk_Opt = {}) -> bool {
    ok, _ := _walk_dir_impl(root, callback, opt, 0)
    return ok
}

// Returns (ok, stopped): ok=false means error, stopped=true means .Stop was returned.
@(private = "file")
_walk_dir_impl :: proc(
    dir_path: string,
    callback: Walk_Proc,
    opt:      Walk_Opt,
    level:    int,
) -> (ok: bool, stopped: bool) {
    // Temp guard: saves temp allocator position on entry, restores on any
    // return path. Prevents unbounded accumulation in deep recursive trees.
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    f, open_err := os.open(dir_path)
    if open_err != nil {
        log_error("Could not open directory '%s': %v", dir_path, open_err)
        return false, false
    }
    defer os.close(f)

    infos, read_err := os.read_all_directory(f, context.temp_allocator)
    if read_err != nil {
        log_error("Could not read directory '%s': %v", dir_path, read_err)
        return false, false
    }
    defer os.file_info_slice_delete(infos, context.temp_allocator)

    for info in infos {
        name := info.name
        if name == "." || name == ".." do continue

        child_path := strings.join({dir_path, "/", name}, "", context.temp_allocator)

        ft: File_Type
        #partial switch info.type {
        case .Regular:   ft = .Regular
        case .Directory: ft = .Directory
        case .Symlink:   ft = .Symlink
        case:            ft = .Other
        }

        entry := Walk_Entry{
            path  = child_path,
            type  = ft,
            level = level,
        }

        if !opt.post_order {
            action := callback(entry, opt.user_data)
            switch action {
            case .Stop:     return true, true   // Stop requested — propagate up.
            case .Skip:     continue            // Skip this directory.
            case .Continue: // Fall through.
            }
        }

        if ft == .Directory {
            child_ok, child_stopped := _walk_dir_impl(child_path, callback, opt, level + 1)
            if !child_ok do return false, false
            if child_stopped do return true, true  // Propagate stop to parent.
        }

        if opt.post_order {
            action := callback(entry, opt.user_data)
            switch action {
            case .Stop:     return true, true
            case .Skip:     // No-op in post-order: children were already visited.
            case .Continue: // Fall through.
            }
        }
    }

    return true, false
}
