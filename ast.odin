package hepls

import "base:runtime"

import "core:log"
import "core:strings"

import vmem "core:mem/virtual"

import hep "hephaistos"
import ast "hephaistos/ast"

Ast :: struct {
	stmts:    []^ast.Stmt,
	checker:     hep.Checker,
	arena:       vmem.Arena,
	text:        string,
	file_id:     i32,
	in_progress: bool,
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
get_node_definition :: proc(node: ^ast.Node) -> (definition: ^ast.Node) {
	e := get_node_entity(node)
	if e == nil {
		return
	}
	definition = e.ident
	if e.ident == nil {
		definition = e.decl
	}
	return
}

ast_init :: proc(state: ^State, uri: Uri, source: string) -> ^Ast {
	ast := &state.asts[uri]
	if ast == nil {
		uri            := uri_clone(uri, context.allocator)
		state.asts[uri] = {}
		ast             = &state.asts[uri]

		ast.file_id = i32(len(state.file_uris))
		append(&state.file_uris, uri)

		arena_err := vmem.arena_init_growing(&ast.arena)
		log.assert(arena_err == nil)
	}

	vmem.arena_free_all(&ast.arena)
	ast.stmts = {}

	ast_allocator := vmem.arena_allocator(&ast.arena)

	source  := strings.clone(source, ast_allocator)
	ast.text = source

	return ast
}
