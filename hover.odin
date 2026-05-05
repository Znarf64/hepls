package hepls

import "core:fmt"
import "core:slice"

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
get_hovered_node_in_block :: proc(
	stmts:    []^ast.Stmt,
	location: hep.Location,
	completion := false,
) -> (node: ^ast.Node, scope: ^ast.Scope) {
	node = _hovered_node_in_block(stmts, location)

	for node != nil {
		if completion {
			#partial switch _ in node.derived {
			case ^ast.Stmt_Continue, ^ast.Stmt_Break, ^ast.Expr_Selector:
				return
			}
		}

		if s, n := hovered_child_node(node, location); n != node {
			if s != nil {
				scope = s
			}
			node = n
		} else {
			return
		}
	}

	return
}

@(require_results)
_hovered_node_in_block :: proc(stmts: []^ast.Stmt, location: hep.Location) -> ^ast.Node {
	index, ok := slice.binary_search_by(stmts, location, proc(node: ^ast.Stmt, location: hep.Location) -> slice.Ordering {
		if node.start.line > location.line {
			return .Greater
		}
		if node.end.line < location.line {
			return .Less
		}
		if node.start.line == location.line && node.start.column > location.column {
			return .Greater
		}
		if node.end.line == location.line && node.end.column < location.column {
			return .Less
		}
		return .Equal
	})
	if !ok {
		return nil
	}
	return stmts[index]
}

