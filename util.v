import os
import v.ast

fn find_vlib() string {
    v_path := os.find_abs_path_of_executable("v") or { panic("cannot locate v executable in system path") }
    return "${os.dir(v_path)}/vlib"
}

fn get_name(expr ast.Expr) ?string {
    match expr {
        ast.Ident {
            return expr.name
        }
        ast.SelectorExpr {
            left := get_name(expr.expr) or { return none }
            return "${left}.${expr.field_name}"
        }
        else {
            return none
        }
    }
}
