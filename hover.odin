package hepls

import "base:runtime"

import "core:fmt"
import "core:slice"
import "core:strings"

import hep "hephaistos"

@(require_results)
location_in_node :: proc(node: ^hep.Ast_Node, location: hep.Location) -> bool {
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

Hover_Context :: struct {
	procedure:   ^hep.Expr_Proc_Lit,
	scope:       ^hep.Scope,
	shader_stage: hep.Shader_Stage,
	arg_index:    int, // Index of relevant field for compound, call and return
	node:         union {
		^hep.Expr_Call,
		^hep.Expr_Compound,

		^hep.Stmt_Return,
		^hep.Stmt_Break,
		^hep.Stmt_Continue,

		^hep.Decl_Import,
	},
}

@(require_results)
get_hover_context :: proc(
	stmts:    []^hep.Ast_Stmt,
	location: hep.Location,
) -> (node: ^hep.Ast_Node, ctx: Hover_Context) {
	node = _hovered_node_in_block(stmts, location)

	for node != nil {
		#partial switch v in node.derived {
		case ^hep.Decl_Value:
			if v.shader_stage != nil {
				ctx.shader_stage = v.shader_stage
			}
		case ^hep.Expr_Proc_Lit:
			ctx.procedure = v
		case ^hep.Expr_Compound:
			ctx.node = v
		case ^hep.Stmt_Return:
			ctx.node = v
		case ^hep.Stmt_Break:
			ctx.node = v
		case ^hep.Stmt_Continue:
			ctx.node = v
		case ^hep.Expr_Call:
			ctx.node = v
		case ^hep.Decl_Import:
			ctx.node = v
		}

		if child := hovered_child_node(node, location, &ctx); child != node {
			node = child
		} else {
			return
		}
	}

	return
}

