package hepls

import "base:runtime"

import "core:log"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode"

import hep "hephaistos"

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
get_package_types :: proc(config: Config, path: string, types: ^map[string]^hep.Type, allocator: runtime.Allocator) -> (ok: bool) {
	dir_file, err := os.open(path)
	if err != nil {
		return
	}
	defer os.close(dir_file)

	iter := os.read_directory_iterator_create(dir_file)
	defer os.read_directory_iterator_destroy(&iter)

	package_name: string
	for file, _ in os.read_directory_iterator(&iter) {
		if !strings.has_suffix(file.name, ".odin") {
			continue
		}
		data, err := os.read_entire_file(file.fullpath, context.temp_allocator)
		if err != nil {
			return
		}
		for line in strings.split_lines_iterator((^string)(&data)) {
			if !strings.has_prefix(line, "package ") {
				continue
			}
			package_name = strings.trim_left_space(line[len("package "):])
			for r, i in package_name {
				if unicode.is_letter(r) || unicode.is_number(r) || r == '_' {
					continue
				}
				package_name = package_name[:i]
				break
			}
			break
		}
		break
	}

	if package_name == "" {
		return
	}

	absolute_path: string
	absolute_path, err = os.get_absolute_path(path, context.temp_allocator)
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
	relative, err = os.get_relative_path(dir, absolute_path, context.temp_allocator)
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
		clone_type_strings :: proc(type: ^hep.Type, allocator: runtime.Allocator) {
			switch v in type.variant {
			case ^hep.Type_Struct:
				for &field in v.fields {
					field.name = strings.clone(field.name, allocator)
					clone_type_strings(field.type, allocator)
				}
			case ^hep.Type_Matrix:
				clone_type_strings(v.col_type, allocator)
			case ^hep.Type_Array:
				clone_type_strings(v.elem, allocator)
			case ^hep.Type_Buffer:
				clone_type_strings(v.elem, allocator)
			case ^hep.Type_Proc:
				for &arg in v.args {
					arg.name = strings.clone(arg.name, allocator)
					clone_type_strings(arg.type, allocator)
				}
				for &ret in v.returns {
					ret.name = strings.clone(ret.name, allocator)
					clone_type_strings(ret.type, allocator)
				}
				clone_type_strings(v.return_type, allocator)
			case ^hep.Type_Proc_Group:
				for m in v.members {
					clone_type_strings(m, allocator)
				}
			case ^hep.Type_Image:
				clone_type_strings(v.texel_type, allocator)
			case ^hep.Type_Enum:
				for &value in v.values {
					value.name = strings.clone(value.name, allocator)
				}
				clone_type_strings(v.backing, allocator)
			case ^hep.Type_Bit_Set:
				clone_type_strings(v.enum_type, allocator)
				clone_type_strings(v.backing,   allocator)
			case ^hep.Type_Complex:
				clone_type_strings(v.array, allocator)
			case ^hep.Type_Opaque:
				v.name = strings.clone(v.name, allocator)
				clone_type_strings(v.backing,  allocator)
			case ^hep.Type_Named:
				v.name = strings.clone(v.name, allocator)
				clone_type_strings(v.type,     allocator)
			case ^hep.Type_Fixed:
			}
		}

		name       := strings.clone(named.name, allocator)
		type       := hep.type_info_to_type(type, allocator) or_continue
		clone_type_strings(type, allocator)
		types[name] = type
	}

	return true
}
