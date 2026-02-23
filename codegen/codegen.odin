package main

// Codegen tool: reads bld/*.odin and generates dist/lib/bld.odin bindings.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// A parsed type definition (verbatim source text).
Type_Def :: struct {
    name:   string,
    source: string, // Full definition including "Name :: struct { ... }"
}

// A parsed proc signature.
Proc_Sig :: struct {
    name:         string,   // e.g. "build"
    link_name:    string,   // e.g. "bld_build"
    params:       string,   // e.g. "config: Build_Config"
    returns:      string,   // e.g. "bool" or "([]u8, bool)" or ""
    is_variadic:  bool,     // true if any param uses ..
    is_companion: bool,     // true if this is a _bld_xxx companion
    source_file:  string,   // e.g. "log.odin"
}

// A parsed global variable.
Global_Var :: struct {
    name:      string,   // e.g. "minimal_log_level"
    link_name: string,   // e.g. "bld_minimal_log_level"
    type_name: string,   // e.g. "Log_Level"
}

BLD_VERSION :: "0.1.0"

// Desired type output order.
TYPE_ORDER :: [?]string{
    "Log_Level", "File_Type", "Opt_Level", "Build_Mode",
    "Vet_Flag", "Vet_Flags", "Sanitize_Flag", "Sanitize_Flags",
    "Error_Pos_Style", "Collection", "Define", "Build_Config",
    "Cmd", "Cmd_Run_Opt", "Tracked_Process", "Procs",
    "Chain", "Chain_Begin_Opt", "Chain_Cmd_Opt", "Chain_End_Opt",
    "Walk_Action", "Walk_Entry", "Walk_Proc", "Walk_Opt",
}

// Section definitions for wrapper proc ordering.
Section :: struct {
    comment:     string,
    source_file: string,
}

SECTIONS :: [?]Section{
    {comment = "// -- Logging (variadic) --",        source_file = "log.odin"},
    {comment = "// -- Path utilities --",             source_file = "path.odin"},
    {comment = "// -- Process management --",         source_file = "procs.odin"},
    {comment = "// -- Command builder --",            source_file = "cmd.odin"},
    {comment = "// -- Directory walking --",          source_file = "walk.odin"},
    {comment = "// -- Odin compiler verbs --",        source_file = "odin.odin"},
    {comment = "// -- Rebuild --",                    source_file = "rebuild.odin"},
    {comment = "// -- Timing --",                     source_file = "time.odin"},
    {comment = "// -- Command chains --",             source_file = "chain.odin"},
    {comment = "// -- File system operations --",     source_file = "fs.odin"},
}

// API struct section comments (for _Bld_API struct).
API_Section :: struct {
    comment:     string,
    source_file: string,
}

API_SECTIONS :: [?]API_Section{
    {comment = "// From log.odin (companions \u2014 take []any):",                   source_file = "log.odin"},
    {comment = "// From path.odin:",                                                  source_file = "path.odin"},
    {comment = "// From procs.odin:",                                                 source_file = "procs.odin"},
    {comment = "// From cmd.odin (cmd_append companion takes []string):",             source_file = "cmd.odin"},
    {comment = "// From walk.odin:",                                                  source_file = "walk.odin"},
    {comment = "// From odin.odin (run companion takes []string):",                   source_file = "odin.odin"},
    {comment = "// From rebuild.odin (go_rebuild_urself companion takes []string):",  source_file = "rebuild.odin"},
    {comment = "// From time.odin:",                                                  source_file = "time.odin"},
    {comment = "// From chain.odin:",                                                 source_file = "chain.odin"},
    {comment = "// From fs.odin:",                                                    source_file = "fs.odin"},
}

