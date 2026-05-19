package hepls

import "base:runtime"

import vmem "core:mem/virtual"

import hep "hephaistos"
import ast "hephaistos/ast"

Ast :: struct {
	stmts: []^ast.Stmt,
	checker:  hep.Checker,
	arena:    vmem.Arena,
	text:     string,
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

@(require_results)
get_imported_library_uri :: proc(state: ^State, decl: ^ast.Decl_Import, allocator: runtime.Allocator) -> (uri: Uri, ok: bool) {
	path := decl.path.const_value.(string) or_return
	path  = state.config.libraries[path]   or_return
	uri   = uri_from_path(path, allocator) or_return
	ok    = true
	return
}
