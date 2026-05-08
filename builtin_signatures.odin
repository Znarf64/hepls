package hepls

import "base:runtime"

import "core:mem"
import "core:strings"

import hep_ast     "hephaistos/ast"
import hep_checker "hephaistos/checker"

Builtin_Signature :: struct {
	text: string,
	args: []Parameter_Information,
}

builtin_signatures: [hep_ast.Builtin_Id]Builtin_Signature

@(init)
initialize_builtin_signatures :: proc "contextless" () {
	context = runtime.default_context()

	@(static)
	arena_mem: [1 << 12]byte
	arena: mem.Arena
	mem.arena_init(&arena, arena_mem[:])
	allocator := mem.arena_allocator(&arena)

	base       := #load_directory("hephaistos/base")
	extensions := #load_directory("hephaistos/extensions")

	lookup_builtin :: proc(name: string) -> (hep_ast.Builtin_Id, bool) {
		for n, builtin in hep_checker.builtin_names {
			n := n

			if dot := strings.index(n, "."); dot != -1 {
				n = n[dot + 1:]
			}

			if name == n {
				return builtin, true
			}
		}

		return .Invalid, false
	}

	handle_file :: proc(source: string, allocator: runtime.Allocator) {
		source := source

		// NOTE: Kind of stupid, but good enough for now

		for line in strings.split_lines_iterator(&source) {
			name, match, signature := strings.partition(line, "::")
			(match != "") or_continue

			signature, match, _ = strings.partition(signature, "---")
			(match != "") or_continue
			signature = strings.trim_space(signature)

			builtin := lookup_builtin(strings.trim_space(name)) or_continue

			args      := strings.trim_prefix(signature, "proc(")
			args, _, _ = strings.partition(args, "->")
			args       = strings.trim_space(args)
			args       = args[:len(args) - 1] // trim ")"

			parameter_strings := strings.split(args, ",", context.temp_allocator)
			parameters        := make([]Parameter_Information, len(parameter_strings), allocator)

			for &param, i in parameters {
				param.label = strings.trim_space(parameter_strings[i])
			}

			builtin_signatures[builtin] = {
				text = signature,
				args = parameters,
			}
		}
	}

	for &singature in builtin_signatures {
		singature.text = "builtin"
	}

	for file in base {
		handle_file(string(file.data), allocator)
	}
	for file in extensions {
		handle_file(string(file.data), allocator)
	}
}