@(require_results)
_hovered_node_in_block :: proc(stmts: []^hep.Ast_Stmt, location: hep.Location) -> ^hep.Ast_Node {
	index, ok := slice.binary_search_by(stmts, location, proc(node: ^hep.Ast_Stmt, location: hep.Location) -> slice.Ordering {
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
hovered_field :: proc(field: hep.Ast_Field, location: hep.Location) -> ^hep.Ast_Node {
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
hovered_proc_sig :: proc(sig: ^hep.Expr_Proc_Sig, location: hep.Location) -> ^hep.Ast_Node {
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
hovered_child_node :: proc(node: ^hep.Ast_Node, location: hep.Location, ctx: ^Hover_Context) -> ^hep.Ast_Node {
	if !location_in_node(node, location) {
		return nil
	}

	@(require_results)
	value_count :: proc(t: ^hep.Type) -> int {
		if t == nil || t.kind != .Tuple {
			return 1
		}
		return len(t.variant.(^hep.Type_Struct).fields)
	}

	switch v in node.derived {
	case ^hep.Expr_Constant, ^hep.Expr_Ident, ^hep.Expr_Interface, ^hep.Expr_Directive:
		return node
	case ^hep.Expr_Binary:
		if location_in_node(v.lhs, location) {
			return v.lhs
		}
		if location_in_node(v.rhs, location) {
			return v.rhs
		}
	case ^hep.Expr_Proc_Lit:
		if h := hovered_proc_sig(v, location); h != nil {
			return h
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			ctx.scope = v.scope
			return n
		}
	case ^hep.Expr_Proc_Sig:
		if h := hovered_proc_sig(v, location); h != nil {
			return h
		}
	case ^hep.Expr_Proc_Group:
		for m in v.members {
			if location_in_node(m, location) {
				return m
			}
		}
	case ^hep.Expr_Paren:
		if location_in_node(v.expr, location) {
			return v.expr
		}
	case ^hep.Expr_Selector:
		if location_in_node(v.lhs, location) {
			return v.lhs
		}
		if location_in_node(v.selector, location) {
			if ident, ok := v.lhs.derived.(^hep.Expr_Ident); ok {
				if ident.entity != nil && ident.entity.kind == .Library {
					ctx.scope = ident.entity.library.scope
				}
			}

			if v.lhs.type != nil {
				type := hep.base_type(v.lhs.type)
				#partial switch v in type.variant {
				case ^hep.Type_Struct:
					ctx.scope = v.scope
				case ^hep.Type_Enum:
					ctx.scope = v.scope
				}
			}

			return v.selector
		}
	case ^hep.Expr_Call:
		if location_in_node(v.lhs, location) {
			return v.lhs
		}

		arg_index: int
		defer ctx.arg_index = arg_index
		for value in v.args {
			if f := hovered_field(value, location); f != nil {
				return f
			}

			arg_index += value_count(value.value.type)
		}
	case ^hep.Expr_Compound:
		if location_in_node(v.type_expr, location) {
			return v.type_expr
		}

		arg_index: int
		defer ctx.arg_index = arg_index
		for value in v.fields {
			if f := hovered_field(value, location); f != nil {
				if value.name != nil {
					arg_index = value.member_index
				}
				return f
			}

			arg_index += value_count(value.value.type)
		}
	case ^hep.Expr_Index:
		if location_in_node(v.lhs, location) {
			return v.lhs
		}
		if location_in_node(v.rhs, location) {
			return v.rhs
		}
	case ^hep.Expr_Cast:
		if location_in_node(v.value, location) {
			return v.value
		}
		if location_in_node(v.type_expr, location) {
			return v.type_expr
		}
	case ^hep.Expr_Unary:
		if location_in_node(v.expr, location) {
			return v.expr
		}
	case ^hep.Expr_Ternary:
		if location_in_node(v.cond, location) {
			return v.cond
		}
		if location_in_node(v.then_expr, location) {
			return v.then_expr
		}
		if location_in_node(v.else_expr, location) {
			return v.else_expr
		}
	case ^hep.Expr_Ellipsis:
		if location_in_node(v.expr, location) {
			return v.expr
		}

	case ^hep.Expr_Type_Struct:
		for field in v.fields {
			if f := hovered_field(field, location); f != nil {
				return f
			}
		}
	case ^hep.Expr_Type_Array:
		if location_in_node(v.count, location) {
			return v.count
		}
		if location_in_node(v.elem, location) {
			return v.elem
		}
	case ^hep.Expr_Type_Matrix:
		if location_in_node(v.rows, location) {
			return v.rows
		}
		if location_in_node(v.cols, location) {
			return v.cols
		}
		if location_in_node(v.elem, location) {
			return v.elem
		}
	case ^hep.Expr_Type_Image:
		if location_in_node(v.dimensions, location) {
			return v.dimensions
		}
		if location_in_node(v.texel_type, location) {
			return v.texel_type
		}
	case ^hep.Expr_Type_Enum:
		for value in v.values {
			if f := hovered_field(value, location); f != nil {
				return f
			}
		}
	case ^hep.Expr_Type_Bit_Set:
		if location_in_node(v.enum_type, location) {
			return v.enum_type
		}
		if location_in_node(v.backing, location) {
			return v.backing
		}
	case ^hep.Expr_Type_Opaque:
		if location_in_node(v.name, location) {
			return v.name
		}
		if location_in_node(v.backing, location) {
			return v.backing
		}
	case ^hep.Expr_Type_Distinct:
		if location_in_node(v.backing, location) {
			return v.backing
		}
	case ^hep.Expr_Type_Fixed:
		return nil

	case ^hep.Stmt_Return:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		arg_index: int
		defer ctx.arg_index = arg_index
		for value in v.values {
			if location_in_node(value, location) {
				return value
			}

			arg_index += value_count(value.type)
		}
	case ^hep.Stmt_Break:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
	case ^hep.Stmt_Continue:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
	case ^hep.Stmt_For_Range:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
		if location_in_node(v.start_expr, location) {
			ctx.scope = v.init_scope
			return v.start_expr
		}
		if location_in_node(v.end_expr, location) {
			ctx.scope = v.init_scope
			return v.end_expr
		}
		if location_in_node(v.variable, location) {
			ctx.scope = v.init_scope
			return v.variable
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			ctx.scope = v.scope
			return n
		}
	case ^hep.Stmt_For:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
		if location_in_node(v.init, location) {
			ctx.scope = v.init_scope
			return v.init
		}
		if location_in_node(v.cond, location) {
			ctx.scope = v.init_scope
			return v.cond
		}
		if location_in_node(v.post, location) {
			ctx.scope = v.init_scope
			return v.post
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			ctx.scope = v.scope
			return n
		}
	case ^hep.Stmt_Block:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
		if n := _hovered_node_in_block(v.body, location); n != nil {
			ctx.scope = v.scope
			return n
		}
	case ^hep.Stmt_If:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
		if location_in_node(v.init, location) {
			ctx.scope = v.init_scope
			return v.init
		}
		if location_in_node(v.cond, location) {
			ctx.scope = v.init_scope
			return v.cond
		}
		if n := _hovered_node_in_block(v.then_block, location); n != nil {
			ctx.scope = v.then_scope
			return n
		}
		if n := _hovered_node_in_block(v.else_block, location); n != nil {
			ctx.scope = v.else_scope
			return n
		}
	case ^hep.Stmt_Switch:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.label, location) {
			return v.label
		}
		if location_in_node(v.init, location) {
			ctx.scope = v.scope
			return v.init
		}
		if location_in_node(v.cond, location) {
			ctx.scope = v.scope
			return v.cond
		}
		for c in v.cases {
			if location_in_node(c.value, location) {
				ctx.scope = c.scope
				return c.value
			}
			if n := _hovered_node_in_block(c.body, location); n != nil {
				ctx.scope = c.scope
				return n
			}
		}
	case ^hep.Stmt_Assign:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		for l in v.lhs {
			if location_in_node(l, location) {
				return l
			}
		}

		for r in v.rhs {
			if location_in_node(r, location) {
				return r
			}
		}
	case ^hep.Stmt_Expr:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		return v.expr
	case ^hep.Stmt_When:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.cond, location) {
			return v.cond
		}
		n := _hovered_node_in_block(v.then_block, location)
		if n != nil {
			return n
		}
		n = _hovered_node_in_block(v.else_block, location)
		if n != nil {
			return n
		}

	case ^hep.Decl_Value:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.type_expr, location) {
			return v.type_expr
		}

		for l in v.lhs {
			if location_in_node(l, location) {
				return l
			}
		}

		for v in v.values {
			if location_in_node(v, location) {
				return v
			}
		}
	case ^hep.Decl_Import:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.alias, location) {
			return v.alias
		}
	case ^hep.Decl_Extension:
		for a in v.attributes {
			if f := hovered_field(a, location); f != nil {
				return f
			}
		}

		if location_in_node(v.extension, location) {
			return v.extension
		}
		n := _hovered_node_in_block(v.body, location)
		if n != nil {
			return n
		}
	}

	return node
}

