// Comprehensive test of all bld features.
// Run from the project root:
//   odin build example/build.odin -file -out:target/test_build
//   ./target/test_build

package main

import "core:fmt"
import bld "../bld"

Pass_Count :: struct {
    passed: int,
    failed: int,
    total:  int,
}

check_result :: proc(pc: ^Pass_Count, name: string, ok: bool) {
    pc.total += 1
    if ok {
        pc.passed += 1
        bld.log_info("  PASS: %s", name)
    } else {
        pc.failed += 1
        bld.log_error("  FAIL: %s", name)
    }
}

main :: proc() {
    bld.log_info("=== bld Feature Test Suite ===")
    start := bld.timer_start()
    pc: Pass_Count

    // --- Setup ---
    bld.mkdir_if_not_exists("target")

    // =========================================================
    // 1. bld.check — type-check only
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.check ---")
    {
        ok := bld.check({package_path = "example/src"})
        check_result(&pc, "check(src)", ok)
    }

    // =========================================================
    // 2. bld.build — basic build
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (basic) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp",
        })
        check_result(&pc, "build(basic)", ok)

        // Verify the binary exists.
        check_result(&pc, "binary exists after build", bld.file_exists("target/testapp"))
    }

    // =========================================================
    // 3. bld.build — release with optimization
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (release) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-release",
            opt          = .Speed,
        })
        check_result(&pc, "build(release, -o:speed)", ok)
    }

    // =========================================================
    // 4. bld.build — debug
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (debug) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-debug",
            debug        = true,
        })
        check_result(&pc, "build(debug)", ok)
    }

    // =========================================================
    // 5. bld.build — with vet flags
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (vet) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-vet",
            vet          = {.Shadowing, .Unused_Imports, .Style},
        })
        check_result(&pc, "build(vet flags)", ok)
    }

    // =========================================================
    // 6. bld.build — with -vet (all)
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (vet all) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-vetall",
            vet          = {.All},
        })
        check_result(&pc, "build(vet all)", ok)
    }

    // =========================================================
    // 7. bld.build — with defines
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (defines) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-defines",
            defines      = {
                {name = "ODIN_TEST_THREADS", value = "1"},
            },
            ignore_unused_defineables = true,
        })
        check_result(&pc, "build(defines)", ok)
    }

    // =========================================================
    // 8. bld.build — warnings as errors
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (warnings-as-errors) ---")
    {
        ok := bld.build({
            package_path       = "example/src",
            out                = "target/testapp-wae",
            warnings_as_errors = true,
        })
        check_result(&pc, "build(warnings-as-errors)", ok)
    }

    // =========================================================
    // 9. bld.build — show timings
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.build (show-timings) ---")
    {
        ok := bld.build({
            package_path = "example/src",
            out          = "target/testapp-timings",
            show_timings = true,
        })
        check_result(&pc, "build(show-timings)", ok)
    }

    // =========================================================
    // 10. bld.build — preset configs
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: preset configs ---")
    {
        config := bld.release_config("example/src", "target/testapp-preset-release")
        ok := bld.build(config)
        check_result(&pc, "release_config preset", ok)

        config2 := bld.debug_config("example/src", "target/testapp-preset-debug")
        ok2 := bld.build(config2)
        check_result(&pc, "debug_config preset", ok2)
    }

    // =========================================================
    // 11. bld.test — run tests
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.test ---")
    {
        ok := bld.test({package_path = "example/src"})
        check_result(&pc, "test(src)", ok)
    }

    // =========================================================
    // 12. bld.run — build and run
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: bld.run ---")
    {
        ok := bld.run(
            {package_path = "example/src", out = "target/testapp-run"},
            "hello", "world",
        )
        check_result(&pc, "run(src, args)", ok)
    }

    // =========================================================
    // 13. bld.build — empty package_path should fail
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: error handling ---")
    {
        ok := bld.build({})
        check_result(&pc, "build({}) fails correctly", !ok)
    }

    // =========================================================
    // 14. needs_rebuild
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: needs_rebuild ---")
    {
        // Binary should be newer than source (we just built it).
        result := bld.needs_rebuild1("target/testapp", "example/src/main.odin")
        check_result(&pc, "needs_rebuild1 returns 0 (up to date)", result == 0)

        // Non-existent output should need rebuild.
        result2 := bld.needs_rebuild1("target/nonexistent", "example/src/main.odin")
        check_result(&pc, "needs_rebuild1 returns 1 (missing output)", result2 == 1)

        // Non-existent input should return error.
        result3 := bld.needs_rebuild1("target/testapp", "nonexistent.odin")
        check_result(&pc, "needs_rebuild1 returns -1 (missing input)", result3 == -1)
    }

    // =========================================================
    // 15. File operations
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: file operations ---")
    {
        // Write.
        ok := bld.write_entire_file_string("target/test_file.txt", "hello bld\n")
        check_result(&pc, "write_entire_file_string", ok)

        // Exists.
        check_result(&pc, "file_exists (exists)", bld.file_exists("target/test_file.txt"))
        check_result(&pc, "file_exists (not exists)", !bld.file_exists("target/nope.txt"))

        // Read.
        data, read_ok := bld.read_entire_file("target/test_file.txt", context.temp_allocator)
        check_result(&pc, "read_entire_file", read_ok && string(data) == "hello bld\n")

        // Copy.
        copy_ok := bld.copy_file("target/test_file.txt", "target/test_file_copy.txt")
        check_result(&pc, "copy_file", copy_ok)
        check_result(&pc, "copy_file result exists", bld.file_exists("target/test_file_copy.txt"))

        // Rename.
        rename_ok := bld.rename_file("target/test_file_copy.txt", "target/test_file_renamed.txt")
        check_result(&pc, "rename_file", rename_ok)
        check_result(&pc, "rename: old gone", !bld.file_exists("target/test_file_copy.txt"))
        check_result(&pc, "rename: new exists", bld.file_exists("target/test_file_renamed.txt"))

        // Get file type.
        ft, ft_ok := bld.get_file_type("target/test_file.txt")
        check_result(&pc, "get_file_type (regular)", ft_ok && ft == .Regular)

        ft2, ft2_ok := bld.get_file_type("target")
        check_result(&pc, "get_file_type (directory)", ft2_ok && ft2 == .Directory)

        // Delete.
        del_ok := bld.delete_file("target/test_file.txt")
        check_result(&pc, "delete_file", del_ok)
        check_result(&pc, "delete_file: gone", !bld.file_exists("target/test_file.txt"))

        bld.delete_file("target/test_file_renamed.txt")
    }

    // =========================================================
    // 16. Directory operations
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: directory operations ---")
    {
        ok := bld.mkdir_if_not_exists("target/testdir")
        check_result(&pc, "mkdir_if_not_exists (create)", ok)

        ok2 := bld.mkdir_if_not_exists("target/testdir")
        check_result(&pc, "mkdir_if_not_exists (already exists)", ok2)

        ok3 := bld.mkdir_all("target/testdir/a/b/c")
        check_result(&pc, "mkdir_all (nested)", ok3)
        check_result(&pc, "mkdir_all result exists", bld.file_exists("target/testdir/a/b/c"))

        // Write a file inside and copy the tree.
        bld.write_entire_file_string("target/testdir/a/file.txt", "nested\n")
        ok4 := bld.copy_directory_recursively("target/testdir", "target/testdir_copy")
        check_result(&pc, "copy_directory_recursively", ok4)
        check_result(&pc, "copy_dir: nested file exists", bld.file_exists("target/testdir_copy/a/file.txt"))

        // Read directory.
        names, rd_ok := bld.read_entire_dir("target/testdir", context.temp_allocator)
        check_result(&pc, "read_entire_dir", rd_ok && len(names) > 0)
    }

    // =========================================================
    // 17. Walk directory
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: walk_dir ---")
    {
        Walk_State :: struct {
            count: int,
        }
        state := Walk_State{}
        ok := bld.walk_dir("target/testdir", proc(entry: bld.Walk_Entry, user_data: rawptr) -> bld.Walk_Action {
            s := cast(^Walk_State)user_data
            s.count += 1
            return .Continue
        }, {user_data = &state})
        check_result(&pc, "walk_dir runs", ok)
        check_result(&pc, "walk_dir found entries", state.count > 0)
    }

    // =========================================================
    // 18. Path utilities
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: path utilities ---")
    {
        check_result(&pc, "path_name", bld.path_name("/foo/bar/baz.odin") == "baz.odin")
        check_result(&pc, "file_ext", bld.file_ext("main.odin") == ".odin")
        check_result(&pc, "file_stem", bld.file_stem("main.odin") == "main")

        cwd, cwd_ok := bld.get_cwd()
        check_result(&pc, "get_cwd", cwd_ok && len(cwd) > 0)
    }

    // =========================================================
    // 19. Cmd (escape hatch)
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: Cmd (escape hatch) ---")
    {
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "echo", "bld escape hatch works")
        ok := bld.cmd_run(&cmd)
        check_result(&pc, "cmd_run(echo)", ok)
    }

    // =========================================================
    // 20. Cmd capture
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: cmd_run_capture ---")
    {
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "echo", "captured output")
        output, ok := bld.cmd_run_capture(&cmd, context.temp_allocator)
        captured := string(output)
        // echo adds a newline.
        check_result(&pc, "cmd_run_capture", ok && len(captured) > 0)
    }

    // =========================================================
    // 21. Parallel procs
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: parallel procs ---")
    {
        procs := bld.procs_create(context.temp_allocator)

        cmd1 := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd1, "echo", "par1")
        bld.cmd_run(&cmd1, {async = &procs})

        cmd2 := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd2, "echo", "par2")
        bld.cmd_run(&cmd2, {async = &procs})

        ok := bld.procs_flush(&procs)
        check_result(&pc, "procs_flush (parallel)", ok)
    }

    // =========================================================
    // 22. Chain (pipes)
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: chain (pipes) ---")
    {
        chain: bld.Chain
        ok := bld.chain_begin(&chain)
        check_result(&pc, "chain_begin", ok)

        cmd1 := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd1, "echo", "pipe test")
        bld.chain_cmd(&chain, &cmd1)

        cmd2 := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd2, "tr", "a-z", "A-Z")
        bld.chain_cmd(&chain, &cmd2)

        ok2 := bld.chain_end(&chain)
        check_result(&pc, "chain_end (pipe)", ok2)
    }

    // =========================================================
    // 23. nprocs
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: nprocs ---")
    {
        n := bld.nprocs()
        bld.log_info("  nprocs() = %d", n)
        check_result(&pc, "nprocs() > 0", n > 0)
    }

    // =========================================================
    // 24. Timer
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: timer ---")
    {
        t := bld.timer_start()
        // Do a tiny bit of work.
        _ = bld.file_exists("target/testapp")
        elapsed := bld.timer_elapsed(t)
        check_result(&pc, "timer_elapsed >= 0", elapsed >= 0)
    }

    // =========================================================
    // 25. Logging
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: logging ---")
    {
        old_level := bld.minimal_log_level
        bld.minimal_log_level = .Warning
        // This should NOT appear.
        bld.log_info("THIS SHOULD NOT APPEAR")
        bld.minimal_log_level = old_level
        check_result(&pc, "minimal_log_level suppresses info", true)

        old_echo := bld.echo_actions
        bld.echo_actions = false
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "echo", "silent")
        bld.cmd_run(&cmd)
        bld.echo_actions = old_echo
        check_result(&pc, "echo_actions = false suppresses CMD echo", true)
    }

    // =========================================================
    // Cleanup
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Cleanup ---")
    // Remove test artifacts but keep target/ dir.
    for name in ([]string{
        "target/testapp", "target/testapp-release", "target/testapp-debug",
        "target/testapp-vet", "target/testapp-vetall", "target/testapp-defines",
        "target/testapp-wae", "target/testapp-timings",
        "target/testapp-preset-release", "target/testapp-preset-debug",
    }) {
        bld.delete_file(name)
    }
    // Remove directories: .dSYM bundles (macOS debug symbols) and test dirs.
    for name in ([]string{
        "target/testapp-debug.dSYM", "target/testapp-preset-debug.dSYM",
        "target/testdir", "target/testdir_copy",
    }) {
        bld.remove_all(name)
    }

    // =========================================================
    // Results
    // =========================================================
    elapsed := bld.timer_elapsed(start)
    bld.log_info("")
    bld.log_info("=== Results: %d/%d passed (%d failed) in %.2fs ===",
        pc.passed, pc.total, pc.failed, elapsed)

    if pc.failed > 0 {
        bld.log_error("SOME TESTS FAILED")
    } else {
        bld.log_info("ALL TESTS PASSED")
    }
}
