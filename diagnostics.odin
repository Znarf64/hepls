package hepls

import vmem "core:mem/virtual"

import hep "hephaistos"
import ast "hephaistos/ast"

@(require_results)
check_file :: proc(state: ^State, source: string, uri: Uri) -> (error: Error) {
	errors, code := check_file_internal(state, source, context.temp_allocator)

	diagnostics := make([]Diagnostic, len(errors), context.temp_allocator)
	for &diagnostic, i in diagnostics {
		error := errors[i]

		diagnostic = {
			range    = {
				start = { line = error.line - 1,     character = error.column - 1,     },
				end   = { line = error.end.line - 1, character = error.end.column - 1, },
			},
			message  = error.message,
			severity = .Error,
			code     = code,
		}
	}

	response_notification := Notification(Publish_Diagnositics_Params) {
		method = "textDocument/publishDiagnostics",
		params = {
			uri         = uri,
			diagnostics = diagnostics,
		},
	}
	return send_message(response_notification)
}

@(require_results)
check_file_internal :: proc(state: ^State, source: string, error_allocator := context.allocator) -> (errors: []hep.Error, code: string) {
	vmem.arena_free_all(&state.ast_arena)
	state.ast = {}

	ast_allocator := vmem.arena_allocator(&state.ast_arena)

	tokens: []hep.Token
	tokens, errors = hep.tokenize(source, false, allocator = ast_allocator, error_allocator = error_allocator)
	if len(errors) != 0 {
		code = "syntax"
		return
	}

	state.ast, errors = hep.parse(tokens, allocator = ast_allocator, error_allocator = error_allocator)
	if len(errors) != 0 {
		code = "syntax"
		return
	}

	checker: hep.Checker
	checker, errors = hep.check(
		state.ast,
		defines         = {},
		types           = {},
		libraries       = {},
		flags           = {},
		allocator       = ast_allocator,
		error_allocator = error_allocator,
	)
	if len(errors) != 0 {
		code = "checker"
		return
	}

	return
}

@(require_results)
position_in_node :: proc(node: ^ast.Node, position: Position) -> bool {
	if node.start.line > position.line {
		return false
	}
	if node.end.line < position.line {
		return false
	}
	if node.start.line == position.line && node.start.column > position.character {
		return false
	}
	if node.end.line == position.line && node.end.column < position.character {
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
hovered_sub_node :: proc(node: ^ast.Node, position: Position) -> ^ast.Node {
	assert(position_in_node(node, position))

	switch v in node.derived {
	case ^ast.Expr_Constant:
	case ^ast.Expr_Binary:
	case ^ast.Expr_Ident:
	case ^ast.Expr_Proc_Lit:
	case ^ast.Expr_Proc_Sig:
	case ^ast.Expr_Proc_Group:
	case ^ast.Expr_Paren:
	case ^ast.Expr_Selector:
	case ^ast.Expr_Call:
	case ^ast.Expr_Compound:
	case ^ast.Expr_Index:
	case ^ast.Expr_Cast:
	case ^ast.Expr_Unary:
	case ^ast.Expr_Interface:
	case ^ast.Expr_Directive:
	case ^ast.Expr_Ternary:
	case ^ast.Expr_Ellipsis:

	case ^ast.Type_Struct:
	case ^ast.Type_Array:
	case ^ast.Type_Matrix:
	case ^ast.Type_Image:
	case ^ast.Type_Enum:
	case ^ast.Type_Bit_Set:

	case ^ast.Stmt_Return:
	case ^ast.Stmt_Break:
	case ^ast.Stmt_Continue:
	case ^ast.Stmt_For_Range:
		n := hovered_node_in_block(v.body, position)
		if n != nil {
			return n
		}
	case ^ast.Stmt_For:
		n := hovered_node_in_block(v.body, position)
		if n != nil {
			return n
		}
	case ^ast.Stmt_Block:
		n := hovered_node_in_block(v.body, position)
		if n != nil {
			return n
		}
	case ^ast.Stmt_If:
		n := hovered_node_in_block(v.then_block, position)
		if n != nil {
			return n
		}
		n = hovered_node_in_block(v.else_block, position)
		if n != nil {
			return n
		}
	case ^ast.Stmt_Switch:
	case ^ast.Stmt_Assign:
	case ^ast.Stmt_Expr:
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
	case ^ast.Decl_Import:
	}

	return node
}