main :: proc() {
    // Read all .odin files in bld/
    bld_dir := "bld"
    f, open_err := os.open(bld_dir)
    if open_err != nil {
        fmt.eprintln("Could not open bld/ directory:", open_err)
        os.exit(1)
    }
    defer os.close(f)

    infos, read_err := os.read_all_directory(f, context.temp_allocator)
    if read_err != nil {
        fmt.eprintln("Could not read bld/ directory:", read_err)
        os.exit(1)
    }
    defer os.file_info_slice_delete(infos, context.temp_allocator)

    // Collect all source file contents.
    Source_File :: struct {
        name:    string,
        content: string,
    }
    sources := make([dynamic]Source_File, context.temp_allocator)

    for info in infos {
        if !strings.has_suffix(info.name, ".odin") do continue
        path := fmt.tprintf("%s/%s", bld_dir, info.name)
        data, ok := os.read_entire_file_from_path(path, context.temp_allocator)
        if ok != nil {
            fmt.eprintfln("Could not read %s: %v", path, ok)
            os.exit(1)
        }
        append(&sources, Source_File{
            name    = strings.clone(info.name, context.temp_allocator),
            content = string(data),
        })
    }

    fmt.printfln("Read %d source files from bld/", len(sources))

    // Parse types, procs, and globals from all source files.
    type_defs   := make([dynamic]Type_Def,   context.temp_allocator)
    proc_sigs   := make([dynamic]Proc_Sig,   context.temp_allocator)
    global_vars := make([dynamic]Global_Var, context.temp_allocator)

    for src in sources {
        _parse_source(src.name, src.content, &type_defs, &proc_sigs, &global_vars)
    }

    fmt.printfln("Found %d types, %d procs, %d globals", len(type_defs), len(proc_sigs), len(global_vars))

    // Fail fast: parsing found nothing useful — likely a broken source tree.
    if len(type_defs) == 0 || len(proc_sigs) == 0 || len(global_vars) == 0 {
        fmt.eprintln("Error: parsed zero types, procs, or globals — aborting codegen")
        os.exit(1)
    }

    // Validate TYPE_ORDER against parsed types — warn on mismatches.
    {
        // Check for parsed types missing from TYPE_ORDER.
        for td in type_defs {
            found := false
            for to in TYPE_ORDER {
                if td.name == to { found = true; break }
            }
            if !found {
                fmt.eprintfln("Warning: parsed type '%s' is not in TYPE_ORDER — it will sort last", td.name)
            }
        }
        // Check for TYPE_ORDER entries not found in parsed types.
        for to in TYPE_ORDER {
            found := false
            for td in type_defs {
                if td.name == to { found = true; break }
            }
            if !found {
                fmt.eprintfln("Warning: TYPE_ORDER entry '%s' was not found in parsed types", to)
            }
        }
    }

    // Sort type_defs according to TYPE_ORDER.
    slice.sort_by(type_defs[:], proc(a, b: Type_Def) -> bool {
        return _type_order_index(a.name) < _type_order_index(b.name)
    })

    // Generate the bindings file.
    sb := strings.builder_make(context.temp_allocator)

    // Header.
    strings.write_string(&sb, "#+feature global-context\n\n")
    strings.write_string(&sb, "package bld\n\n")
    strings.write_string(&sb, "// Odin bindings for the bld build system library.\n")
    strings.write_string(&sb, "// Loads libbld at runtime via core:dynlib and exposes the full API through wrapper procs.\n\n")

    // Imports.
    strings.write_string(&sb, "import \"core:dynlib\"\n")
    strings.write_string(&sb, "import \"core:fmt\"\n")
    strings.write_string(&sb, "import \"core:mem\"\n")
    strings.write_string(&sb, "import \"core:os\"\n")
    strings.write_string(&sb, "import \"core:time\"\n\n")

    // Section 1: Metadata constants.
    // "// \u2500\u2500 Metadata \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 Metadata \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")
    fmt.sbprintf(&sb, "BLD_VERSION :: \"%s\"\n\n", BLD_VERSION)

    // Section 2: Type definitions.
    // "// \u2500\u2500 Types \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 Types \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")
    for td in type_defs {
        strings.write_string(&sb, td.source)
        strings.write_string(&sb, "\n\n")
    }

    // Section 3: API struct.
    // "// \u2500\u2500 API Struct \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 API Struct \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")
    strings.write_string(&sb, "@(private = \"file\")\n")
    strings.write_string(&sb, "_Bld_API :: struct {\n")

    // Emit API struct fields grouped by source file with section comments.
    for api_sec in API_SECTIONS {
        // Collect procs for this section.
        sec_procs := make([dynamic]Proc_Sig, context.temp_allocator)
        for ps in proc_sigs {
            if len(ps.link_name) == 0 do continue
            if ps.source_file != api_sec.source_file do continue
            append(&sec_procs, ps)
        }
        if len(sec_procs) == 0 do continue

        // Find max field name length for column alignment within this section.
        max_field_len := 0
        for ps in sec_procs {
            field_name := ps.link_name[4:] if strings.has_prefix(ps.link_name, "bld_") else ps.link_name
            if len(field_name) > max_field_len {
                max_field_len = len(field_name)
            }
        }

        fmt.sbprintf(&sb, "    %s\n", api_sec.comment)
        for ps in sec_procs {
            field_name := ps.link_name[4:] if strings.has_prefix(ps.link_name, "bld_") else ps.link_name
            // Expand shorthand params and strip defaults.
            expanded := _expand_shorthand_params(ps.params)
            stripped_params := _strip_defaults(expanded)
            // Pad field name for column alignment.
            padding := max_field_len - len(field_name)
            fmt.sbprintf(&sb, "    %s:", field_name)
            for _ in 0..<padding {
                strings.write_byte(&sb, ' ')
            }
            fmt.sbprintf(&sb, " proc(%s)", stripped_params)
            if len(ps.returns) > 0 {
                fmt.sbprintf(&sb, " -> %s", ps.returns)
            }
            strings.write_string(&sb, ",\n")
        }

        // Blank line between sections.
        strings.write_string(&sb, "\n")
    }

    strings.write_string(&sb, "    __handle: dynlib.Library,\n")
    strings.write_string(&sb, "}\n\n")

    // Section 4: Package-Level State.
    // "// \u2500\u2500 Package-Level State \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 Package-Level State \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")

    // API instance.
    strings.write_string(&sb, "@(private = \"file\")\n")
    strings.write_string(&sb, "_api: _Bld_API\n\n")

    // Global variable pointers.
    if len(global_vars) > 0 {
        strings.write_string(&sb, "// Global variable pointers (into DLL memory).\n")
        // Column-align the global var declarations.
        max_gv_len := 0
        for gv in global_vars {
            if len(gv.name) > max_gv_len {
                max_gv_len = len(gv.name)
            }
        }
        for gv in global_vars {
            padding := max_gv_len - len(gv.name)
            fmt.sbprintf(&sb, "%s:", gv.name)
            for _ in 0..<padding {
                strings.write_byte(&sb, ' ')
            }
            fmt.sbprintf(&sb, " ^%s\n", gv.type_name)
        }
        strings.write_string(&sb, "\n")
    }

    // Section 5: @(init) loader.
    // "// \u2500\u2500 Init \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 Init \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")
    strings.write_string(&sb, "@(init)\n")
    strings.write_string(&sb, "@(private = \"file\")\n")
    strings.write_string(&sb, "_load_bld :: proc() {\n")
    strings.write_string(&sb, "    LIB_DIR :: #directory\n\n")

    // Platform-specific dylib name.
    strings.write_string(&sb, "    when ODIN_OS == .Darwin {\n")
    strings.write_string(&sb, "        DYLIB_NAME :: \"libbld.dylib\"\n")
    strings.write_string(&sb, "    } else when ODIN_OS == .Linux {\n")
    strings.write_string(&sb, "        DYLIB_NAME :: \"libbld.so\"\n")
    strings.write_string(&sb, "    } else {\n")
    strings.write_string(&sb, "        #panic(\"Unsupported OS\")\n")
    strings.write_string(&sb, "    }\n\n")

    strings.write_string(&sb, "    dylib_path := fmt.tprintf(\"%s%s\", LIB_DIR, DYLIB_NAME)\n\n")

    strings.write_string(&sb, "    count, ok := dynlib.initialize_symbols(&_api, dylib_path, \"bld_\")\n")
    strings.write_string(&sb, "    if !ok {\n")
    strings.write_string(&sb, "        fmt.eprintfln(\"[bld] Could not load library at '%s': %s\", dylib_path, dynlib.last_error())\n")
    strings.write_string(&sb, "        os.exit(1)\n")
    strings.write_string(&sb, "    }\n\n")

    // Load global variable pointers (fail-fast on missing symbols).
    strings.write_string(&sb, "    // Load global variable pointers.\n")
    for gv in global_vars {
        // Use deterministic short names to match handwritten style:
        // minimal_log_level -> ml, echo_actions -> ea.
        // For unknown globals, use initials of underscore-separated words to avoid collision.
        short: string
        if gv.name == "minimal_log_level" {
            short = "ml"
        } else if gv.name == "echo_actions" {
            short = "ea"
        } else {
            // Build initials from underscore-separated words: "foo_bar_baz" -> "fbb".
            words := strings.split(gv.name, "_", context.temp_allocator)
            initials := make([dynamic]u8, context.temp_allocator)
            for w in words {
                if len(w) > 0 do append(&initials, w[0])
            }
            short = strings.clone_from_bytes(initials[:], context.temp_allocator)
        }
        strings.write_string(&sb, fmt.tprintf("    %s_ptr, %s_ok := dynlib.symbol_address(_api.__handle, \"%s\")\n",
            short, short, gv.link_name))
        strings.write_string(&sb, fmt.tprintf("    if !%s_ok {{\n", short))
        strings.write_string(&sb, fmt.tprintf("        fmt.eprintfln(\"[bld] Could not load '%s' from library\")\n", gv.name))
        strings.write_string(&sb, "        os.exit(1)\n")
        strings.write_string(&sb, "    }\n")
        strings.write_string(&sb, fmt.tprintf("    %s = (^%s)(%s_ptr)\n\n", gv.name, gv.type_name, short))
    }

    // Version mismatch warning using runtime lib_odin_version().
    strings.write_string(&sb, "    // Version mismatch warning: compare the dylib's baked-in version against\n")
    strings.write_string(&sb, "    // the user's compiler version (baked when they compile the bindings).\n")
    strings.write_string(&sb, "    lib_version := _api.lib_odin_version()\n")
    strings.write_string(&sb, "    if lib_version != ODIN_VERSION {\n")
    strings.write_string(&sb, "        fmt.eprintfln(\n")
    strings.write_string(&sb, "            \"[bld] Warning: library compiled with Odin %s, you are using %s. ABI mismatch may cause crashes.\",\n")
    strings.write_string(&sb, "            lib_version, ODIN_VERSION,\n")
    strings.write_string(&sb, "        )\n")
    strings.write_string(&sb, "    }\n")
    strings.write_string(&sb, "}\n\n")

    // Section 6: Wrapper procs — grouped by section with section comments.
    // "// \u2500\u2500 Wrapper Procs \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" (68 chars)
    strings.write_string(&sb, "// \u2500\u2500 Wrapper Procs \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n")

    for sec in SECTIONS {
        // Collect procs for this section.
        sec_procs := make([dynamic]Proc_Sig, context.temp_allocator)
        for ps in proc_sigs {
            if ps.source_file != sec.source_file do continue
            // Skip lib_odin_version (internal only).
            orig_name := ps.link_name[4:] if strings.has_prefix(ps.link_name, "bld_") else ps.link_name
            if orig_name == "lib_odin_version" do continue
            append(&sec_procs, ps)
        }
        if len(sec_procs) == 0 do continue

        fmt.sbprintf(&sb, "%s\n\n", sec.comment)

        for ps in sec_procs {
            field_name := ps.link_name[4:] if strings.has_prefix(ps.link_name, "bld_") else ps.link_name

            if ps.is_companion {
                // Variadic wrapper: restore variadic syntax.
                original_name := field_name
                variadic_params := _make_variadic_params(ps.params)

                fmt.sbprintf(&sb, "%s :: proc(%s)", original_name, variadic_params)
                if len(ps.returns) > 0 {
                    fmt.sbprintf(&sb, " -> %s", ps.returns)
                }
                strings.write_string(&sb, " {\n")

                param_names := _extract_param_names(ps.params)
                call_args := strings.join(param_names, ", ", context.temp_allocator)

                if len(ps.returns) > 0 {
                    fmt.sbprintf(&sb, "    return _api.%s(%s)\n", field_name, call_args)
                } else {
                    fmt.sbprintf(&sb, "    _api.%s(%s)\n", field_name, call_args)
                }
                strings.write_string(&sb, "}\n\n")
            } else {
                // Regular wrapper: expand shorthand params in the signature.
                expanded_params := _expand_shorthand_params(ps.params)
                fmt.sbprintf(&sb, "%s :: proc(%s)", ps.name, expanded_params)
                if len(ps.returns) > 0 {
                    fmt.sbprintf(&sb, " -> %s", ps.returns)
                }
                strings.write_string(&sb, " {\n")

                // Forward using original param names (from original params, not expanded).
                param_names := _extract_param_names(ps.params)
                call_args := strings.join(param_names, ", ", context.temp_allocator)

                if len(ps.returns) > 0 {
                    fmt.sbprintf(&sb, "    return _api.%s(%s)\n", field_name, call_args)
                } else {
                    fmt.sbprintf(&sb, "    _api.%s(%s)\n", field_name, call_args)
                }
                strings.write_string(&sb, "}\n\n")
            }
        }
    }

    // Write the output file.
    // Trim trailing newline to match handwritten file exactly.
    output := strings.to_string(sb)
    output = strings.trim_right(output, "\n")
    output = strings.concatenate({output, "\n"}, context.temp_allocator)

    // Ensure dist/lib/ exists.
    os.mkdir_all("dist/lib")

    err := os.write_entire_file("dist/lib/bld.odin", output)
    if err != nil {
        fmt.eprintln("Could not write dist/lib/bld.odin:", err)
        os.exit(1)
    }

    fmt.println("Generated dist/lib/bld.odin")
}

