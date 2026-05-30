package hepls

import "base:runtime"

import "core:log"
import "core:strings"

import vmem "core:mem/virtual"

import hep "hephaistos"

Ast :: struct {
	stmts:    []^hep.Ast_Stmt,
	checker:     hep.Checker,
	arena:       vmem.Arena,
	text:        string,
	file_id:     i32,
	in_progress: bool,
}

@(require_results)
get_node_entity :: proc(node: ^hep.Ast_Node) -> (entity: ^hep.Entity) {
	if node == nil {
		return
	}

	ident, ok := node.derived.(^hep.Expr_Ident)
	if !ok {
		return
	}

	return ident.entity
}

@(require_results)
get_node_definition :: proc(node: ^hep.Ast_Node) -> (definition: ^hep.Ast_Node) {
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
