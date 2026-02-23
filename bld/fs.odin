package bld

// File system operations: mkdir, copy, read, write, delete, rename.

import "base:runtime"
import "core:os"
import "core:strings"

// File type classification.
File_Type :: enum {
    Regular,
    Directory,
    Symlink,
    Other,
}

// Create a directory if it does not already exist.
@(export, link_name="bld_mkdir_if_not_exists")
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

// Create directories recursively (like mkdir -p).
@(export, link_name="bld_mkdir_all")
mkdir_all :: proc(path: string) -> bool {
    err := os.mkdir_all(path)
    if err != nil {
        if err == .Exist {
            if echo_actions do log_info("directory tree '%s' already exists", path)
            return true
        }
        log_error("Could not create directory tree '%s': %v", path, err)
        return false
    }
    if echo_actions do log_info("created directory tree '%s'", path)
    return true
}

// Copy a single file from src to dst using streaming (constant memory).
// Preserves the source file's permission bits on the destination.
@(export, link_name="bld_copy_file")
copy_file :: proc(src_path, dst_path: string) -> bool {
    if echo_actions do log_info("copying %s -> %s", src_path, dst_path)

    // Stat source to capture permission bits before copying.
    src_info, stat_err := os.stat(src_path, context.temp_allocator)
    if stat_err != nil {
        log_error("Could not stat '%s': %v", src_path, stat_err)
        return false
    }
    defer os.file_info_delete(src_info, context.temp_allocator)

    src, src_err := os.open(src_path, {.Read})
    if src_err != nil {
        log_error("Could not open '%s' for reading: %v", src_path, src_err)
        return false
    }
    defer os.close(src)

    dst, dst_err := os.open(dst_path, {.Write, .Create, .Trunc})
    if dst_err != nil {
        log_error("Could not open '%s' for writing: %v", dst_path, dst_err)
        return false
    }
    // No defer — we manage dst close explicitly to handle partial-write cleanup.

    COPY_BUF_SIZE :: 64 * 1024 // 64 KB
    buf: [COPY_BUF_SIZE]u8

    copy_ok := true
    for {
        n, read_err := os.read(src, buf[:])
        if n > 0 {
            _, write_err := os.write(dst, buf[:n])
            if write_err != nil {
                log_error("Could not write to '%s': %v", dst_path, write_err)
                copy_ok = false
                break
            }
        }
        if read_err != nil {
            if read_err == .EOF do break
            log_error("Could not read from '%s': %v", src_path, read_err)
            copy_ok = false
            break
        }
        if n == 0 do break
    }

    os.close(dst)

    if !copy_ok {
        // Remove partial destination file to avoid leaving corrupt data on disk.
        os.remove(dst_path)
        return false
    }

    // Apply source file's permission bits to the destination (best effort —
    // some filesystems like FAT/exFAT don't support POSIX permissions).
    chmod_err := os.chmod(dst_path, src_info.mode)
    if chmod_err != nil {
        log_warn("Could not set permissions on '%s': %v (content copied successfully)", dst_path, chmod_err)
    }

    return true
}

// Read an entire file into a byte slice.
@(export, link_name="bld_read_entire_file")
read_entire_file :: proc(
    path: string,
    allocator := context.allocator,
) -> (data: []u8, ok: bool) {
    result, err := os.read_entire_file_from_path(path, allocator)
    if err != nil {
        log_error("Could not read file '%s': %v", path, err)
        return nil, false
    }
    return result, true
}

// Write data to a file (creates or truncates).
@(export, link_name="bld_write_entire_file")
write_entire_file :: proc(path: string, data: []u8) -> bool {
    err := os.write_entire_file(path, data)
    if err != nil {
        log_error("Could not write file '%s': %v", path, err)
        return false
    }
    return true
}

// Write a string to a file (creates or truncates).
@(export, link_name="bld_write_entire_file_string")
write_entire_file_string :: proc(path: string, content: string) -> bool {
    err := os.write_entire_file(path, content)
    if err != nil {
        log_error("Could not write file '%s': %v", path, err)
        return false
    }
    return true
}

// Delete a file.
@(export, link_name="bld_delete_file")
delete_file :: proc(path: string) -> bool {
    err := os.remove(path)
    if err != nil {
        log_error("Could not delete '%s': %v", path, err)
        return false
    }
    return true
}

// Remove a file or directory recursively (like rm -rf).
@(export, link_name="bld_remove_all")
remove_all :: proc(path: string) -> bool {
    err := os.remove_all(path)
    if err != nil {
        log_error("Could not remove '%s': %v", path, err)
        return false
    }
    return true
}

// Rename or move a file.
@(export, link_name="bld_rename_file")
rename_file :: proc(old_path, new_path: string) -> bool {
    err := os.rename(old_path, new_path)
    if err != nil {
        log_error("Could not rename '%s' to '%s': %v", old_path, new_path, err)
        return false
    }
    return true
}

// Get the type of a file.
@(export, link_name="bld_get_file_type")
get_file_type :: proc(path: string) -> (File_Type, bool) {
    info, err := os.stat(path, context.temp_allocator)
    if err != nil {
        return .Other, false
    }
    defer os.file_info_delete(info, context.temp_allocator)

    #partial switch info.type {
    case .Regular:      return .Regular, true
    case .Directory:    return .Directory, true
    case .Symlink:      return .Symlink, true
    case:               return .Other, true
    }
}

// Check if a file exists.
@(export, link_name="bld_file_exists")
file_exists :: proc(path: string) -> bool {
    _, err := os.stat(path, context.temp_allocator)
    return err == nil
}

// Read all entries in a directory (names only, not full paths).
// Always reads directory entries with temp allocator internally,
// then clones names into the caller's allocator.
@(export, link_name="bld_read_entire_dir")
read_entire_dir :: proc(
    dir_path: string,
    allocator := context.allocator,
) -> (names: []string, ok: bool) {
    f, open_err := os.open(dir_path)
    if open_err != nil {
        log_error("Could not open directory '%s': %v", dir_path, open_err)
        return nil, false
    }
    defer os.close(f)

    infos, read_err := os.read_all_directory(f, context.temp_allocator)
    if read_err != nil {
        log_error("Could not read directory '%s': %v", dir_path, read_err)
        return nil, false
    }
    defer os.file_info_slice_delete(infos, context.temp_allocator)

    result := make([]string, len(infos), allocator)
    for info, i in infos {
        result[i] = strings.clone(info.name, allocator)
    }
    return result, true
}

// Copy a directory recursively.
@(export, link_name="bld_copy_directory_recursively")
copy_directory_recursively :: proc(src_path, dst_path: string) -> bool {
    if echo_actions do log_info("copying directory %s -> %s", src_path, dst_path)

    // Temp guard: saves/restores temp allocator position to prevent
    // unbounded accumulation in deep recursive directory trees.
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    if !mkdir_if_not_exists(dst_path) do return false

    names, ok := read_entire_dir(src_path, context.temp_allocator)
    if !ok do return false

    for name in names {
        if name == "." || name == ".." do continue

        src := strings.join({src_path, "/", name}, "", context.temp_allocator)
        dst := strings.join({dst_path, "/", name}, "", context.temp_allocator)

        ft, ft_ok := get_file_type(src)
        if !ft_ok {
            log_error("Could not determine file type of '%s'", src)
            return false
        }

        switch ft {
        case .Directory:
            if !copy_directory_recursively(src, dst) do return false
        case .Regular, .Symlink, .Other:
            if !copy_file(src, dst) do return false
        }
    }

    return true
}