// Return the index of a type name in TYPE_ORDER, or a large number if not found.
@(private = "file")
_type_order_index :: proc(name: string) -> int {
    for n, i in TYPE_ORDER {
        if n == name do return i
    }
    return len(TYPE_ORDER) + 1000
}

// Parse a single source file for types, procs, and globals.
@(private = "file")
_parse_source :: proc(
    filename: string,
    content: string,
    type_defs: ^[dynamic]Type_Def,
    proc_sigs: ^[dynamic]Proc_Sig,
    global_vars: ^[dynamic]Global_Var,
) {
    lines := strings.split(content, "\n", context.temp_allocator)

    i := 0
    for i < len(lines) {
        line := lines[i]
        trimmed := strings.trim_space(line)

        // Skip empty lines, comments, imports, package declaration.
        if len(trimmed) == 0 || strings.has_prefix(trimmed, "//") ||
           strings.has_prefix(trimmed, "import ") || strings.has_prefix(trimmed, "package ") {
            i += 1
            continue
        }

        // Check for @(export, link_name="...") on the NEXT line's proc/global.
        if strings.has_prefix(trimmed, "@(export") {
            link_name := _extract_link_name(trimmed)

            // Look ahead for what this attribute applies to.
            // Could be a proc or a global variable.
            // Skip any additional attribute lines (like @(private)).
            j := i + 1
            for j < len(lines) {
                next := strings.trim_space(lines[j])
                if strings.has_prefix(next, "@(") || strings.has_prefix(next, "//") || len(next) == 0 {
                    j += 1
                    continue
                }
                break
            }

            if j < len(lines) {
                next_line := lines[j]
                next_trimmed := strings.trim_space(next_line)

                // Is it a global variable? Pattern: "name: Type = value"
                if _is_global_var(next_trimmed) {
                    gv := _parse_global_var(next_trimmed, link_name)
                    if len(gv.name) > 0 {
                        append(global_vars, gv)
                    }
                    i = j + 1
                    continue
                }

                // Is it a proc? Pattern: "name :: proc("
                if _is_proc_def(next_trimmed) {
                    // Collect the full proc signature (may span multiple lines).
                    sig_text := _collect_proc_signature(lines[:], j)
                    ps := _parse_proc_sig(sig_text, link_name, filename)
                    if len(ps.name) > 0 {
                        append(proc_sigs, ps)
                    }
                    i = j + 1
                    continue
                }
            }

            i += 1
            continue
        }

        // Check for type definitions (no @(export) needed — types are copied verbatim).
        // Pattern: "Name :: struct {", "Name :: enum {", "Name :: bit_set[", "Name :: proc("
        // Only match top-level type defs (no leading whitespace in original line).
        if _is_type_def(trimmed) && len(line) > 0 && (line[0] >= 'A' && line[0] <= 'Z') {
            // Check if preceded by @(private...) — skip private types.
            is_private := false
            for k := i - 1; k >= 0 && k >= i - 3; k -= 1 {
                prev := strings.trim_space(lines[k])
                if strings.has_prefix(prev, "@(private") {
                    is_private = true
                    break
                }
                if len(prev) == 0 || strings.has_prefix(prev, "//") {
                    continue // skip blanks and comments
                }
                break // hit a non-attribute line, stop looking
            }
            if is_private {
                i = _skip_block(lines[:], i)
                continue
            }

            td := _collect_type_def(lines[:], i)
            if len(td.name) > 0 {
                append(type_defs, td)
            }
            // Skip past the type definition.
            i = _skip_block(lines[:], i)
            continue
        }

        i += 1
    }
}

