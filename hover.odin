package hepls

import "core:fmt"

import "hephaistos/ast"
import "hephaistos/types"

@(require_results)
position_in_node :: proc(node: ^ast.Node, position: Position) -> bool {
	if node == nil {
		return false
	}

	if node.start.line > position.line {
		return false
	}
	if node.end.line < position.line {
		return false
	}
	if node.start.line == position.line && node.start.column > position.character {
		return false
	}
	if node.end.line == position.line && node.end.column <= position.character {
		return false
	}
	return true
}

@(require_results)
hovered_node_in_block :: proc(stmts: []^ast.Stmt, position: Position) -> ^ast.Node {
	for node in stmts {
		position_in_node(node, position) or_continue
		return hovered_sub_node(node, position)
	}

	return nil
}

@(require_results)
hovered_field :: proc(field: ast.Field, position: Position) -> ^ast.Node {
	if position_in_node(field.name, position) {
		return hovered_sub_node(field.name, position)
	}
	if position_in_node(field.type, position) {
		return hovered_sub_node(field.type, position)
	}
	if position_in_node(field.value, position) {
		return hovered_sub_node(field.value, position)
	}
	if position_in_node(field.location, position) {
		return hovered_sub_node(field.location, position)
	}

	return nil
}

@(require_results)
hovered_proc_sig :: proc(sig: ^ast.Expr_Proc_Sig, position: Position) -> ^ast.Node {
	for arg in sig.args {
		if f := hovered_field(arg, position); f != nil {
			return f
		}
	}
	for ret in sig.returns {
		if f := hovered_field(ret, position); f != nil {
			return f
		}
	}

	return nil
}

@(require_results)
hovered_sub_node :: proc(node: ^ast.Node, position: Position) -> ^ast.Node {
	if !position_in_node(node, position) {
		return nil
	}

	switch v in node.derived {
	case ^ast.Expr_Constant, ^ast.Expr_Ident, ^ast.Expr_Interface, ^ast.Expr_Directive:
		return node
	case ^ast.Expr_Binary:
		if position_in_node(v.lhs, position) {
			return hovered_sub_node(v.lhs, position)
		}
		if position_in_node(v.rhs, position) {
			return hovered_sub_node(v.rhs, position)
		}
	case ^ast.Expr_Proc_Lit:
		if h := hovered_proc_sig(v, position); h != nil {
			return h
		}
		if n := hovered_node_in_block(v.body, position); n != nil {
			return n
		}
	case ^ast.Expr_Proc_Sig:
		if h := hovered_proc_sig(v, position); h != nil {
			return h
		}
	case ^ast.Expr_Proc_Group:
		for m in v.members {
			if position_in_node(m, position) {
				return hovered_sub_node(m, position)
			}
		}
	case ^ast.Expr_Paren:
		if position_in_node(v.expr, position) {
			return hovered_sub_node(v.expr, position)
		}
	case ^ast.Expr_Selector:
		if position_in_node(v.lhs, position) {
			return hovered_sub_node(v.lhs, position)
		}
		if position_in_node(v.selector, position) {
			return hovered_sub_node(v.selector, position)
		}
	case ^ast.Expr_Call:
		if position_in_node(v.lhs, position) {
			return hovered_sub_node(v.lhs, position)
		}
		for value in v.args {
			if f := hovered_field(value, position); f != nil {
				return f
			}
		}
	case ^ast.Expr_Compound:
		if position_in_node(v.type_expr, position) {
			return hovered_sub_node(v.type_expr, position)
		}
		for value in v.fields {
			if f := hovered_field(value, position); f != nil {
				return f
			}
		}
	case ^ast.Expr_Index:
		if position_in_node(v.lhs, position) {
			return hovered_sub_node(v.lhs, position)
		}
		if position_in_node(v.rhs, position) {
			return hovered_sub_node(v.rhs, position)
		}
	case ^ast.Expr_Cast:
		if position_in_node(v.value, position) {
			return hovered_sub_node(v.value, position)
		}
		if position_in_node(v.type_expr, position) {
			return hovered_sub_node(v.type_expr, position)
		}
	case ^ast.Expr_Unary:
		if position_in_node(v.expr, position) {
			return hovered_sub_node(v.expr, position)
		}
	case ^ast.Expr_Ternary:
		if position_in_node(v.cond, position) {
			return hovered_sub_node(v.cond, position)
		}
		if position_in_node(v.then_expr, position) {
			return hovered_sub_node(v.then_expr, position)
		}
		if position_in_node(v.else_expr, position) {
			return hovered_sub_node(v.else_expr, position)
		}
	case ^ast.Expr_Ellipsis:
		if position_in_node(v.expr, position) {
			return hovered_sub_node(v.expr, position)
		}

	case ^ast.Type_Struct:
		for field in v.fields {
			if f := hovered_field(field, position); f != nil {
				return f
			}
		}
	case ^ast.Type_Array:
		if position_in_node(v.count, position) {
			return hovered_sub_node(v.count, position)
		}
		if position_in_node(v.elem, position) {
			return hovered_sub_node(v.elem, position)
		}
	case ^ast.Type_Matrix:
		if position_in_node(v.rows, position) {
			return hovered_sub_node(v.rows, position)
		}
		if position_in_node(v.cols, position) {
			return hovered_sub_node(v.cols, position)
		}
		if position_in_node(v.elem, position) {
			return hovered_sub_node(v.elem, position)
		}
	case ^ast.Type_Image:
		if position_in_node(v.dimensions, position) {
			return hovered_sub_node(v.dimensions, position)
		}
		if position_in_node(v.texel_type, position) {
			return hovered_sub_node(v.texel_type, position)
		}
	case ^ast.Type_Enum:
		for value in v.values {
			if f := hovered_field(value, position); f != nil {
				return f
			}
		}
	case ^ast.Type_Bit_Set:
		if position_in_node(v.enum_type, position) {
			return hovered_sub_node(v.enum_type, position)
		}
		if position_in_node(v.backing, position) {
			return hovered_sub_node(v.backing, position)
		}

	case ^ast.Stmt_Return:
		for value in v.values {
			if position_in_node(value, position) {
				return hovered_sub_node(value, position)
			}
		}
	case ^ast.Stmt_Break:
	case ^ast.Stmt_Continue:
	case ^ast.Stmt_For_Range:
		if position_in_node(v.start_expr, position) {
			return hovered_sub_node(v.start_expr, position)
		}
		if position_in_node(v.end_expr, position) {
			return hovered_sub_node(v.end_expr, position)
		}
		if position_in_node(v.variable, position) {
			return hovered_sub_node(v.variable, position)
		}
		if n := hovered_node_in_block(v.body, position); n != nil {
			return n
		}
	case ^ast.Stmt_For:
		if n := hovered_node_in_block(v.body, position); n != nil {
			return n
		}
	case ^ast.Stmt_Block:
		if n := hovered_node_in_block(v.body, position); n != nil {
			return n
		}
	case ^ast.Stmt_If:
		if n := hovered_node_in_block(v.then_block, position); n != nil {
			return n
		}
		if n := hovered_node_in_block(v.else_block, position); n != nil {
			return n
		}
	case ^ast.Stmt_Switch:
		// TODO
	case ^ast.Stmt_Assign:
		for l in v.lhs {
			if position_in_node(l, position) {
				return hovered_sub_node(l, position)
			}
		}

		for r in v.rhs {
			if position_in_node(r, position) {
				return hovered_sub_node(r, position)
			}
		}
	case ^ast.Stmt_Expr:
		return hovered_sub_node(v.expr, position)
	case ^ast.Stmt_When:
		n := hovered_node_in_block(v.then_block, position)
		if n != nil {
			return n
		}
		n = hovered_node_in_block(v.else_block, position)
		if n != nil {
			return n
		}

	case ^ast.Decl_Value:
		for a in v.attributes {
			if f := hovered_field(a, position); f != nil {
				return f
			}
		}

		if position_in_node(v.type_expr, position) {
			return hovered_sub_node(v.type_expr, position)
		}

		for l in v.lhs {
			if position_in_node(l, position) {
				return hovered_sub_node(l, position)
			}
		}

		for v in v.values {
			if position_in_node(v, position) {
				return hovered_sub_node(v, position)
			}
		}
	case ^ast.Decl_Import:
		if position_in_node(v.path, position) {
			return hovered_sub_node(v.path, position)
		}
		if position_in_node(v.alias, position) {
			return hovered_sub_node(v.alias, position)
		}
	}

	return node
}

