// Build script for bld itself. Dogfoods bld to build the dylib, run codegen, and test.
//
// Bootstrap:  odin build build.odin -file -out:target/build_bld
// Run:        ./target/build_bld
package main

import bld "bld"

import "core:fmt"
import "core:os"

DYLIB_PATH :: "dist/lib/" + DYLIB_NAME

when ODIN_OS == .Darwin {
    DYLIB_NAME :: "libbld.dylib"
} else when ODIN_OS == .Linux {
    DYLIB_NAME :: "libbld.so"
} else {
    #panic("Unsupported OS")
}

main :: proc() {
    bld.go_rebuild_urself("build.odin", "bld")
    start := bld.timer_start()

    bld.mkdir_if_not_exists("target")

    // Step 1: Build the dylib if any bld/ source changed.
    rebuild, check_ok := bld.needs_rebuild(DYLIB_PATH, {"bld"})
    if !check_ok {
        bld.log_error("Could not check if dylib needs rebuild")
        os.exit(1)
    }

    if rebuild {
        bld.log_info("bld/ sources changed, rebuilding dylib...")
        if !bld.build({
            package_path = "bld",
            out          = DYLIB_PATH,
            build_mode   = .Dll,
        }) {
            bld.log_error("Dylib build failed")
            os.exit(1)
        }
    } else {
        bld.log_info("Dylib is up to date")
    }

    // Step 2: Run codegen to regenerate dist/lib/bld.odin.
    codegen_cmd := bld.cmd_create(context.temp_allocator)
    bld.cmd_append(&codegen_cmd, "odin", "run", "codegen")
    if !bld.cmd_run(&codegen_cmd) {
        bld.log_error("Codegen failed")
        os.exit(1)
    }

    // Step 3: Build and run the test suite.
    bld.log_info("Running test suite...")
    test_binary :: "target/test_build"
    if !bld.build({
        package_path = "example/build.odin",
        out          = test_binary,
        file_mode    = true,
    }) {
        bld.log_error("Test build failed")
        os.exit(1)
    }

    test_cmd := bld.cmd_create(context.temp_allocator)
    bld.cmd_append(&test_cmd, fmt.tprintf("./%s", test_binary))
    if !bld.cmd_run(&test_cmd) {
        bld.log_error("Tests failed")
        os.exit(1)
    }

    bld.log_info("All done in %.2fs", bld.timer_elapsed(start))
}