// Extract link_name from @(export, link_name="bld_xxx").
@(private = "file")
_extract_link_name :: proc(attr_line: string) -> string {
    // Find link_name="
    idx := strings.index(attr_line, "link_name=\"")
    if idx < 0 do return ""
    start := idx + len("link_name=\"")
    end := strings.index(attr_line[start:], "\"")
    if end < 0 do return ""
    return attr_line[start:][:end]
}

// Check if a line is a global variable declaration.
// Pattern: "name: Type = value" at column 0 (no leading whitespace in original).
@(private = "file")
_is_global_var :: proc(line: string) -> bool {
    // Must contain ": " and " = " but NOT "::" (which is a constant/proc/type).
    if strings.contains(line, "::") do return false
    colon := strings.index(line, ":")
    if colon < 0 do return false
    // Name before colon must be a valid identifier (no spaces).
    name := strings.trim_space(line[:colon])
    if strings.contains(name, " ") do return false
    return true
}

// Parse a global variable declaration.
@(private = "file")
_parse_global_var :: proc(line: string, link_name: string) -> Global_Var {
    colon := strings.index(line, ":")
    if colon < 0 do return {}
    name := strings.trim_space(line[:colon])

    // Type is between ":" and "="
    rest := line[colon + 1:]
    eq := strings.index(rest, "=")
    type_name: string
    if eq >= 0 {
        type_name = strings.trim_space(rest[:eq])
    } else {
        type_name = strings.trim_space(rest)
    }

    return Global_Var{
        name      = strings.clone(name, context.temp_allocator),
        link_name = strings.clone(link_name, context.temp_allocator),
        type_name = strings.clone(type_name, context.temp_allocator),
    }
}

