package hepls

import "core:fmt"

import hep "hephaistos"
import "hephaistos/ast"
import "hephaistos/types"

@(require_results)
location_in_node :: proc(node: ^ast.Node, location: hep.Location) -> bool {
	if node == nil {
		return false
	}

	if node.start.line > location.line {
		return false
	}
	if node.end.line < location.line {
		return false
	}
	if node.start.line == location.line && node.start.column > location.column {
		return false
	}
	if node.end.line == location.line && node.end.column < location.column {
		return false
	}
	return true
}

@(require_results)
hovered_node_in_block :: proc(stmts: []^ast.Stmt, location: hep.Location) -> ^ast.Node {
	for node in stmts {
		location_in_node(node, location) or_continue
		return hovered_sub_node(node, location)
	}

	return nil
}

@(require_results)
hovered_field :: proc(field: ast.Field, location: hep.Location) -> ^ast.Node {
	if location_in_node(field.name, location) {
		return hovered_sub_node(field.name, location)
	}
	if location_in_node(field.type, location) {
		return hovered_sub_node(field.type, location)
	}
	if location_in_node(field.value, location) {
		return hovered_sub_node(field.value, location)
	}
	if location_in_node(field.location, location) {
		return hovered_sub_node(field.location, location)
	}

	return nil
}

@(require_results)
hovered_proc_sig :: proc(sig: ^ast.Expr_Proc_Sig, location: hep.Location) -> ^ast.Node {
	for arg in sig.args {
		if f := hovered_field(arg, location); f != nil {
			return f
		}
	}
	for ret in sig.returns {
		if f := hovered_field(ret, location); f != nil {
			return f
		}
	}

	return nil
}

