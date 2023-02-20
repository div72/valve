module main

import flag
import os
import v.ast
import v.builder
import v.pref

fn main() {
    mut fp := flag.new_flag_parser(os.args)

    fp.application("valve")
    fp.version("v1.0.0")
    fp.description("A basic static analyzer powered by Z3. Verifies assertions and array accesses.")
    fp.skip_executable()
    verbose := fp.bool("verbose", `v`, false, "enables verbose mode. reports facts used in assertions.")
    fp.limit_free_args_to_exactly(1)!
    fp.arguments_description("file")
    files := fp.finalize() or {
        // TODO: handle other errors.
        eprintln("error: You need to specify a file.")
        eprintln(fp.usage())
        exit(2)
    }

    if !os.is_file(files[0]) || !os.is_readable(files[0]) {
        eprintln("error: not readable file: ${files[0]}")
        exit(2)
    }

    // The builder is used here as file dependencies are needed to properly
    // check the file.
    mut p := pref.new_preferences()
    p.is_shared = true
    p.lookup_path << find_vlib()

    mut b := builder.new_builder(p)
    mut all_files := []string{cap: files.len + 100}
    all_files << files
    all_files << b.get_builtin_files()
    b.front_and_middle_stages(all_files)!

    // FIXME: V bug? source_fn is not properly initialized in some trivial
    // cases.
    for file in b.parsed_files {
        for stmt in file.stmts {
            if stmt is ast.FnDecl {
                b.table.fns[stmt.name].source_fn = voidptr(&stmt)
            }
        }
    }

    mut verifier := new_verifier(files[0], b.table, verbose)
    defer { verifier.free() }

    normalised_files := files.map(os.norm_path(os.abs_path(it)))
    for file in b.parsed_files {
        if os.norm_path(os.abs_path(file.path)) !in normalised_files {
            continue
        }

        for stmt in file.stmts {
            // We only feed the main to the verifier. The verifier should
            // visit the called on its own.
            if stmt is ast.FnDecl && (stmt as ast.FnDecl).short_name != "main" {
                continue
            }

            verifier.visit(stmt) or { continue }
        }
    }

    if verifier.error_count > 0 {
        exit(1)
    }
}
