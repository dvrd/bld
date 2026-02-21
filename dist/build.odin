// Default build script for bld. Edit this file to customize your build.
// Run: odin build bld -out:build && ./build
package main

import bld "lib"

SRC_DIR :: "src"
OUT_DIR :: "target"
BINARY  :: "target/myapp"

main :: proc() {
	bld.go_rebuild_urself("bld")
	start := bld.timer_start()

	// Create output directory.
	if !bld.mkdir_if_not_exists(OUT_DIR) do return

	// Verify source directory exists.
	if !bld.file_exists(SRC_DIR) {
		bld.log_error("Source directory '%s' not found", SRC_DIR)
		return
	}

	// Fast type-check gate.
	if !bld.check({package_path = SRC_DIR}) {
		bld.log_error("Type check failed")
		return
	}

	// Run tests.
	if !bld.test({package_path = SRC_DIR}) {
		bld.log_error("Tests failed")
		return
	}

	// Build the application.
	if !bld.build({
		package_path = SRC_DIR,
		out          = BINARY,
	}) {
		bld.log_error("Build failed")
		return
	}

	bld.log_info("All done in %.2fs", bld.timer_elapsed(start))
}