@(require_results)
hovered_sub_node :: proc(node: ^ast.Node, location: hep.Location) -> ^ast.Node {
	if !location_in_node(node, location) {
		return nil
	}

	switch v in node.derived {
	case ^ast.Expr_Constant, ^ast.Expr_Ident, ^ast.Expr_Interface, ^ast.Expr_Directive:
		return node
	case ^ast.Expr_Binary:
		if location_in_node(v.lhs, location) {
			return hovered_sub_node(v.lhs, location)
		}
		if location_in_node(v.rhs, location) {
			return hovered_sub_node(v.rhs, location)
		}
	case ^ast.Expr_Proc_Lit:
		if h := hovered_proc_sig(v, location); h != nil {
			return h
		}
		if n := hovered_node_in_block(v.body, location); n != nil {
			return n
		}
	case ^ast.Expr_Proc_Sig:
		if h := hovered_proc_sig(v, location); h != nil {
			return h
		}
	case ^ast.Expr_Proc_Group:
		for m in v.members {
			if location_in_node(m, location) {
				return hovered_sub_node(m, location)
			}
		}
	case ^ast.Expr_Paren:
		if location_in_node(v.expr, location) {
			return hovered_sub_node(v.expr, location)
		}
	case ^ast.Expr_Selector:
		if location_in_node(v.lhs, location) {
			return hovered_sub_node(v.lhs, location)
		}
		if location_in_node(v.selector, location) {
			return hovered_sub_node(v.selector, location)
		}
	case ^ast.Expr_Call:
		if location_in_node(v.lhs, location) {
			return hovered_sub_node(v.lhs, location)
		}
		for value in v.args {
			if f := hovered_field(value, location); f != nil {
				return f
			}
		}
	case ^ast.Expr_Compound:
		if location_in_node(v.type_expr, location) {
			return hovered_sub_node(v.type_expr, location)
		}
		for value in v.fields {
			if f := hovered_field(value, location); f != nil {
				return f
			}
		}
	case ^ast.Expr_Index:
		if location_in_node(v.lhs, location) {
			return hovered_sub_node(v.lhs, location)
		}
		if location_in_node(v.rhs, location) {
			return hovered_sub_node(v.rhs, location)
		}
	case ^ast.Expr_Cast:
		if location_in_node(v.value, location) {
			return hovered_sub_node(v.value, location)
		}
		if location_in_node(v.type_expr, location) {
			return hovered_sub_node(v.type_expr, location)
		}
	case ^ast.Expr_Unary:
		if location_in_node(v.expr, location) {
			return hovered_sub_node(v.expr, location)
		}
	case ^ast.Expr_Ternary:
		if location_in_node(v.cond, location) {
			return hovered_sub_node(v.cond, location)
		}
		if location_in_node(v.then_expr, location) {
			return hovered_sub_node(v.then_expr, location)
		}
		if location_in_node(v.else_expr, location) {
			return hovered_sub_node(v.else_expr, location)
		}
	case ^ast.Expr_Ellipsis:
		if location_in_node(v.expr, location) {
			return hovered_sub_node(v.expr, location)
		}

	case ^ast.Type_Struct:
		for field in v.fields {
			if f := hovered_field(field, location); f != nil {
				return f
			}
		}
	case ^ast.Type_Array:
		if location_in_node(v.count, location) {
			return hovered_sub_node(v.count, location)
		}
		if location_in_node(v.elem, location) {
			return hovered_sub_node(v.elem, location)
		}
	case ^ast.Type_Matrix:
		if location_in_node(v.rows, location) {
			return hovered_sub_node(v.rows, location)
		}
		if location_in_node(v.cols, location) {
			return hovered_sub_node(v.cols, location)
		}
		if location_in_node(v.elem, location) {
			return hovered_sub_node(v.elem, location)
		}
	case ^ast.Type_Image:
		if location_in_node(v.dimensions, location) {
			return hovered_sub_node(v.dimensions, location)
		}
		if location_in_node(v.texel_type, location) {
			return hovered_sub_node(v.texel_type, location)
		}
	case ^ast.Type_Enum:
		for value in v.values {
			if f := hovered_field(value, location); f != nil {
				return f
			}
		}
	case ^ast.Type_Bit_Set:
		if location_in_node(v.enum_type, location) {
			return hovered_sub_node(v.enum_type, location)
		}
		if location_in_node(v.backing, location) {
			return hovered_sub_node(v.backing, location)
		}

	case ^ast.Stmt_Return:
		for value in v.values {
			if location_in_node(value, location) {
				return hovered_sub_node(value, location)
			}
		}
	case ^ast.Stmt_Break:
	case ^ast.Stmt_Continue:
	case ^ast.Stmt_For_Range:
		if location_in_node(v.start_expr, location) {
			return hovered_sub_node(v.start_expr, location)
		}
		if location_in_node(v.end_expr, location) {
			return hovered_sub_node(v.end_expr, location)
		}
		if location_in_node(v.variable, location) {
			return hovered_sub_node(v.variable, location)
		}
		if n := hovered_node_in_block(v.body, location); n != nil {
			return n
		}
	case ^ast.Stmt_For:
		if location_in_node(v.init, location) {
			return hovered_sub_node(v.init, location)
		}
		if location_in_node(v.cond, location) {
			return hovered_sub_node(v.cond, location)
		}
		if location_in_node(v.post, location) {
			return hovered_sub_node(v.post, location)
		}
		if n := hovered_node_in_block(v.body, location); n != nil {
			return n
		}
	case ^ast.Stmt_Block:
		if n := hovered_node_in_block(v.body, location); n != nil {
			return n
		}
	case ^ast.Stmt_If:
		if location_in_node(v.init, location) {
			return hovered_sub_node(v.init, location)
		}
		if location_in_node(v.cond, location) {
			return hovered_sub_node(v.cond, location)
		}
		if n := hovered_node_in_block(v.then_block, location); n != nil {
			return n
		}
		if n := hovered_node_in_block(v.else_block, location); n != nil {
			return n
		}
	case ^ast.Stmt_Switch:
		if location_in_node(v.init, location) {
			return hovered_sub_node(v.init, location)
		}
		if location_in_node(v.cond, location) {
			return hovered_sub_node(v.cond, location)
		}
		for c in v.cases {
			if location_in_node(c.value, location) {
				return hovered_sub_node(c.value, location)
			}
			if n := hovered_node_in_block(c.body, location); n != nil {
				return n
			}
		}
	case ^ast.Stmt_Assign:
		for l in v.lhs {
			if location_in_node(l, location) {
				return hovered_sub_node(l, location)
			}
		}

		for r in v.rhs {
			if location_in_node(r, location) {
				return hovered_sub_node(r, location)
			}
		}
	case ^ast.Stmt_Expr:
		return hovered_sub_node(v.expr, location)
	case ^ast.Stmt_When:
		if location_in_node(v.cond, location) {
			return hovered_sub_node(v.cond, location)
		}
		n := hovered_node_in_block(v.then_block, location)
		if n != nil {
			return n
		}
		n = hovered_node_in_block(v.else_block, location)
		if n != nil {
			return n
		}

	case ^ast.Decl_Value:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.type_expr, location) {
			return hovered_sub_node(v.type_expr, location)
		}

		for l in v.lhs {
			if location_in_node(l, location) {
				return hovered_sub_node(l, location)
			}
		}

		for v in v.values {
			if location_in_node(v, location) {
				return hovered_sub_node(v, location)
			}
		}
	case ^ast.Decl_Import:
		if location_in_node(v.path, location) {
			return hovered_sub_node(v.path, location)
		}
		if location_in_node(v.alias, location) {
			return hovered_sub_node(v.alias, location)
		}
	}

	return node
}

@(require_results)
node_hover_text :: proc(node: ^ast.Node, allocator := context.temp_allocator) -> string {
	type:   ^types.Type
	value:   types.Const_Value
	prefix:  string
	entity: ^ast.Entity

	switch v in node.derived {
	case ^ast.Expr_Constant:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Binary:
		type   = v.type
		value  = v.const_value
	case ^ast.Expr_Ident:
		prefix = fmt.tprintf("%s: ", v.text)
		entity = v.entity
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
		entity = v.entity
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

	type_string: string
	if entity != nil {
		#partial switch entity.kind {
		case .Library:
			type_string = "library"
		case .Builtin:
			type_string = "builtin"
		case .Label:
			type_string = "label"
		case .Type:
			type_string = "type"
		case:
			type_string = types.to_string(type, context.temp_allocator)
		}
	} else if type != nil {
		type_string = types.to_string(type, context.temp_allocator)
	}

	if type_string == "" {
		return ""
	}

	suffix: string
	if value != nil {
		if str, ok := value.(string); ok {
			type_string = "string"
			suffix      = fmt.tprintf(` ("%s")`, str)
		} else {
			suffix = fmt.tprintf(" (%v)", value)
		}
	}

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

@(require_results)
node_definition :: proc(node: ^ast.Node) -> ^ast.Node {
	#partial switch v in node.derived {
	case ^ast.Expr_Ident:
		e := v.entity
		if e == nil {
			return nil
		}
		return e.ident
	}

	return nil
}

