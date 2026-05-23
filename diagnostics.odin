package hepls

import "base:runtime"

import "core:strings"
import vmem "core:mem/virtual"

import hep     "hephaistos"
import hep_ast "hephaistos/ast"

check_file :: proc(state: ^State, source: string, uri: Uri, show_errors := true) {
	ast           := ast_init(state, uri, source)
	ast_allocator := vmem.arena_allocator(&ast.arena)
	source        := ast.text

	send_errors :: proc(state: ^State, uri: Uri, errors: []hep.Error, code: string) {
		diagnostics := make([]Diagnostic, len(errors), context.temp_allocator)
		for &diagnostic, i in diagnostics {
			error := errors[i]

			diagnostic = {
				range    = {
					start = { line = error.line     - 1, character = error.column     - 1, },
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
				diagnostics = diagnostics[:],
			},
		}
		_ = send_message(response_notification)
	}

	tokens, errors := hep.tokenize(source, false, ast.file_id, allocator = ast_allocator, error_allocator = context.temp_allocator)
	if len(errors) != 0 {
		send_errors(state, uri, errors, "syntax")
		return
	}

	ast.stmts, errors = hep.parse(tokens, allocator = ast_allocator, error_allocator = context.temp_allocator)
	if len(errors) != 0 {
		send_errors(state, uri, errors, "syntax")
		return
	}

	libraries := make(map[string]hep.Library, ast_allocator)

	for stmt in ast.stmts {
		v := stmt.derived.(^hep_ast.Decl_Import) or_continue
		libraries[v.path.value.(string)] = {}
	}

	for name, &lib in libraries {
		@(require_results)
		check_library :: proc(
			source:    string,
			path:      string,
			defines:   map[string]hep.Const_Value = {},
			types:     map[string]^hep.Type       = {},
			libraries: map[string]hep.Library     = {},
			flags:     hep.Checker_Flags          = {},
			file_id:   i32                        = -1,
			allocator       := context.allocator,
			error_allocator := context.allocator,
		) -> (library: hep.Library, errors: []hep.Error, code: string) {
			tokens: []hep.Token
			tokens, errors = hep.tokenize(source, false, file_id, context.temp_allocator, error_allocator)
			if len(errors) != 0 {
				code = "syntax"
				return
			}

			stmts: []^hep.Ast_Stmt
			stmts, errors = hep.parse(tokens, allocator, error_allocator)
			if len(errors) != 0 {
				code = "syntax"
				return
			}

			c: hep.Checker
			c, errors = hep.check_with_types(stmts, defines, types, libraries, { .Enable_References, }, allocator, error_allocator)
			if len(errors) != 0 {
				code = "checker"
			}

			library.entities = c.scope.entities
			library.stmts    = stmts
			return
		}

		lib_uri := state.libraries[name]
		lib_ast := state.asts[lib_uri]
		source  := strings.clone(lib_ast.text, ast_allocator)
		code: string
		lib, errors, code = check_library(
			source,
			name,
			defines         = state.config.defines,
			types           = state.shared_types,
			libraries       = {}, // TODO
			file_id         = lib_ast.file_id,
			allocator       = ast_allocator,
			error_allocator = context.temp_allocator,
		)

		send_errors(state, lib_uri, errors, code)
	}

	ast.checker, errors = hep.check_with_types(
		ast.stmts,
		defines         = state.config.defines,
		types           = state.shared_types,
		libraries       = libraries,
		flags           = state.checker_flags | { .Enable_References, },
		allocator       = ast_allocator,
		error_allocator = context.temp_allocator,
	)

	send_errors(state, uri, errors, "checker")
}
