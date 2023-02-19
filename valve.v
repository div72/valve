module main

import os
import v.ast
import v.parser
import v.pref
import v.token
import v.util as vutil

[noinit]
struct Verifier {
    file_path string
    verbose bool
    table ast.Table
mut:
    error_count int

    ctx C.Z3_context
    // TODO: does Z3 have a mechanism for this?
    facts []C.Z3_ast
}

fn new_verifier(file_path string, table ast.Table, verbose bool) Verifier {
    cfg := C.Z3_mk_config()
    defer { C.Z3_del_config(cfg) }

    ctx := C.Z3_mk_context(cfg)

    return Verifier{ctx: ctx, file_path: file_path, table: table, verbose: verbose}
}

fn (mut v Verifier) free() {
    C.Z3_del_context(v.ctx)
}

fn (mut v Verifier) error(msg string, pos token.Pos) {
    eprintln(vutil.formatted_error("error:", msg, v.file_path, pos))
    v.error_count += 1
}

fn (mut v Verifier) make_variable(name string) C.Z3_ast {
    symbol := C.Z3_mk_string_symbol(v.ctx, name.str)
    return C.Z3_mk_const(v.ctx, symbol, C.Z3_mk_int_sort(v.ctx))
}

fn (mut v Verifier) ensure(expr C.Z3_ast) bool {
    // It seems like solvers are single use.
    solver := C.Z3_mk_solver(v.ctx)
    C.Z3_solver_inc_ref(v.ctx, solver)

    if v.verbose {
        unsafe {
            eprintln("Attempting to ensure: ${tos2(C.Z3_ast_to_string(v.ctx, expr))}")
            eprintln("with facts: ${v.facts.map(tos2(C.Z3_ast_to_string(v.ctx, it))).join('; ')}")
        }
    }

    // Since Z3 can only check if an expression is satisfiable or not,
    // we check if the opposite expression is not satisfiable in order
    // to see if the expression is always true.
    v.facts << C.Z3_mk_not(v.ctx, expr)
    C.Z3_solver_assert(v.ctx, solver, C.Z3_mk_and(v.ctx, v.facts.len, v.facts.data))
    v.facts.pop()

    ret := C.Z3_solver_check(v.ctx, solver)
    match ret {
        C.Z3_L_FALSE {
            // proved
            return true
        }
        C.Z3_L_UNDEF, C.Z3_L_TRUE {
            // unknown/disproven
            return false
        }
        else {
            panic("unexpected state from solver: ${ret}")
        }
    }

    C.Z3_solver_dec_ref(v.ctx, solver)
}

pub fn (mut v Verifier) visit(node &ast.Node) C.Z3_ast {
    match node {
        ast.Expr {
            match node {
                ast.BoolLiteral {
                    return if node.val { C.Z3_mk_true(v.ctx) } else { C.Z3_mk_false(v.ctx) }
                }
                ast.CallExpr {
                    for arg in node.args {
                        v.visit(arg.expr)
                    }
                }
                ast.IfExpr {
                    // Else and other branches not handled yet.
                    // If is also being treated as a stmt rather than an
                    // expression. That makes things easier and less
                    // complicated for now.
                    v.facts << v.visit(node.branches[0].cond)
                    for stmt in node.branches[0].stmts {
                        v.visit(stmt)
                    }
                    v.facts.pop()
                }
                ast.IndexExpr {
                    if node.index is ast.IntegerLiteral {
                        left := get_name(node.left) or { v.error("could not get name of expression. (use temp?)", node.pos) return C.Z3_mk_true(v.ctx) }
                        var := v.make_variable("${left}_len")
                        if !v.ensure(C.Z3_mk_lt(v.ctx, v.visit(ast.Expr(node.index)), var)) {
                            v.error("cannot ensure array access is in bounds", node.pos)
                        }
                    } else {
                        eprintln("unhandled index expr type: ${node.index.type_name()}")
                    }
                }
                ast.InfixExpr {
                    match node.op {
                        .eq {
                            return C.Z3_mk_eq(v.ctx, v.visit(node.left), v.visit(node.right))
                        }
                        .ne {
                            args := [v.visit(node.left), v.visit(node.right)]!
                            return C.Z3_mk_distinct(v.ctx, 2, &args[0])
                        }
                        .gt {
                            return C.Z3_mk_gt(v.ctx, v.visit(node.left), v.visit(node.right))
                        }
                        .lt {
                            return C.Z3_mk_lt(v.ctx, v.visit(node.left), v.visit(node.right))
                        }
                        .ge {
                            return C.Z3_mk_ge(v.ctx, v.visit(node.left), v.visit(node.right))
                        }
                        .le {
                            return C.Z3_mk_le(v.ctx, v.visit(node.left), v.visit(node.right))
                        }
                        .and {
                            args := [v.visit(node.left), v.visit(node.right)]!
                            return C.Z3_mk_and(v.ctx, 2, &args[0])
                        }
                        .logical_or {
                            args := [v.visit(node.left), v.visit(node.right)]!
                            return C.Z3_mk_or(v.ctx, 2, &args[0])
                        }
                        else {
                            eprintln("unhandled op in infix expr: ${node.op}")
                        }
                    }
                }
                ast.IntegerLiteral {
                    return C.Z3_mk_int64(v.ctx, node.val.i64(), C.Z3_mk_int_sort(v.ctx))
                }
                ast.PrefixExpr {
                    match node.op {
                        .not {
                            return C.Z3_mk_not(v.ctx, v.visit(node.right))
                        }
                        else {
                            eprintln("unhandled op in prefix expr: ${node.op}")
                        }
                    }
                }
                else {
                    eprintln("unhandled expr type: ${node.type_name()}")
                }
            }
        }
        ast.Stmt {
            match node {
                ast.AssertStmt {
                    expr := v.visit(node.expr)

                    if !v.ensure(expr) {
                        v.error("failed to prove assertion", node.pos)
                    }
                }
                ast.ExprStmt {
                    return v.visit(node.expr)
                }
                ast.FnDecl {
                    for stmt in node.stmts {
                        v.visit(stmt)
                    }
                }
                ast.AsmStmt, ast.Module {}
                else {
                    eprintln("unhandled stmt type: ${node.type_name()}")
                }
            }
        }
        else {
            eprintln("unhandled node type: ${node.type_name()}")
        }
    }

    return C.Z3_mk_true(v.ctx)
}

fn main() {
    if os.args.len != 2 {
        eprintln("USAGE: valve <file name>")
        eprintln("\nA basic static analyzer powered by Z3. Checks if a V programs assertions are provable.")
        exit(2)
    }

    file_name := os.args[1]
    if !os.is_file(file_name) || !os.is_readable(file_name) {
        eprintln("error: not readable file: ${file_name}")
    }

    table := ast.new_table()
    pref_ := &pref.Preferences{}

    parsed_file := parser.parse_file(file_name, table, .parse_comments, pref_)

    mut verifier := new_verifier(file_name, table, false)
    defer { verifier.free() }
    for stmt in parsed_file.stmts {
        verifier.visit(stmt)
    }

    if verifier.error_count > 0 {
        exit(1)
    }
}