// may allocate using context.temp_allocator
@(require_results)
entity_detail_string :: proc(entity: ^hep.Entity, pretty: bool) -> string {
	#partial switch entity.kind {
	case .Library:
		return "library"
	case .Builtin:
		return builtin_signatures[entity.builtin_id].text
	case .Label:
		return "label"
	case .Type:
		return hep.type_to_string(hep.base_type(entity.type), pretty, context.temp_allocator)
	case:
		return hep.type_to_string(entity.type, pretty, context.temp_allocator)
	}
}

@(require_results)
node_hover_text :: proc(node: ^hep.Ast_Node, allocator: runtime.Allocator, ctx: Maybe(Hover_Context) = nil) -> string {
	type:   ^hep.Type
	value:   hep.Const_Value
	entity: ^hep.Entity
	usage:   hep.Interface_Usage

	if ctx, ok := ctx.?; ok {
		if import_, ok := ctx.node.(^hep.Decl_Import); ok {
			return fmt.aprintf(`%s: library ("%v")`, import_.entity.name, import_.path.value.(string) or_else "", allocator = allocator)
		}
	}

	b := strings.builder_make(allocator)

	switch v in node.derived {
	case ^hep.Expr_Constant:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Binary:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Ident:
		entity = v.entity
		type   = v.type
		value  = v.const_value

		ab := strings.builder_make(context.temp_allocator)

		find_decl: if entity != nil && entity.decl != nil {
			decl := entity.decl.derived.(^hep.Decl_Value) or_break find_decl

			if decl.interface != nil {
				fmt.sbprintf(&ab, "@(%v", hep.interface_kind_names[decl.interface])
			}

			if decl.descriptor_set != -1 {
				fmt.sbprint(&ab, ", descriptor_set =", decl.descriptor_set)
			}

			if decl.binding != -1 {
				fmt.sbprint(&ab, ", binding =", decl.binding)
			}

			if decl.location != -1 {
				fmt.sbprint(&ab, ", location =", decl.location)
			}

			if decl.shader_stage != nil {
				fmt.sbprintf(&ab, "@(%v", hep.shader_stage_names[decl.shader_stage])
			}

			if strings.builder_len(ab) != 0 {
				fmt.sbprintln(&ab, ")")
				strings.write_string(&b, strings.to_string(ab))
			}
		}

		if strings.builder_len(ab) == 0 {
			if entity != nil && entity.location != -1 {
				#partial switch entity.kind {
				case .Proc_Param:
					fmt.sbprintfln(&ab, "@(input, location = %d)", entity.location)
				case .Proc_Return:
					fmt.sbprintfln(&ab, "@(output, location = %d)", entity.location)
				}
				strings.write_string(&b, strings.to_string(ab))
			}
		}

		fmt.sbprint(&b, v.text)

		if v.entity != nil && v.entity.kind == .Type {
			fmt.sbprint(&b, " :: ")
		} else {
			fmt.sbprint(&b, ": ")
		}
	case ^hep.Expr_Proc_Lit:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Proc_Sig:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Proc_Group:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Paren:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Selector:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Call:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Compound:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Index:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Cast:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Unary:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Interface:
		shader_stage: hep.Shader_Stage
		if ctx, ok := ctx.?; ok {
			shader_stage = ctx.shader_stage
		}
		fmt.sbprintf(&b, "$%s: ", v.ident.text)
		usage  = hep.interface_infos[v.ident.text].usage[shader_stage]
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Directive:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Ternary:
		type   = v.type
		value  = v.const_value
	case ^hep.Expr_Ellipsis:
		type   = v.type
		value  = v.const_value

	case ^hep.Expr_Type_Struct:
		if v.type.kind == .Named {
			named := v.type.variant.(^hep.Type_Named)
			type   = named.type
			fmt.sbprint(&b, named.name, ":: ")
		} else {
			type = v.type
		}
	case ^hep.Expr_Type_Enum:
		if v.type.kind == .Named {
			named := v.type.variant.(^hep.Type_Named)
			type   = named.type
			fmt.sbprint(&b, named.name, ":: ")
		} else {
			type = v.type
		}
	case ^hep.Expr_Type_Array:
		type = v.type
	case ^hep.Expr_Type_Matrix:
		type = v.type
	case ^hep.Expr_Type_Image:
		type = v.type
	case ^hep.Expr_Type_Bit_Set:
		type = v.type
	case ^hep.Expr_Type_Opaque:
		type = v.type
	case ^hep.Expr_Type_Distinct:
		type = v.type
	case ^hep.Expr_Type_Fixed:
		type = v.type

	case ^hep.Stmt_Return:
	case ^hep.Stmt_Break:
	case ^hep.Stmt_Continue:
	case ^hep.Stmt_For_Range:
	case ^hep.Stmt_For:
	case ^hep.Stmt_Block:
	case ^hep.Stmt_If:
	case ^hep.Stmt_Switch:
	case ^hep.Stmt_Assign:
	case ^hep.Stmt_Expr:
	case ^hep.Stmt_When:

	case ^hep.Decl_Value:
	case ^hep.Decl_Import:
		return fmt.aprintf(`"%s"`, v.path.value.(string), allocator = allocator)

	case ^hep.Decl_Extension:
	}

	if value == nil && entity != nil {
		value = entity.value
	}

	if entity != nil {
		strings.write_string(&b, entity_detail_string(entity, true))
	} else if type != nil {
		if str, ok := value.(string); ok && type.kind == .Invalid {
			strings.write_string(&b, fmt.tprintf(`string`))
		} else {
			strings.write_string(&b, hep.type_to_string(type, true, context.temp_allocator))
		}
	} else {
		strings.builder_destroy(&b)
		return ""
	}

	if value != nil {
		if str, ok := value.(string); ok {
			strings.write_string(&b, fmt.tprintf(` ("%s")`, str))
		} else {
			strings.write_string(&b, fmt.tprintf(" (%v)", value))
		}
	} else if usage != nil {
		switch usage {
		case .In:
			strings.write_string(&b, " (input)")
		case .Out:
			strings.write_string(&b, " (output)")
		}
	}

	return strings.to_string(b)
}