// Check if a line starts a proc definition.
@(private = "file")
_is_proc_def :: proc(line: string) -> bool {
    return strings.contains(line, ":: proc(") || strings.contains(line, ":: proc (")
}

// Check if a line starts a type definition.
// Must start with an uppercase letter (Ada_Case) and contain ":: struct", ":: enum", ":: bit_set", or ":: proc(".
@(private = "file")
_is_type_def :: proc(line: string) -> bool {
    if len(line) == 0 do return false
    // Must start with uppercase letter (type names are Ada_Case).
    first := line[0]
    if first < 'A' || first > 'Z' do return false

    if strings.contains(line, ":: struct {") || strings.contains(line, ":: struct{") do return true
    if strings.contains(line, ":: enum {") || strings.contains(line, ":: enum{") do return true
    if strings.contains(line, ":: bit_set[") do return true
    // Type alias: "Name :: proc("
    if strings.contains(line, ":: proc(") do return true

    return false
}

// Collect a complete type definition (may span multiple lines for structs/enums).
// For Build_Config, applies column alignment to field names.
@(private = "file")
_collect_type_def :: proc(lines: []string, start: int) -> Type_Def {
    line := strings.trim_space(lines[start])

    // Extract name (everything before " :: ").
    name_end := strings.index(line, " :: ")
    if name_end < 0 do return {}
    name := line[:name_end]

    // For bit_set and type aliases (single line), just return the line.
    if strings.contains(line, ":: bit_set[") || !strings.contains(line, "{") {
        return Type_Def{
            name   = strings.clone(name, context.temp_allocator),
            source = strings.clone(line, context.temp_allocator),
        }
    }

    // For structs and enums, collect until closing "}".
    // Always recompute column alignment from field name lengths.

    // First pass: find max and second-max field name lengths.
    max_field_name_len := 0
    second_max_field_name_len := 0
    for i := start + 1; i < len(lines); i += 1 {
        l := strings.trim_space(lines[i])
        if l == "}" do break
        if len(l) == 0 || strings.has_prefix(l, "//") do continue
        // Find the colon that separates field name from type (not part of :=).
        colon := -1
        for ci := 0; ci < len(l); ci += 1 {
            if l[ci] == ':' {
                if ci + 1 < len(l) && l[ci+1] == '=' do continue // skip :=
                colon = ci
                break
            }
        }
        if colon > 0 {
            field_name_len := len(l[:colon])
            if field_name_len > max_field_name_len {
                second_max_field_name_len = max_field_name_len
                max_field_name_len = field_name_len
            } else if field_name_len > second_max_field_name_len {
                second_max_field_name_len = field_name_len
            }
        }
    }

    // Effective max for alignment.
    // Special case: Build_Config has default_to_panic_allocator (26) as a sole outlier
    // vs ignore_unused_defineables (25). Align to second-longest so the outlier
    // just gets 1 space rather than making all other fields 1 space wider.
    effective_max := max_field_name_len
    if name == "Build_Config" && max_field_name_len == second_max_field_name_len + 1 {
        effective_max = second_max_field_name_len
    }

    sb := strings.builder_make(context.temp_allocator)
    depth := 0

    for i := start; i < len(lines); i += 1 {
        l := lines[i]
        if i == start {
            strings.write_string(&sb, strings.trim_space(l))
        } else {
            trimmed_l := strings.trim_space(l)
            if trimmed_l == "}" {
                // Closing brace of outermost block — no indent.
                strings.write_string(&sb, "}")
            } else if max_field_name_len > 0 && len(trimmed_l) > 0 && !strings.has_prefix(trimmed_l, "//") {
                // Field line: apply alignment.
                // Find the colon (not part of :=).
                colon := -1
                for ci := 0; ci < len(trimmed_l); ci += 1 {
                    if trimmed_l[ci] == ':' {
                        if ci + 1 < len(trimmed_l) && trimmed_l[ci+1] == '=' do continue
                        colon = ci
                        break
                    }
                }
                if colon > 0 {
                    field_name := trimmed_l[:colon]
                    rest := trimmed_l[colon+1:] // everything after the colon
                    // Compute alignment: spaces = max(1, effective_max - len(name) + 1)
                    spaces := effective_max - len(field_name) + 1
                    if spaces < 1 do spaces = 1
                    strings.write_string(&sb, "    ")
                    strings.write_string(&sb, field_name)
                    strings.write_string(&sb, ":")
                    for _ in 0..<spaces {
                        strings.write_byte(&sb, ' ')
                    }
                    strings.write_string(&sb, strings.trim_left_space(rest))
                } else {
                    strings.write_string(&sb, "    ")
                    strings.write_string(&sb, trimmed_l)
                }
            } else if len(trimmed_l) == 0 {
                // Blank line inside struct — emit as empty line (no indent).
                // (nothing to write — the \n below handles it)
            } else {
                strings.write_string(&sb, "    ") // Re-indent with 4 spaces.
                strings.write_string(&sb, strings.trim_space(l))
            }
        }
        strings.write_string(&sb, "\n")

        // Count braces, but skip any inside string literals.
        in_string := false
        prev_ch: rune = 0
        for ch in l {
            if ch == '"' && prev_ch != '\\' do in_string = !in_string
            if !in_string {
                if ch == '{' do depth += 1
                if ch == '}' do depth -= 1
            }
            prev_ch = ch
        }
        if depth <= 0 && i > start do break
        if depth <= 0 && strings.contains(l, "}") do break
    }

    source := strings.to_string(sb)
    // Trim trailing newline.
    if len(source) > 0 && source[len(source)-1] == '\n' {
        source = source[:len(source)-1]
    }

    return Type_Def{
        name   = strings.clone(name, context.temp_allocator),
        source = strings.clone(source, context.temp_allocator),
    }
}

