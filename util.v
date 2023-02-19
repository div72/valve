import v.ast

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
