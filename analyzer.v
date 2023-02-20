module main

import v.ast
import v.token
import v.util as vutil

[noinit]
struct Verifier {
    verbose bool
    table ast.Table
mut:
    file_path string
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

fn (mut v Verifier) make_variable(name string, typ ast.Type) C.Z3_ast {
    if v.verbose {
        eprintln("requesting name for ${name}")
    }
    symbol := C.Z3_mk_string_symbol(v.ctx, name.str)
    if typ.is_int() {
        return C.Z3_mk_const(v.ctx, symbol, C.Z3_mk_int_sort(v.ctx))
    } else if typ.is_bool() {
        return C.Z3_mk_const(v.ctx, symbol, C.Z3_mk_bool_sort(v.ctx))
    } else if typ == 0 {
        eprintln("This should never happen. (typ == 0)")
        return C.Z3_mk_const(v.ctx, symbol, C.Z3_mk_bool_sort(v.ctx))
    } else {
        type_name := v.table.sym(typ).name
        eprintln("unhandled variable type: ${type_name}")
        return C.Z3_mk_const(v.ctx, symbol, C.Z3_mk_uninterpreted_sort(v.ctx, C.Z3_mk_string_symbol(v.ctx, type_name.str)))
    }
}

fn (mut v Verifier) ensure(expr C.Z3_ast) bool {
    // It seems like solvers are single use.
    solver := C.Z3_mk_solver(v.ctx)
    C.Z3_solver_inc_ref(v.ctx, solver)

    if v.verbose {
        unsafe {
            eprintln("Attempting to ensure: ${tos_clone(C.Z3_ast_to_string(v.ctx, expr))}")
            eprintln("with facts: ${v.facts.map(tos_clone(C.Z3_ast_to_string(v.ctx, it))).join('; ')}")
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

pub fn (mut v Verifier) assign(target ast.Node, value ast.Expr) {
    if value is ast.ArrayInit {
        if (value.is_fixed && value.has_val) || (!value.is_fixed && value.exprs.len > 0) {
            name := get_name(target) or { return }
            v.facts << C.Z3_mk_eq(v.ctx, v.make_variable("${name}.len", ast.int_type_idx), C.Z3_mk_int64(v.ctx, value.exprs.len, C.Z3_mk_int_sort(v.ctx)))
        }
    }

    // TODO: Handle variables being changed.
    fact := C.Z3_mk_eq(v.ctx, v.visit(&target) or { return }, v.visit(value) or { return })
    v.facts << fact
}

pub fn (mut v Verifier) visit(node &ast.Node) ?C.Z3_ast {
    match node {
        ast.Expr {
            match node {
                ast.BoolLiteral {
                    return if node.val { C.Z3_mk_true(v.ctx) } else { C.Z3_mk_false(v.ctx) }
                }
                ast.CallExpr {
                    previous_facts_marker := v.facts.len

                    // Do not dive into builtin funcs for now.
                    if node.name != "println" {
                        if f := v.table.find_fn(node.name) {
                            if v.verbose {
                                eprintln("Going down function: ${f.name}")
                            }

                            prev_file_path := v.file_path
                            v.file_path = f.file

                            fn_decl := unsafe { &ast.FnDecl(f.source_fn) }
                            for i, param in fn_decl.params {
                                v.assign(param, node.args[i].expr)
                            }

                            for stmt in fn_decl.stmts {
                                v.visit(stmt)
                            }

                            v.file_path = prev_file_path
                        }
                    } else {
                        // Still visit the arguments though.
                        for arg in node.args {
                            v.visit(arg.expr) or { continue }
                        }
                    }

                    v.facts.trim(previous_facts_marker)
                }
                ast.CastExpr {
                    return v.visit(node.expr)
                }
                ast.Ident {
                    return v.make_variable(get_name(ast.Expr(node)) or { eprintln("unhandled name expr") return C.Z3_mk_true(v.ctx) }, node.info.typ)
                }
                ast.IfExpr {
                    // Else and other branches not handled yet.
                    // If is also being treated as a stmt rather than an
                    // expression. That makes things easier and less
                    // complicated for now.
                    previous_length := v.facts.len
                    if fact := v.visit(node.branches[0].cond) {
                        v.facts << fact
                    }
                    for stmt in node.branches[0].stmts {
                        v.visit(stmt) or { continue }
                    }
                    v.facts.trim(previous_length)
                }
                ast.IndexExpr {
                    left := get_name(node.left) or { v.error("could not get name of expression. (use temp?)", node.pos) return C.Z3_mk_true(v.ctx) }
                    var := v.make_variable("${left}.len", ast.int_type_idx)
                    if !v.ensure(C.Z3_mk_lt(v.ctx, v.visit(node.index)?, var)) {
                        v.error("cannot ensure array access is in bounds", node.left.pos().extend(node.pos))
                    }
                }
                ast.InfixExpr {
                    match node.op {
                        .eq {
                            return C.Z3_mk_eq(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .ne {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_distinct(v.ctx, 2, &args[0])
                        }
                        .gt {
                            return C.Z3_mk_gt(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .lt {
                            return C.Z3_mk_lt(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .ge {
                            return C.Z3_mk_ge(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .le {
                            return C.Z3_mk_le(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .and {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_and(v.ctx, 2, &args[0])
                        }
                        .logical_or {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_or(v.ctx, 2, &args[0])
                        }
                        .plus {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_add(v.ctx, 2, &args[0])
                        }
                        .mul {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_mul(v.ctx, 2, &args[0])
                        }
                        .minus {
                            args := [v.visit(node.left)?, v.visit(node.right)?]!
                            return C.Z3_mk_sub(v.ctx, 2, &args[0])
                        }
                        .div {
                            return C.Z3_mk_div(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .mod {
                            return C.Z3_mk_mod(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .xor {
                            return C.Z3_mk_bvxor(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .pipe {
                            return C.Z3_mk_bvor(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .amp {
                            return C.Z3_mk_bvand(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .left_shift {
                            return C.Z3_mk_bvshl(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .right_shift {
                            return C.Z3_mk_bvlshr(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
                        }
                        .unsigned_right_shift {
                            return C.Z3_mk_bvashr(v.ctx, v.visit(node.left)?, v.visit(node.right)?)
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
                            return C.Z3_mk_not(v.ctx, v.visit(node.right)?)
                        }
                        .bit_not {
                            return C.Z3_mk_bvnot(v.ctx, v.visit(node.right)?)
                        }
                        else {
                            eprintln("unhandled op in prefix expr: ${node.op}")
                        }
                    }
                }
                ast.SelectorExpr {
                    // FIXME: V bug. Using node.typ breaks the whole
                    // smartcasting.
                    mut node_ := node
                    // FIXME: V bug. node.typ can be 0 when node has a valid
                    // type.
                    if node_.typ == 0 && node.expr_type != 0 {
                        sym := v.table.sym(node.expr_type)
                        if sym.kind in [.array, .array_fixed] && node.field_name == "len" {
                            node_.typ = ast.int_type_idx
                        }
                    }
                    return v.make_variable(get_name(ast.Expr(node)) or { eprintln("unhandled name expr") return none }, node_.typ)
                }
                else {
                    eprintln("unhandled expr type: ${node.type_name()}")
                }
            }
        }
        ast.Stmt {
            match node {
                ast.AssertStmt {
                    expr := v.visit(node.expr)?

                    if !v.ensure(expr) {
                        v.error("failed to prove assertion", node.pos)
                    }
                }
                ast.AssignStmt {
                    for i in 0 .. node.left.len {
                        left := node.left[i]
                        right := node.right[i]

                        v.assign(left, right)
                    }
                }
                ast.ConstDecl {
                    for field in node.fields {
                        v.facts << C.Z3_mk_eq(v.ctx, v.make_variable(field.name, field.typ), v.visit(field.expr) or { continue })
                    }
                }
                ast.ExprStmt {
                    return v.visit(node.expr)
                }
                ast.FnDecl {
                    for stmt in node.stmts {
                        v.visit(stmt) or { continue }
                    }
                }
                ast.Return {
                    for expr in node.exprs {
                        v.visit(expr) or { continue }
                    }
                }
                ast.AsmStmt, ast.Module {}
                else {
                    eprintln("unhandled stmt type: ${node.type_name()}")
                }
            }
        }
        ast.Param {
            return v.make_variable(node.name, node.typ)
        }
        else {
            eprintln("unhandled node type: ${node.type_name()}")
        }
    }

    return none
}

