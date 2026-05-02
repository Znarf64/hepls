package hepls

import vmem "core:mem/virtual"

import hep "hephaistos"
import ast "hephaistos/ast"

Ast :: struct {
	stmts: []^hep.Ast_Stmt,
	arena: vmem.Arena,
}

Ast_Iterator :: struct {
	stack: [dynamic]^hep.Ast_Node,
}

@(require_results)
ast_iterator_make :: proc(ast: []^hep.Ast_Stmt, allocator := context.temp_allocator) -> (iter: Ast_Iterator) {
	iter.stack = make([dynamic]^hep.Ast_Node, 0, len(ast), allocator)
	#reverse for node in ast {
		append(&iter.stack, node)
	}
	return
}

@(require_results)
ast_iterator :: proc(iter: ^Ast_Iterator) -> (node: ^hep.Ast_Node, cond: bool) {
	for node == nil {
		node = pop_safe(&iter.stack) or_return
	}

	switch v in node.derived {
	case ^ast.Expr_Constant, ^ast.Expr_Ident, ^ast.Expr_Interface, ^ast.Expr_Directive:
	case ^ast.Expr_Binary:
		append(&iter.stack, v.lhs)
		append(&iter.stack, v.rhs)
	case ^ast.Expr_Proc_Lit:
		for arg in v.args {
			append(&iter.stack, arg.name)
			append(&iter.stack, arg.type)
			append(&iter.stack, arg.value)
			append(&iter.stack, arg.location)
		}
		for ret in v.returns {
			append(&iter.stack, ret.name)
			append(&iter.stack, ret.type)
			append(&iter.stack, ret.value)
			append(&iter.stack, ret.location)
		}
		for node in v.body {
			append(&iter.stack, node)
		}
	case ^ast.Expr_Proc_Sig:
		for arg in v.args {
			append(&iter.stack, arg.name)
			append(&iter.stack, arg.type)
			append(&iter.stack, arg.value)
			append(&iter.stack, arg.location)
		}
		for ret in v.returns {
			append(&iter.stack, ret.name)
			append(&iter.stack, ret.type)
			append(&iter.stack, ret.value)
			append(&iter.stack, ret.location)
		}
	case ^ast.Expr_Proc_Group:
		for m in v.members {
			append(&iter.stack, m)
		}
	case ^ast.Expr_Paren:
		append(&iter.stack, v.expr)
	case ^ast.Expr_Selector:
		append(&iter.stack, v.lhs)
		append(&iter.stack, v.selector)
	case ^ast.Expr_Call:
		append(&iter.stack, v.lhs)
		for arg in v.args {
			append(&iter.stack, arg.name)
			append(&iter.stack, arg.type)
			append(&iter.stack, arg.value)
			append(&iter.stack, arg.location)
		}
	case ^ast.Expr_Compound:
		append(&iter.stack, v.type_expr)
		for value in v.fields {
			append(&iter.stack, value.name)
			append(&iter.stack, value.type)
			append(&iter.stack, value.value)
			append(&iter.stack, value.location)
		}
	case ^ast.Expr_Index:
		append(&iter.stack, v.lhs)
		append(&iter.stack, v.rhs)
	case ^ast.Expr_Cast:
		append(&iter.stack, v.value)
		append(&iter.stack, v.type_expr)
	case ^ast.Expr_Unary:
		append(&iter.stack, v.expr)
	case ^ast.Expr_Ternary:
		append(&iter.stack, v.cond)
		append(&iter.stack, v.then_expr)
		append(&iter.stack, v.else_expr)
	case ^ast.Expr_Ellipsis:
		append(&iter.stack, v.expr)

	case ^ast.Type_Struct:
		for field in v.fields {
			append(&iter.stack, field.name)
			append(&iter.stack, field.type)
			append(&iter.stack, field.value)
			append(&iter.stack, field.location)
		}
	case ^ast.Type_Array:
		append(&iter.stack, v.count)
		append(&iter.stack, v.elem)
	case ^ast.Type_Matrix:
		append(&iter.stack, v.rows)
		append(&iter.stack, v.cols)
		append(&iter.stack, v.elem)
	case ^ast.Type_Image:
		append(&iter.stack, v.dimensions)
		append(&iter.stack, v.texel_type)
	case ^ast.Type_Enum:
		for field in v.values {
			append(&iter.stack, field.name)
			append(&iter.stack, field.type)
			append(&iter.stack, field.value)
			append(&iter.stack, field.location)
		}
	case ^ast.Type_Bit_Set:
		append(&iter.stack, v.enum_type)
		append(&iter.stack, v.backing)

	case ^ast.Stmt_Return:
		for value in v.values {
			append(&iter.stack, value)
		}
	case ^ast.Stmt_Break:
	case ^ast.Stmt_Continue:
	case ^ast.Stmt_For_Range:
		append(&iter.stack, v.start_expr)
		append(&iter.stack, v.end_expr)
		append(&iter.stack, v.variable)
		for node in v.body {
			append(&iter.stack, node)
		}
	case ^ast.Stmt_For:
		append(&iter.stack, v.init)
		append(&iter.stack, v.cond)
		append(&iter.stack, v.post)
		for node in v.body {
			append(&iter.stack, node)
		}
	case ^ast.Stmt_Block:
		for node in v.body {
			append(&iter.stack, node)
		}
	case ^ast.Stmt_If:
		append(&iter.stack, v.init)
		append(&iter.stack, v.cond)
		for node in v.then_block {
			append(&iter.stack, node)
		}
		for node in v.else_block {
			append(&iter.stack, node)
		}
	case ^ast.Stmt_Switch:
		append(&iter.stack, v.init)
		append(&iter.stack, v.cond)
		for c in v.cases {
			append(&iter.stack, c.value)
			for node in c.body {
				append(&iter.stack, node)
			}
		}
	case ^ast.Stmt_Assign:
		for l in v.lhs {
			append(&iter.stack, l)
		}

		for r in v.rhs {
			append(&iter.stack, r)
		}
	case ^ast.Stmt_Expr:
		append(&iter.stack, v.expr)
	case ^ast.Stmt_When:
		append(&iter.stack, v.cond)
		for node in v.then_block {
			append(&iter.stack, node)
		}
		for node in v.else_block {
			append(&iter.stack, node)
		}

	case ^ast.Decl_Value:
		for a in v.attributes {
			append(&iter.stack, a.name)
			append(&iter.stack, a.type)
			append(&iter.stack, a.value)
			append(&iter.stack, a.location)
		}

		append(&iter.stack, v.type_expr)

		for l in v.lhs {
			append(&iter.stack, l)
		}

		for v in v.values {
			append(&iter.stack, v)
		}
	case ^ast.Decl_Import:
		append(&iter.stack, v.path)
		append(&iter.stack, v.alias)
	}

	cond = true
	return
}

@(require_results)
get_node_entity :: proc(node: ^ast.Node) -> (entity: ^ast.Entity) {
	#partial switch v in node.derived {
	case ^ast.Expr_Ident:
		return v.entity
	}
	return
}

@(require_results)
get_node_definition :: proc(node: ^ast.Node) -> (library: string, definition: ^ast.Node) {
	e := get_node_entity(node)
	if e == nil {
		return
	}
	library    = e.library
	definition = e.ident
	if e.ident == nil {
		definition = e.decl
	}
	return
}
