module main

#flag -I/nix/store/y2zscf605s507cqv0241i9zzqbgxnh7g-z3-4.8.15-dev/include
#flag -L/nix/store/q5wd1fbwbyq0b5hx2ayxmhzw3dn1y8r9-z3-4.8.15-lib/lib

#flag -lz3

#include <z3.h>

[typedef]
struct C.Z3_config {}
[typedef]
struct C.Z3_context {}
[typedef]
struct C.Z3_solver {}
[typedef]
struct C.Z3_ast {}
[typedef]
struct C.Z3_sort {}
[typedef]
struct C.Z3_symbol {}


fn C.Z3_mk_config() C.Z3_config
fn C.Z3_del_config(config C.Z3_config)


fn C.Z3_mk_context(config C.Z3_config) C.Z3_context
fn C.Z3_del_context(c C.Z3_context)


fn C.Z3_ast_to_string(c C.Z3_context, a C.Z3_ast) &u8


fn C.Z3_mk_solver(c C.Z3_context) C.Z3_solver
fn C.Z3_solver_inc_ref(c C.Z3_context, s C.Z3_solver)
fn C.Z3_solver_dec_ref(c C.Z3_context, s C.Z3_solver)

fn C.Z3_solver_check(c C.Z3_context, s C.Z3_solver) i32
fn C.Z3_solver_pop(c C.Z3_context, s C.Z3_solver, n u32)
fn C.Z3_solver_push(c C.Z3_context, s C.Z3_solver)

fn C.Z3_solver_assert(c C.Z3_context, s C.Z3_solver, a C.Z3_ast)


fn C.Z3_mk_int_sort(c C.Z3_context) C.Z3_sort

fn C.Z3_mk_true(c C.Z3_context) C.Z3_ast
fn C.Z3_mk_false(c C.Z3_context) C.Z3_ast
fn C.Z3_mk_eq(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_distinct(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_lt(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_le(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_gt(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_ge(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_and(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_or(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_not(c C.Z3_context, a C.Z3_ast) C.Z3_ast
fn C.Z3_mk_add(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_mul(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_sub(c C.Z3_context, n u32, a &C.Z3_ast) C.Z3_ast
fn C.Z3_mk_unary_minus(c C.Z3_context, a C.Z3_ast) C.Z3_ast
fn C.Z3_mk_div(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_mod(c C.Z3_context, l C.Z3_ast, r C.Z3_ast) C.Z3_ast
fn C.Z3_mk_int64(c C.Z3_context, n i64, s C.Z3_sort) C.Z3_ast

fn C.Z3_mk_string_symbol(c C.Z3_context, s &u8) C.Z3_symbol
fn C.Z3_mk_const(c C.Z3_context, s C.Z3_symbol, s C.Z3_sort) C.Z3_ast
