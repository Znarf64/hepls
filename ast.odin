package hepls

import "base:runtime"

import vmem "core:mem/virtual"

import hep "hephaistos"
import ast "hephaistos/ast"

Ast :: struct {
	stmts:    []^ast.Stmt,
	checker:     hep.Checker,
	arena:       vmem.Arena,
	text:        string,
	file_id:     int,
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
get_node_definition :: proc(node: ^ast.Node) -> (file_id: int, definition: ^ast.Node) {
	e := get_node_entity(node)
	if e == nil {
		return
	}
	file_id    = e.file_id
	definition = e.ident
	if e.ident == nil {
		definition = e.decl
	}
	return
}