@(require_results)
node_hover_text :: proc(node: ^ast.Node, allocator := context.temp_allocator) -> string {
	type:  ^types.Type
	value:  types.Const_Value
	prefix: string

	switch v in node.derived {
	case ^ast.Expr_Constant:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Binary:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Ident:
		prefix = fmt.tprintf("%s: ", v.text)
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Proc_Lit:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Proc_Sig:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Proc_Group:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Paren:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Selector:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Call:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Compound:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Index:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Cast:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Unary:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Interface:
		prefix = fmt.tprintf("$%s: ", v.ident.text)
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Directive:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Ternary:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Ellipsis:
		type   = v.type
		value  = v.const_value
	
	case ^ast.Type_Struct:
		type = v.type
	case ^ast.Type_Array:
		type = v.type
	case ^ast.Type_Matrix:
		type = v.type
	case ^ast.Type_Image:
		type = v.type
	case ^ast.Type_Enum:
		type = v.type
	case ^ast.Type_Bit_Set:
		type = v.type

	case ^ast.Stmt_Return:
	case ^ast.Stmt_Break:
	case ^ast.Stmt_Continue:
	case ^ast.Stmt_For_Range:
	case ^ast.Stmt_For:
	case ^ast.Stmt_Block:
	case ^ast.Stmt_If:
	case ^ast.Stmt_Switch:
	case ^ast.Stmt_Assign:
	case ^ast.Stmt_Expr:
	case ^ast.Stmt_When:

	case ^ast.Decl_Value:
	case ^ast.Decl_Import:
	}

	if type == nil {
		return ""
	}

	suffix: string
	if value != nil {
		suffix = fmt.tprintf(" (%v)", value)
	}
	type_string := types.to_string(type, context.temp_allocator)
	return fmt.aprint(
		"```odin\n",
		prefix,
		type_string,
		suffix,
		"\n```",
		sep       = "",
		allocator = allocator,
	)
}