// Skip past a block (struct/enum body) to find the next statement.
@(private = "file")
_skip_block :: proc(lines: []string, start: int) -> int {
    line := lines[start]
    if !strings.contains(line, "{") {
        return start + 1 // Single-line definition.
    }

    depth := 0
    for i := start; i < len(lines); i += 1 {
        for ch in lines[i] {
            if ch == '{' do depth += 1
            if ch == '}' do depth -= 1
        }
        if depth <= 0 do return i + 1
    }
    return len(lines)
}

// Collect a proc signature that may span multiple lines.
@(private = "file")
_collect_proc_signature :: proc(lines: []string, start: int) -> string {
    sb := strings.builder_make(context.temp_allocator)
    paren_depth := 0
    found_open := false

    for i := start; i < len(lines); i += 1 {
        line := lines[i]
        trimmed := strings.trim_space(line)

        if i == start {
            strings.write_string(&sb, trimmed)
        } else {
            strings.write_string(&sb, " ")
            strings.write_string(&sb, trimmed)
        }

        for ch in line {
            if ch == '(' {
                paren_depth += 1
                found_open = true
            }
            if ch == ')' do paren_depth -= 1
        }

        // We're done when we've closed all parens and found the opening brace.
        if found_open && paren_depth <= 0 {
            break
        }
    }

    return strings.to_string(sb)
}

