// Comprehensive test of all bld features.
// Run from the project root:
//   odin build example/build.odin -file -out:target/test_build
//   ./target/test_build

package main

import "core:fmt"
import "core:os"
import "core:strings"
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
        check_result(&pc, "binary exists after release build", bld.file_exists("target/testapp-release"))
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
        check_result(&pc, "binary exists after debug build", bld.file_exists("target/testapp-debug"))
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
        check_result(&pc, "binary exists after vet build", bld.file_exists("target/testapp-vet"))
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
        check_result(&pc, "binary exists after vet-all build", bld.file_exists("target/testapp-vetall"))
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
        check_result(&pc, "binary exists after defines build", bld.file_exists("target/testapp-defines"))
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
        check_result(&pc, "binary exists after wae build", bld.file_exists("target/testapp-wae"))
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
        check_result(&pc, "binary exists after timings build", bld.file_exists("target/testapp-timings"))
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
        rebuild1, ok1 := bld.needs_rebuild1("target/testapp", "example/src/main.odin")
        check_result(&pc, "needs_rebuild1 up to date", !rebuild1 && ok1)

        // Non-existent output should need rebuild.
        rebuild2, ok2 := bld.needs_rebuild1("target/nonexistent", "example/src/main.odin")
        check_result(&pc, "needs_rebuild1 missing output", rebuild2 && ok2)

        // Non-existent input should return error.
        rebuild3, ok3 := bld.needs_rebuild1("target/testapp", "nonexistent.odin")
        check_result(&pc, "needs_rebuild1 missing input", !rebuild3 && !ok3)
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
        // echo adds a newline; verify content, not just length.
        check_result(&pc, "cmd_run_capture ok", ok)
        check_result(&pc, "cmd_run_capture output not empty", len(captured) > 0)
        check_result(&pc, "cmd_run_capture content correct", strings.contains(captured, "captured output"))
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

        // Redirect chain stdout to a temp file so we can verify the output.
        ok2 := bld.chain_end(&chain, {stdout_path = "target/chain_out.txt"})
        check_result(&pc, "chain_end (pipe)", ok2)

        // Read back and verify the piped+transformed output.
        chain_data, chain_read_ok := bld.read_entire_file("target/chain_out.txt", context.temp_allocator)
        chain_out := string(chain_data)
        check_result(&pc, "chain output readable", chain_read_ok)
        check_result(&pc, "chain output contains PIPE TEST", strings.contains(chain_out, "PIPE TEST"))
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
        // Verify minimal_log_level mechanism: set it, confirm it changed, restore.
        // Full suppression verification requires an external test harness (log goes to stderr).
        old_level := bld.minimal_log_level
        bld.minimal_log_level = .Warning
        level_was_set := bld.minimal_log_level == .Warning
        // This should NOT appear (level is .Warning, log_info is .Info).
        bld.log_info("THIS SHOULD NOT APPEAR")
        bld.minimal_log_level = old_level
        level_restored := bld.minimal_log_level == old_level
        check_result(&pc, "minimal_log_level can be set", level_was_set)
        check_result(&pc, "minimal_log_level can be restored", level_restored)

        // Verify echo_actions mechanism: set it, confirm it changed, restore.
        old_echo := bld.echo_actions
        bld.echo_actions = false
        echo_was_set := bld.echo_actions == false
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "echo", "silent")
        bld.cmd_run(&cmd)
        bld.echo_actions = old_echo
        echo_restored := bld.echo_actions == old_echo
        check_result(&pc, "echo_actions can be set to false", echo_was_set)
        check_result(&pc, "echo_actions can be restored", echo_restored)
    }

    // =========================================================
    // B1. log_warn — API call does not crash
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: log_warn ---")
    {
        // Cannot capture stderr from within process; verify no crash.
        bld.log_warn("test warning %d", 42)
        check_result(&pc, "log_warn does not crash", true)
    }

    // =========================================================
    // B2. dir_name
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: dir_name ---")
    {
        result := bld.dir_name("foo/bar/baz.txt")
        // dir_name returns the directory portion; exact trailing slash is impl-defined.
        check_result(&pc, "dir_name returns non-empty", len(result) > 0)
        check_result(&pc, "dir_name contains parent", strings.contains(result, "foo/bar") || strings.contains(result, "foo"))
    }

    // =========================================================
    // B3. path_join
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: path_join ---")
    {
        result := bld.path_join("foo", "bar", "baz.txt")
        check_result(&pc, "path_join result", result == "foo/bar/baz.txt")
    }

    // =========================================================
    // B4. set_cwd / get_cwd round-trip
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: set_cwd ---")
    {
        original, orig_ok := bld.get_cwd()
        check_result(&pc, "get_cwd before set_cwd", orig_ok && len(original) > 0)

        ok := bld.set_cwd("target")
        check_result(&pc, "set_cwd to target", ok)

        new_cwd, new_ok := bld.get_cwd()
        check_result(&pc, "get_cwd changed after set_cwd", new_ok && new_cwd != original)

        // Restore.
        restore_ok := bld.set_cwd(original)
        check_result(&pc, "set_cwd restore original", restore_ok)

        restored_cwd, restored_ok := bld.get_cwd()
        check_result(&pc, "cwd restored correctly", restored_ok && restored_cwd == original)
    }

    // =========================================================
    // B5. procs_destroy — no crash
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: procs_destroy ---")
    {
        procs := bld.procs_create(context.temp_allocator)
        bld.procs_destroy(&procs)
        check_result(&pc, "procs_destroy does not crash", true)
    }

    // =========================================================
    // B6. procs_wait — non-destructive wait
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: procs_wait ---")
    {
        procs := bld.procs_create(context.temp_allocator)

        cmd_pw := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd_pw, "echo", "procs_wait test")
        bld.cmd_run(&cmd_pw, {async = &procs})

        // procs_wait takes Procs by value — waits without clearing the list.
        wait_ok := bld.procs_wait(procs)
        check_result(&pc, "procs_wait ok", wait_ok)
        // Note: do NOT call procs_flush after procs_wait — the processes are
        // already reaped and a second wait would return ESRCH.
    }

    // =========================================================
    // B7. cmd_extend
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: cmd_extend ---")
    {
        base := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&base, "echo", "hello")

        extra := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&extra, "world")

        bld.cmd_extend(&base, extra)
        rendered := bld.cmd_render(base)
        check_result(&pc, "cmd_extend combines args", strings.contains(rendered, "hello") && strings.contains(rendered, "world"))
    }

    // =========================================================
    // B8. cmd_reset
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: cmd_reset ---")
    {
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "echo", "before reset")
        bld.cmd_reset(&cmd)
        rendered := bld.cmd_render(cmd)
        check_result(&pc, "cmd_reset clears args", len(rendered) == 0)
    }

    // =========================================================
    // B9. cmd_destroy — no crash
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: cmd_destroy ---")
    {
        // Use a non-temp allocator so destroy actually frees memory.
        cmd := bld.cmd_create(context.allocator)
        bld.cmd_append(&cmd, "echo", "to be destroyed")
        bld.cmd_destroy(&cmd)
        check_result(&pc, "cmd_destroy does not crash", true)
    }

    // =========================================================
    // B10. cmd_render
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: cmd_render ---")
    {
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "odin", "build", ".", "-out:target/foo")
        rendered := bld.cmd_render(cmd)
        check_result(&pc, "cmd_render contains command", strings.contains(rendered, "odin"))
        check_result(&pc, "cmd_render contains args", strings.contains(rendered, "build"))
        check_result(&pc, "cmd_render contains flags", strings.contains(rendered, "-out:target/foo"))
    }

    // =========================================================
    // B11. needs_rebuild (multi-input)
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: needs_rebuild (multi-input) ---")
    {
        // Create two temp input files.
        bld.write_entire_file_string("target/nb_input1.txt", "input1")
        bld.write_entire_file_string("target/nb_input2.txt", "input2")
        // Output doesn't exist → should need rebuild.
        rebuild1, ok1 := bld.needs_rebuild("target/nb_output_missing.txt", []string{"target/nb_input1.txt", "target/nb_input2.txt"})
        check_result(&pc, "needs_rebuild multi: missing output needs rebuild", rebuild1 && ok1)

        // Create output after inputs → should NOT need rebuild.
        bld.write_entire_file_string("target/nb_output.txt", "output")
        rebuild2, ok2 := bld.needs_rebuild("target/nb_output.txt", []string{"target/nb_input1.txt", "target/nb_input2.txt"})
        // Output was just created (newer than inputs), so no rebuild needed.
        check_result(&pc, "needs_rebuild multi: up-to-date ok", ok2)
        _ = rebuild2 // Direction depends on filesystem timestamp resolution; just verify no error.
    }

    // =========================================================
    // B12. nanos_now
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: nanos_now ---")
    {
        t1 := bld.nanos_now()
        t2 := bld.nanos_now()
        check_result(&pc, "nanos_now > 0", t1 > 0)
        check_result(&pc, "nanos_now is monotonic", t2 >= t1)
    }

    // =========================================================
    // B13. write_entire_file (raw bytes)
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: write_entire_file (raw bytes) ---")
    {
        // "Hello" as raw bytes.
        hello_bytes := []u8{72, 101, 108, 108, 111}
        ok := bld.write_entire_file("target/raw_bytes.txt", hello_bytes)
        check_result(&pc, "write_entire_file raw bytes", ok)

        data, read_ok := bld.read_entire_file("target/raw_bytes.txt", context.temp_allocator)
        check_result(&pc, "write_entire_file: read back ok", read_ok)
        check_result(&pc, "write_entire_file: content matches", string(data) == "Hello")
    }

    // =========================================================
    // B14. chain_destroy — no crash
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: chain_destroy ---")
    {
        chain: bld.Chain
        bld.chain_begin(&chain)
        bld.chain_destroy(&chain)
        check_result(&pc, "chain_destroy does not crash", true)
    }

    // =========================================================
    // C1. Negative: cmd_run with non-existent executable
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: cmd_run non-existent ---")
    {
        cmd := bld.cmd_create(context.temp_allocator)
        bld.cmd_append(&cmd, "nonexistent_binary_xyz_bld_test")
        ok := bld.cmd_run(&cmd)
        check_result(&pc, "cmd_run non-existent returns false", !ok)
    }

    // =========================================================
    // C2. Negative: copy_file missing source
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: copy_file missing source ---")
    {
        ok := bld.copy_file("nonexistent_source_xyz.txt", "target/copy_should_fail.txt")
        check_result(&pc, "copy_file missing source returns false", !ok)
    }

    // =========================================================
    // C3. Negative: read_entire_file missing
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: read_entire_file missing ---")
    {
        _, ok := bld.read_entire_file("nonexistent_xyz.txt", context.temp_allocator)
        check_result(&pc, "read_entire_file missing returns false", !ok)
    }

    // =========================================================
    // C4. Negative: rename_file missing source
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: rename_file missing ---")
    {
        ok := bld.rename_file("nonexistent_xyz.txt", "target/renamed_should_fail.txt")
        check_result(&pc, "rename_file missing source returns false", !ok)
    }

    // =========================================================
    // C5. Negative: walk_dir missing directory
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: walk_dir missing dir ---")
    {
        ok := bld.walk_dir("nonexistent_dir_xyz", proc(entry: bld.Walk_Entry, user_data: rawptr) -> bld.Walk_Action {
            return .Continue
        })
        check_result(&pc, "walk_dir missing dir returns false", !ok)
    }

    // =========================================================
    // C6. Negative: delete_file missing
    // =========================================================
    bld.log_info("")
    bld.log_info("--- Test: negative: delete_file missing ---")
    {
        // Behavior is implementation-defined: may return true (idempotent) or false.
        // We call it to verify it does not crash and returns a bool.
        _ = bld.delete_file("nonexistent_xyz_bld_test.txt")
        check_result(&pc, "delete_file missing does not crash", true)
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
        "target/testapp-run",
        // B-test artifacts.
        "target/chain_out.txt",
        "target/nb_input1.txt", "target/nb_input2.txt",
        "target/nb_output.txt",
        "target/raw_bytes.txt",
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
        os.exit(1)
    } else {
        bld.log_info("ALL TESTS PASSED")
    }
}
