package bld

// Path utilities.

import "core:os"
import "core:strings"

// Get the last component of a path (filename or directory name).
// "/path/to/file.c" -> "file.c"
@(export, link_name="bld_path_name")
path_name :: proc(path: string) -> string {
    _, name := os.split_path(path)
    return name
}

// Get the directory part of a path.
// "/path/to/file.c" -> "/path/to"
@(export, link_name="bld_dir_name")
dir_name :: proc(path: string, allocator := context.temp_allocator) -> string {
    dir, _ := os.split_path(path)
    return strings.clone(dir, allocator)
}

// Get the file extension including the dot.
// "file.tar.gz" -> ".gz"
@(export, link_name="bld_file_ext")
file_ext :: proc(path: string) -> string {
    name := path_name(path)
    for i := len(name) - 1; i >= 0; i -= 1 {
        if name[i] == '.' {
            return name[i:]
        }
    }
    return ""
}

// Get the filename without extension.
// "file.tar.gz" -> "file.tar"
@(export, link_name="bld_file_stem")
file_stem :: proc(path: string) -> string {
    name := path_name(path)
    for i := len(name) - 1; i >= 0; i -= 1 {
        if name[i] == '.' {
            return name[:i]
        }
    }
    return name
}

// Join path components with a forward slash separator.
path_join :: proc(parts: ..string) -> string {
    return strings.join(parts, "/", context.temp_allocator)
}

// Exported companion for dynlib — takes slice instead of variadic.
@(export, link_name="bld_path_join")
_bld_path_join :: proc(parts: []string) -> string {
    return strings.join(parts, "/", context.temp_allocator)
}

// Get the current working directory (temp allocated).
@(export, link_name="bld_get_cwd")
get_cwd :: proc() -> (string, bool) {
    cwd, err := os.get_working_directory(context.temp_allocator)
    if err != nil {
        log_error("Could not get current directory: %v", err)
        return "", false
    }
    return cwd, true
}

// Set the current working directory.
@(export, link_name="bld_set_cwd")
set_cwd :: proc(path: string) -> bool {
    err := os.set_working_directory(path)
    if err != nil {
        log_error("Could not set current directory to '%s': %v", path, err)
        return false
    }
    return true
}