// Parse a proc signature string into a Proc_Sig.
@(private = "file")
_parse_proc_sig :: proc(sig: string, link_name: string, source_file: string) -> Proc_Sig {
    // Format: "name :: proc(params) -> returns {"
    // or:     "name :: proc(params) {"
    // or:     "_bld_name :: proc(params) {"

    name_end := strings.index(sig, " :: proc(")
    if name_end < 0 do return {}
    name := sig[:name_end]

    // Check if this is a companion proc.
    is_companion := strings.has_prefix(name, "_bld_")

    // Extract params: everything between first "(" and matching ")".
    open := strings.index(sig, "(")
    if open < 0 do return {}

    // Find matching close paren.
    depth := 0
    close := -1
    for idx := open; idx < len(sig); idx += 1 {
        if sig[idx] == '(' do depth += 1
        if sig[idx] == ')' {
            depth -= 1
            if depth == 0 {
                close = idx
                break
            }
        }
    }
    if close < 0 do return {}

    params := strings.trim_space(sig[open+1:close])
    // Strip trailing comma and whitespace.
    params = strings.trim_right(params, ", ")

    // Check for variadic.
    is_variadic := strings.contains(params, "..")

    // Extract return type: everything between ") -> " and " {".
    returns := ""
    arrow := strings.index(sig[close:], "->")
    if arrow >= 0 {
        ret_start := close + arrow + 2
        // Find the opening brace.
        brace := strings.index(sig[ret_start:], "{")
        if brace >= 0 {
            returns = strings.trim_space(sig[ret_start:][:brace])
        } else {
            returns = strings.trim_space(sig[ret_start:])
        }
    }

    return Proc_Sig{
        name         = strings.clone(name, context.temp_allocator),
        link_name    = strings.clone(link_name, context.temp_allocator),
        params       = strings.clone(strings.trim_space(params), context.temp_allocator),
        returns      = strings.clone(returns, context.temp_allocator),
        is_variadic  = is_variadic,
        is_companion = is_companion,
        source_file  = strings.clone(source_file, context.temp_allocator),
    }
}

// Extract parameter names from a params string for forwarding calls.
// "config: Build_Config, args: []string" -> ["config", "args"]
@(private = "file")
_extract_param_names :: proc(params: string) -> []string {
    if len(strings.trim_space(params)) == 0 do return {}

    parts := strings.split(params, ",", context.temp_allocator)
    names := make([dynamic]string, context.temp_allocator)

    for part in parts {
        trimmed := strings.trim_space(part)
        if len(trimmed) == 0 do continue

        // Handle "name: Type" or "name: Type = default" or "name := default"
        // Also handle Odin shorthand: "output_path, input_path: string" where
        // the first part has no colon — the whole trimmed string is the name.
        colon := strings.index(trimmed, ":")
        if colon >= 0 {
            name := strings.trim_space(trimmed[:colon])
            append(&names, name)
        } else {
            // Shorthand param (no colon) — the entire trimmed string is the name.
            append(&names, trimmed)
        }
    }

    return names[:]
}

