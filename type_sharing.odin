package hepls

import "base:runtime"

import "core:log"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"

import hep       "hephaistos"
import hep_types "hephaistos/types"

CONTENT :: `// This is an auto generated file to fetch types from a package. Why are you reading this?
package hepls_tmp

import "base:runtime"

@(require)
import pkg "%v"

@(export)
get_type_table :: proc() -> []^runtime.Type_Info {{
	return runtime.type_table
}}

@(export)
_main :: proc() {{
	pkg.main()
}}
`

@(require_results)
get_package_types :: proc(config: Config, path: string, types: ^map[string]^hep.Type, allocator := context.allocator) -> (ok: bool) {
	path, err := os.get_absolute_path(path, context.temp_allocator)
	if err != nil {
		return
	}

	dir: string
	dir, err = os.make_directory_temp("", "hepls_*", context.temp_allocator)
	if err != nil {
		return
	}
	defer os.remove_all(dir)

	wd: string
	wd, err = os.get_working_directory(context.temp_allocator)
	if err != nil {
		return
	}

	os.set_working_directory(dir)
	defer os.set_working_directory(wd)

	relative: string
	relative, err = os.get_relative_path(dir, path, context.temp_allocator)
	if err != nil {
		return
	}

	err = os.write_entire_file("main.odin", fmt.tprintf(CONTENT, relative))
	if err != nil {
		return
	}

	assert(config.odin_command != "")
	state, stdout, stderr, odin_err := os.process_exec({
		command = { config.odin_command, "build", ".", "-build-mode:shared", "-out:lib." + dynlib.LIBRARY_FILE_EXTENSION, "-o:none", },

	}, context.temp_allocator)
	if odin_err != nil {
		log.error("Failed to run odin compiler")
		return
	}
	if state.exit_code != 0 {
		log.error("Failed to run odin compiler")
		log.error("stdout:", string(stdout))
		log.error("stderr:", string(stderr))
		return
	}

	lib := dynlib.load_library("./lib." + dynlib.LIBRARY_FILE_EXTENSION) or_return
	defer dynlib.unload_library(lib)

	get_type_table := cast(proc() -> []^runtime.Type_Info)dynlib.symbol_address(lib, "get_type_table")

	package_name := os.base(path)

	type_table := get_type_table()
	for type in type_table {
		if type == nil {
			continue
		}
		named := type.variant.(runtime.Type_Info_Named) or_continue
		if named.pkg != package_name {
			continue
		}

		// the strings point into the shared library which we want to unload since there is no need to keep it around and it could very well be pretty big
		clone_type_strings :: proc(type: ^hep.Type, allocator := context.allocator) {
			switch v in type.variant {
			case ^hep_types.Struct:
				for &field in v.fields {
					field.name = strings.clone(field.name, allocator)
					clone_type_strings(field.type, allocator)
				}
			case ^hep_types.Matrix:
				clone_type_strings(v.col_type, allocator)
			case ^hep_types.Array:
				clone_type_strings(v.elem, allocator)
			case ^hep_types.Buffer:
				clone_type_strings(v.elem, allocator)
			case ^hep_types.Proc:
				for &arg in v.args {
					arg.name = strings.clone(arg.name, allocator)
					clone_type_strings(arg.type, allocator)
				}
				for &ret in v.returns {
					ret.name = strings.clone(ret.name, allocator)
					clone_type_strings(ret.type, allocator)
				}
				clone_type_strings(v.return_type, allocator)
			case ^hep_types.Proc_Group:
				for m in v.members {
					clone_type_strings(m, allocator)
				}
			case ^hep_types.Image:
				clone_type_strings(v.texel_type, allocator)
			case ^hep_types.Enum:
				for &value in v.values {
					value.name = strings.clone(value.name, context.allocator)
				}
				clone_type_strings(v.backing, allocator)
			case ^hep_types.Bit_Set:
				clone_type_strings(v.enum_type, allocator)
				clone_type_strings(v.backing,   allocator)
			case ^hep_types.Complex:
				clone_type_strings(v.array,     allocator)
			case ^hep_types.Opaque:
				clone_type_strings(v.backing,   allocator)
			}
		}

		name       := strings.clone(named.name, allocator)
		type       := hep.type_info_to_type(type, allocator) or_continue
		clone_type_strings(type, allocator)
		types[name] = type
	}

	return true
}
