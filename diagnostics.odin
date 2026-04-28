package hepls

import "core:strings"
import vmem "core:mem/virtual"

import hep "hephaistos"

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

	source := strings.clone(source, ast_allocator)

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