// Expand Odin shorthand params: "output_path, input_path: string" -> "output_path: string, input_path: string"
@(private = "file")
_expand_shorthand_params :: proc(params: string) -> string {
    if len(strings.trim_space(params)) == 0 do return params

    parts := strings.split(params, ",", context.temp_allocator)
    result := make([dynamic]string, context.temp_allocator)

    // Walk backwards: find the type for each shorthand group.
    // A "group" is a sequence of parts where only the last has a colon.
    i := len(parts) - 1
    for i >= 0 {
        part := strings.trim_space(parts[i])
        if len(part) == 0 {
            i -= 1
            continue
        }

        // Find the colon that separates name from type (not part of :=).
        colon := -1
        for ci := 0; ci < len(part); ci += 1 {
            if part[ci] == ':' {
                if ci + 1 < len(part) && part[ci+1] == '=' do continue // skip :=
                colon = ci
                break
            }
        }
        if colon >= 0 {
            // This part has a colon — it's the type-bearing part of a group.
            type_part := strings.trim_space(part[colon+1:])
            name_part := strings.trim_space(part[:colon])

            // Emit this part as-is.
            append(&result, fmt.tprintf("%s: %s", name_part, type_part))

            // Look backwards for shorthand names (parts without type-colons).
            j := i - 1
            for j >= 0 {
                prev := strings.trim_space(parts[j])
                if len(prev) == 0 {
                    j -= 1
                    continue
                }
                // Check if this part has a type-colon (not :=).
                prev_has_colon := false
                for ci := 0; ci < len(prev); ci += 1 {
                    if prev[ci] == ':' {
                        if ci + 1 < len(prev) && prev[ci+1] == '=' do continue
                        prev_has_colon = true
                        break
                    }
                }
                if prev_has_colon {
                    break // This part has its own type — stop.
                }
                // Shorthand name — expand with the base type (no default).
                base_type := type_part
                eq := strings.index(base_type, "=")
                if eq >= 0 {
                    base_type = strings.trim_space(base_type[:eq])
                }
                append(&result, fmt.tprintf("%s: %s", prev, base_type))
                j -= 1
            }
            i = j
        } else {
            // Standalone part without colon — keep as-is.
            append(&result, part)
            i -= 1
        }
    }

    // Reverse result (we built it backwards).
    for left, right := 0, len(result)-1; left < right; left, right = left+1, right-1 {
        result[left], result[right] = result[right], result[left]
    }

    return strings.join(result[:], ", ", context.temp_allocator)
}

// Convert slice params back to variadic: "[]string" -> "..string", "[]any" -> "..any"
// Only converts the LAST slice parameter to avoid incorrectly making earlier params variadic.
@(private = "file")
_make_variadic_params :: proc(params: string) -> string {
    // Split into individual params, find the last one that's a slice type, replace only that.
    parts := strings.split(params, ",", context.temp_allocator)
    if len(parts) == 0 do return params

    // Walk backwards to find the last slice param.
    last_slice := -1
    for i := len(parts) - 1; i >= 0; i -= 1 {
        trimmed := strings.trim_space(parts[i])
        if strings.contains(trimmed, "[]any") || strings.contains(trimmed, "[]string") {
            last_slice = i
            break
        }
    }

    if last_slice < 0 do return params // No slice params found.

    // Replace only in the last slice param.
    p := parts[last_slice]
    if strings.contains(p, "[]any") {
        parts[last_slice], _ = strings.replace(p, "[]any", "..any", 1, context.temp_allocator)
    } else {
        parts[last_slice], _ = strings.replace(p, "[]string", "..string", 1, context.temp_allocator)
    }

    return strings.join(parts[:], ",", context.temp_allocator)
}

// Strip default values from a params string for use in proc pointer type fields.
// Proc pointer types in structs cannot have defaults — only proc declarations can.
// Examples:
//   "allocator := context.allocator"  -> "allocator: mem.Allocator"
//   "allocator := context.temp_allocator" -> "allocator: mem.Allocator"
//   "opt: Cmd_Run_Opt = {}"           -> "opt: Cmd_Run_Opt"
//   "name: string"                    -> "name: string"  (unchanged)
@(private = "file")
_strip_defaults :: proc(params: string) -> string {
    if len(strings.trim_space(params)) == 0 do return params

    parts := strings.split(params, ",", context.temp_allocator)
    result_parts := make([dynamic]string, context.temp_allocator)

    for part in parts {
        trimmed := strings.trim_space(part)
        if len(trimmed) == 0 do continue

        walrus := strings.index(trimmed, ":=")
        if walrus >= 0 {
            // Infer the type from the default value.
            name := strings.trim_space(trimmed[:walrus])
            value := strings.trim_space(trimmed[walrus+2:])
            if strings.contains(value, "allocator") {
                append(&result_parts, fmt.tprintf("%s: mem.Allocator", name))
            } else {
                // Unknown inferred type — emit a warning and keep the raw text.
                fmt.eprintfln("Warning: _strip_defaults cannot infer type for '%s := %s'", name, value)
                append(&result_parts, trimmed)
            }
        } else {
            // Check for "name: Type = value" pattern.
            eq := strings.index(trimmed, " = ")
            if eq >= 0 {
                // Strip the " = value" part.
                append(&result_parts, strings.trim_space(trimmed[:eq]))
            } else {
                // No default — keep as-is.
                append(&result_parts, trimmed)
            }
        }
    }

    return strings.join(result_parts[:], ", ", context.temp_allocator)
}