@(require_results)
hovered_field :: proc(field: ast.Field, location: hep.Location) -> ^ast.Node {
	if location_in_node(field.name, location) {
		return field.name
	}
	if location_in_node(field.type, location) {
		return field.type
	}
	if location_in_node(field.value, location) {
		return field.value
	}
	if location_in_node(field.location, location) {
		return field.location
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
hovered_child_node :: proc(node: ^ast.Node, location: hep.Location) -> (^ast.Scope, ^ast.Node) {
	if !location_in_node(node, location) {
		return nil, nil
	}

	switch v in node.derived {
	case ^ast.Expr_Constant, ^ast.Expr_Ident, ^ast.Expr_Interface, ^ast.Expr_Directive:
		return nil, node
	case ^ast.Expr_Binary:
		if location_in_node(v.lhs, location) {
			return nil, v.lhs
		}
		if location_in_node(v.rhs, location) {
			return nil, v.rhs
		}
	case ^ast.Expr_Proc_Lit:
		if h := hovered_proc_sig(v, location); h != nil {
			return nil, h
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			return v.scope, n
		}
	case ^ast.Expr_Proc_Sig:
		if h := hovered_proc_sig(v, location); h != nil {
			return nil, h
		}
	case ^ast.Expr_Proc_Group:
		for m in v.members {
			if location_in_node(m, location) {
				return nil, m
			}
		}
	case ^ast.Expr_Paren:
		if location_in_node(v.expr, location) {
			return nil, v.expr
		}
	case ^ast.Expr_Selector:
		if location_in_node(v.lhs, location) {
			return nil, v.lhs
		}
		if location_in_node(v.selector, location) {
			return nil, v.selector
		}
	case ^ast.Expr_Call:
		if location_in_node(v.lhs, location) {
			return nil, v.lhs
		}
		for value in v.args {
			if f := hovered_field(value, location); f != nil {
				return nil, f
			}
		}
	case ^ast.Expr_Compound:
		if location_in_node(v.type_expr, location) {
			return nil, v.type_expr
		}
		for value in v.fields {
			if f := hovered_field(value, location); f != nil {
				return nil, f
			}
		}
	case ^ast.Expr_Index:
		if location_in_node(v.lhs, location) {
			return nil, v.lhs
		}
		if location_in_node(v.rhs, location) {
			return nil, v.rhs
		}
	case ^ast.Expr_Cast:
		if location_in_node(v.value, location) {
			return nil, v.value
		}
		if location_in_node(v.type_expr, location) {
			return nil, v.type_expr
		}
	case ^ast.Expr_Unary:
		if location_in_node(v.expr, location) {
			return nil, v.expr
		}
	case ^ast.Expr_Ternary:
		if location_in_node(v.cond, location) {
			return nil, v.cond
		}
		if location_in_node(v.then_expr, location) {
			return nil, v.then_expr
		}
		if location_in_node(v.else_expr, location) {
			return nil, v.else_expr
		}
	case ^ast.Expr_Ellipsis:
		if location_in_node(v.expr, location) {
			return nil, v.expr
		}

	case ^ast.Type_Struct:
		for field in v.fields {
			if f := hovered_field(field, location); f != nil {
				return nil, f
			}
		}
	case ^ast.Type_Array:
		if location_in_node(v.count, location) {
			return nil, v.count
		}
		if location_in_node(v.elem, location) {
			return nil, v.elem
		}
	case ^ast.Type_Matrix:
		if location_in_node(v.rows, location) {
			return nil, v.rows
		}
		if location_in_node(v.cols, location) {
			return nil, v.cols
		}
		if location_in_node(v.elem, location) {
			return nil, v.elem
		}
	case ^ast.Type_Image:
		if location_in_node(v.dimensions, location) {
			return nil, v.dimensions
		}
		if location_in_node(v.texel_type, location) {
			return nil, v.texel_type
		}
	case ^ast.Type_Enum:
		for value in v.values {
			if f := hovered_field(value, location); f != nil {
				return nil, f
			}
		}
	case ^ast.Type_Bit_Set:
		if location_in_node(v.enum_type, location) {
			return nil, v.enum_type
		}
		if location_in_node(v.backing, location) {
			return nil, v.backing
		}

	case ^ast.Stmt_Return:
		for value in v.values {
			if location_in_node(value, location) {
				return nil, value
			}
		}
	case ^ast.Stmt_Break:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
	case ^ast.Stmt_Continue:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
	case ^ast.Stmt_For_Range:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
		if location_in_node(v.start_expr, location) {
			return v.init_scope, v.start_expr
		}
		if location_in_node(v.end_expr, location) {
			return v.init_scope, v.end_expr
		}
		if location_in_node(v.variable, location) {
			return v.init_scope, v.variable
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			return v.scope, n
		}
	case ^ast.Stmt_For:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
		if location_in_node(v.init, location) {
			return v.init_scope, v.init
		}
		if location_in_node(v.cond, location) {
			return v.init_scope, v.cond
		}
		if location_in_node(v.post, location) {
			return v.init_scope, v.post
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			return v.scope, n
		}
	case ^ast.Stmt_Block:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			return v.scope, n
		}
	case ^ast.Stmt_If:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
		if location_in_node(v.init, location) {
			return v.init_scope, v.init
		}
		if location_in_node(v.cond, location) {
			return v.init_scope, v.cond
		}
		if n := _hovered_node_in_block(v.then_block, location); n != nil {
			return v.then_scope, n
		}
		if n := _hovered_node_in_block(v.else_block, location); n != nil {
			return v.else_scope, n
		}
	case ^ast.Stmt_Switch:
		if location_in_node(v.label, location) {
			return nil, v.label
		}
		if location_in_node(v.init, location) {
			return v.scope, v.init
		}
		if location_in_node(v.cond, location) {
			return v.scope, v.cond
		}
		for c in v.cases {
			if location_in_node(c.value, location) {
				return c.scope, c.value
			}
			if n := _hovered_node_in_block(c.body, location); n != nil {
				return c.scope, n
			}
		}
	case ^ast.Stmt_Assign:
		for l in v.lhs {
			if location_in_node(l, location) {
				return nil, l
			}
		}

		for r in v.rhs {
			if location_in_node(r, location) {
				return nil, r
			}
		}
	case ^ast.Stmt_Expr:
		return nil, v.expr
	case ^ast.Stmt_When:
		if location_in_node(v.cond, location) {
			return nil, v.cond
		}
		n := _hovered_node_in_block(v.then_block, location)
		if n != nil {
			return nil, n
		}
		n = _hovered_node_in_block(v.else_block, location)
		if n != nil {
			return nil, n
		}

	case ^ast.Decl_Value:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return nil, f
			}
		}

		if location_in_node(v.type_expr, location) {
			return nil, v.type_expr
		}

		for l in v.lhs {
			if location_in_node(l, location) {
				return nil, l
			}
		}

		for v in v.values {
			if location_in_node(v, location) {
				return nil, v
			}
		}
	case ^ast.Decl_Import:
		if location_in_node(v.alias, location) {
			return nil, v.alias
		}
	}

	return nil, node
}

// may allocate using context.temp_allocator
@(require_results)
entity_detail_string :: proc(entity: ^ast.Entity, pretty: bool) -> string {
	#partial switch entity.kind {
	case .Library:
		return "library"
	case .Builtin:
		return "builtin"
	case .Label:
		return "label"
	case .Type:
		return "type"
	case:
		return types.to_string(entity.type, pretty, context.temp_allocator)
	}
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
		type_string = entity_detail_string(entity, true)
	} else if type != nil {
		type_string = types.to_string(type, true, context.temp_allocator)
	} else {
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
