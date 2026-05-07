#+feature dynamic-literals
package hepls

import "base:runtime"

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:mem"
import vmem "core:mem/virtual"

import hep           "hephaistos"
import hep_ast       "hephaistos/ast"
import hep_types     "hephaistos/types"
import hep_tokenizer "hephaistos/tokenizer"

Error :: union {
	json.Unmarshal_Error,
	json.Marshal_Error,
}

State :: struct {
	initialized:  bool,
	shutdown:     bool,
	exit:         bool,

	asts:          map[Uri]Ast,
	shared_types:  map[string]^hep.Type,
	libraries:     map[string]hep.Library,
	checker_flags: hep.Checker_Flags,
	config:        Config,
}

Config :: struct {
	odin_command:        string,
	checker_only_saved:  bool,
	shared_type_sources: []string,
	defines:             map[string]hep.Const_Value,
	checker_flags:       []hep.Checker_Flag,
	libraries:           map[string]string,
}

main :: proc() {
	when ODIN_DEBUG {
		log_file, err := os.open("log.txt", { .Create, .Read, .Write, .Trunc, }, os.Permissions_Default_File)
		if err != 0 {
			return
		}
		context.logger = log.create_file_logger(log_file, lowest = .Debug, allocator = context.allocator)
		defer log.destroy_file_logger(context.logger, allocator = context.allocator)
	}

	log.debug("pid:", os.get_pid())

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)

		defer for _, leak in track.allocation_map {
			log.infof("leaked %m", leak.size, location = leak.location)
		}
		defer for free in track.bad_free_array {
			log.errorf("bad free", location = free.location)
		}
	}

	state: State = {
		config = {
			odin_command        = "odin",
			// NOTE: paths are reverse ordered by likelihood of being what the user wants, since types may overwrite each other
			shared_type_sources = { "src", "../src", "..", ".", },
		},
	}

	defer {
		for uri, &ast in state.asts {
			delete(string(uri), context.allocator)
			vmem.arena_destroy(&ast.arena)
		}
		defer delete(state.asts)
	}

	document_arena: vmem.Arena
	document_err := vmem.arena_init_growing(&document_arena)
	log.assert(document_err == nil)
	defer vmem.arena_destroy(&document_arena)
	document_allocator := vmem.arena_allocator(&document_arena)

	global_config: {
		global_config_path, _ := os.join_path({ os.dir(os.args[0]), "hepls.json", }, context.temp_allocator)
		global_config_data    := os.read_entire_file(global_config_path, context.temp_allocator) or_break global_config
		err                   := json.unmarshal(global_config_data, &state.config, allocator = document_allocator)
		if err != nil {
			log.error("Failed to load global config:", err)
		}
	}

	local_config: {
		local_config_path := "hepls.json"
		local_config_data := os.read_entire_file(local_config_path, context.temp_allocator) or_break local_config
		err               := json.unmarshal(local_config_data, &state.config, allocator = document_allocator)
		if err != nil {
			log.error("Failed to load local config:", err)
		}
	}

	log.debug("config:", state.config)

	state.shared_types = make(map[string]^hep.Type, document_allocator)
	for pkg in state.config.shared_type_sources {
		ok := get_package_types(state.config, pkg, &state.shared_types, document_allocator)
		if !ok {
			log.error("Failed to load types from package:", pkg)
		}
	}
	log.debug("shared types:", state.shared_types)

	for flag in state.config.checker_flags {
		state.checker_flags += { flag, }
	}

	state.libraries = make(map[string]hep.Library, document_allocator)
	for name, path in state.config.libraries {
		f, err     := os.open(path)
		if err != nil {
			log.error("Failed to open library file:", path, err)
			continue
		}
		info, err2 := os.fstat(f, context.temp_allocator)
		if err2 != nil {
			log.error("Failed to open library file:", path, err2)
			continue
		}

		if info.type == .Directory {
			log.error("Failed to open library file:", path, "directories are not supported yet")
			continue
		}

		data: []byte
		data, err = os.read_entire_file(f, document_allocator)
		if err != nil {
			log.error("Failed to read library file:", path, err)
			continue
		}

		library, errors := hep.check_library(string(data), path, allocator = document_allocator)
		if len(errors) != 0 {
			log.error("Failed to compile library file:", path)
			continue
		}
		state.libraries[name] = library
	}
	log.debug("libraries:", state.libraries)

	s: bufio.Scanner
	bufio.scanner_init(&s, io.to_reader(os.to_stream(os.stdin)), buf_allocator = context.allocator)
	s.split = split
	defer bufio.scanner_destroy(&s)

	for !state.exit && bufio.scanner_scan(&s) {
		text := bufio.scanner_bytes(&s)
		method, contents, ok := decode_message(text)
		if !ok {
			log.error("Failed to decode message")
			return
		}
		handle_message(&state, method, contents)

		free_all(context.temp_allocator)
	}

	if !state.shutdown {
		os.exit(1)
	}
}

handle_message :: proc(state: ^State, method: string, contents: []byte) {
	log.info(method)
	if fn, ok := requests_map[method]; ok {
		err := fn(state, contents)
		if err != nil {
			log.panic(method, err, string(contents))
		}
		return
	}

	log.error("Invalid method:", method)
}

requests_map := map[string]proc(state: ^State, contents: []byte) -> (error: Error) {
	"textDocument/didOpen"           = notification_did_open_text_document,
	"textDocument/didChange"         = notification_did_change_text_document,
	"textDocument/didSave"           = notification_did_save_text_document,
	"textDocument/completion"        = request_completion,
	"textDocument/hover"             = request_hover,
	"textDocument/definition"        = request_definition,
	"textDocument/references"        = request_references,
	"textDocument/documentHighlight" = request_highlight,
	"textDocument/rename"            = request_rename,
	"textDocument/signatureHelp"     = request_signature_help,
	"shutdown"                       = request_shutdown,
	"initialize"                     = request_initialize,
	"initialized"                    = notification_initialized,
	"exit"                           = notification_exit,
}

notification_initialized :: proc(state: ^State, contents: []byte) -> Error {
	return nil
}

notification_did_open_text_document :: proc(state: ^State, contents: []byte) -> (error: Error) {
	notification: Notification(Did_Open_Text_Document_Params)
	json.unmarshal(contents, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

	log.infof("textDocument/didOpen(%v)", params.textDocument.uri)

	return check_file(state, notification.params.textDocument.text, params.textDocument.uri)
}

notification_did_change_text_document :: proc(state: ^State, content: []byte) -> (error: Error) {
	notification: Notification(Did_Change_Text_Document_Params)
	json.unmarshal(content, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

	log.infof("textDocument/didChange(%v)", params.textDocument.uri)

	return check_file(state, params.contentChanges[0].text, params.textDocument.uri, !state.config.checker_only_saved)
}

notification_did_save_text_document :: proc(state: ^State, content: []byte) -> (error: Error) {
	notification: Request(Did_Save_Text_Document_Params)
	json.unmarshal(content, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

	log.infof("textDocument/didSave(%v)", params.textDocument.uri)

	text, ok := params.text.?
	if !ok {
		return nil
	}

	return check_file(state, text, notification.params.textDocument.uri)
}

request_shutdown :: proc(state: ^State, content: []byte) -> (error: Error) {
	request: Request(struct{})
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return

	state.shutdown = true

	response := Response {
		id = request.id,
	}
	return send_message(response)
}

notification_exit :: proc(state: ^State, content: []byte) -> (error: Error) {
	notification: Notification(struct{})
	json.unmarshal(content, &notification, allocator = context.temp_allocator) or_return

	state.exit = true
	return nil
}

Notification :: struct($Params: typeid) {
	using _: Base_Notification,
	params:  Params,
}

Base_Notification :: struct {
	jsonrpc: string,
	method:  string,
}

Uri :: distinct string

Text_Document_Identifier :: struct {
	uri: Uri,
}

Versioned_Text_Document_Identifier :: struct {
	using _: Text_Document_Identifier,
	version: int,
}

Text_Document_Item :: struct {
	uri:        Uri,
	languageId: string,
	version:    int,
	text:       string,
}

Did_Open_Text_Document_Params :: struct {
	textDocument: Text_Document_Item,
}

Did_Save_Text_Document_Params :: struct {
	textDocument: Text_Document_Identifier,
	text:         Maybe(string),
}

Did_Change_Text_Document_Params :: struct {
	textDocument:   Versioned_Text_Document_Identifier,
	contentChanges: []struct { text: string, },
}

Publish_Diagnositics_Params :: struct {
	uri:         Uri,
	version:     Maybe(int),
	diagnostics: []Diagnostic,
}

Diagnostic_Severity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

Diagnostic :: struct {
	range:    Range,
	message:  string,
	code:     string,
	severity: Maybe(Diagnostic_Severity),
}

Range :: struct {
	start, end: Position,
}

Position :: struct {
	line, character: int,
}

Base_Request :: struct {
	jsonrpc: string,
	id:      int,
	method:  string,
}

Request :: struct($Params: typeid) {
	using _: Base_Request,
	params:  Params,
}

@(require_results)
request_initialize :: proc(state: ^State, contents: []byte) -> (error: Error) {
	request: Request(Initialize_Request_Params)
	json.unmarshal(contents, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.info("Connected to", params.clientInfo.name, params.clientInfo.version)

	state.initialized = true

	response := Response {
		id     = request.id,
		result = Initialize_Result {
			serverInfo  = Server_Info {
				name    = "hephaistos language server (hepls)",
				version = "0.0.1",
			},
			capabilities = {
				textDocumentSync          = .Full,
				completionProvider        = { triggerCharacters = { ".", }, },
				hoverProvider             = true,
				definitionProvider        = true,
				referencesProvider        = true,
				documentHighlightProvider = true,
				renameProvider            = true,
				signatureHelpProvider     = {
					triggerCharacters   = { "(", ",", "return", },
					retriggerCharacters = { ",", },
				},
			},
		},
	}
	return send_message(response)
}

Initialize_Request_Params :: struct {
	clientInfo: struct {
		name:    string,
		version: Maybe(string),
	},
}

Initialize_Result :: struct {
	capabilities: Capabilities,
	serverInfo:   Maybe(Server_Info),
}

Signature_Help_Options :: struct {
	triggerCharacters:   []string,
	retriggerCharacters: []string,
}

Capabilities :: struct {
	textDocumentSync:          Text_Document_Sync_Kind,
	completionProvider:        Completion_Options,
	hoverProvider:             bool,
	definitionProvider:        bool,
	referencesProvider:        bool,
	documentHighlightProvider: bool,
	renameProvider:            bool,
	signatureHelpProvider:     Signature_Help_Options,
}

Completion_Options :: struct {
	triggerCharacters: []string,
}

Text_Document_Sync_Kind :: enum {
	None        = 0,
	Full        = 1,
	Incremental = 2,
}

Server_Info :: struct {
	name:    string,
	version: Maybe(string),
}

Response :: struct {
	using _: Base_Response,
	result:  Response_Result,
}

Response_Result :: union {
	Initialize_Result,
	Completion_Result,
	Hover_Result,
	Location,
	[]Location,
	[]Document_Highlight,
	Workspace_Edit,
	Signature_Help,
}

Base_Response :: struct {
	jsonrpc: string,
	id:      Maybe(int),
}

Completion_Result :: []Completion_Item

Completion_Item_Kind :: enum {
	Text          = 1,
	Method        = 2,
	Function      = 3,
	Constructor   = 4,
	Field         = 5,
	Variable      = 6,
	Class         = 7,
	Interface     = 8,
	Module        = 9,
	Property      = 10,
	Unit          = 11,
	Value         = 12,
	Enum          = 13,
	Keyword       = 14,
	Snippet       = 15,
	Color         = 16,
	File          = 17,
	Reference     = 18,
	Folder        = 19,
	EnumMember    = 20,
	Constant      = 21,
	Struct        = 22,
	Event         = 23,
	Operator      = 24,
	TypeParameter = 25,
}

Completion_Item :: struct {
	label:  string,
	detail: Maybe(string),
	kind:   Completion_Item_Kind,
}

Completion_Trigger_Kind :: enum {
	/**
	 * Completion was triggered by typing an identifier (24x7 code
	 * complete), manual invocation (e.g Ctrl+Space) or via API.
	 */
	Invoked = 1,

	/**
	 * Completion was triggered by a trigger character specified by
	 * the `triggerCharacters` properties of the
	 * `CompletionRegistrationOptions`.
	 */
	TriggerCharacter = 2,

	/**
	 * Completion was re-triggered as the current completion list is incomplete.
	 */
	TriggerForIncompleteCompletions = 3,
}

Completion_Params :: struct {
	using _:  Text_Document_Position_Params,
	context_: struct {
		triggerKind: Completion_Trigger_Kind,
	} `json:"context"`,
	triggerCharacter: Maybe(string),
}

request_completion :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Completion_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/completion(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location  := position_to_location(params.position)
	node, ctx := get_hover_context(ast.stmts, location)

	response := Response {
		id = request.id,
	}
	if node == nil {
		return send_message(response)
	}

	items := make([dynamic]Completion_Item, context.temp_allocator)

	@(require_results)
	entity_completion_item :: proc(entity: ^hep_ast.Entity, location: Maybe(hep.Location) = nil) -> (item: Completion_Item, ok: bool) {
		item = Completion_Item {
			label  = entity.name,
			detail = entity_detail_string(entity, false),
		}

		switch entity.kind {
		case .Invalid:
			return
		case .Const:
			item.kind = .Constant
		case .Type:
			item.kind = .TypeParameter
		case .Var:
			if location, ok := location.?; ok && location_before(location, entity.decl.end) {
				return
			}
			item.kind = .Variable
		case .Proc, .Proc_Group:
			item.kind = .Function
		case .Builtin:
			item.kind = .Function
		case .Library:
			item.kind = .Module
		case .Label:
			item.kind = .Text
		}

		ok = true
		return
	}

	expected_entity_kind: hep_ast.Entity_Kind
	#partial switch v in ctx.expr {
	case ^hep_ast.Expr_Selector:
		if v.lhs == nil {
			break
		}

		if ident, ok := v.lhs.derived.(^hep_ast.Expr_Ident); ok {
			if ident.entity != nil && ident.entity.kind == .Library {
				lib := ast.checker.libraries[ident.entity.library] or_break
				for _, e in lib.entities {
					item := entity_completion_item(e) or_continue
					append(&items, item)
				}
				break
			}
		}

		type := v.lhs.type
		if type == nil {
			break
		}

		#partial switch type.kind {
		case .Array:
			append(&items, Completion_Item { label = "x", kind = .Field, })
			append(&items, Completion_Item { label = "y", kind = .Field, })
			append(&items, Completion_Item { label = "z", kind = .Field, })
			append(&items, Completion_Item { label = "w", kind = .Field, })

			append(&items, Completion_Item { label = "r", kind = .Field, })
			append(&items, Completion_Item { label = "g", kind = .Field, })
			append(&items, Completion_Item { label = "b", kind = .Field, })
			append(&items, Completion_Item { label = "a", kind = .Field, })
		case .Struct:
			for member in type.variant.(^hep_types.Struct).fields {
				append(&items, Completion_Item {
					label  = member.name,
					kind   = .Field,
					detail = hep_types.to_string(member.type, false, context.temp_allocator),
				})
			}
		case .Enum:
			for member in type.variant.(^hep_types.Enum).values {
				append(&items, Completion_Item {
					label  = member.name,
					kind   = .EnumMember,
					detail = fmt.tprint(member.value),
				})
			}
		}
	case ^hep_ast.Stmt_Break, ^hep_ast.Stmt_Continue:
		expected_entity_kind = .Label
	case:
		seen := make(map[string]struct{}, context.temp_allocator)

		scope := ctx.scope
		for scope != nil {
			for name, e in scope.entities {
				if name in seen {
					continue
				}
				seen[name] = {}

				if expected_entity_kind != nil && e.kind != expected_entity_kind {
					continue
				}

				item := entity_completion_item(e) or_continue
				append(&items, item)
			}
			scope = scope.parent
		}

		for name in hep_tokenizer.keyword_strings {
			if name in seen {
				continue
			}
			seen[name] = {}

			append(&items, Completion_Item {
				label = name,
				kind  = .Keyword,
			})
		}
	}

	response.result = items[:]
	return send_message(response)
}

Text_Document_Position_Params :: struct {
	textDocument: Text_Document_Identifier,
	position:     Position,
}

Hover_Params :: struct {
	using _: Text_Document_Position_Params,
}

Markup_Kind :: distinct string

Markup_Content :: struct {
	kind:  Markup_Kind,
	value: string,
}

Hover_Result :: struct {
	contents: Markup_Content,
	range:    Maybe(Range),
}

request_hover :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Hover_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/hover(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location := position_to_location(params.position)
	node, _  := get_hover_context(ast.stmts, location)

	response: Response = {
		id = request.id,
	}

	if node == nil {
		return send_message(response)
	}

	text := node_hover_text(node, context.temp_allocator)

	if text == "" {
		return send_message(response)
	}

	response.result = Hover_Result {
		contents = {
			kind  = "markdown",
			value = fmt.tprintf("```odin\n%s\n```", text),
		},
	}

	return send_message(response)
}

Definition_Params :: struct {
	using _: Text_Document_Position_Params,
}

Location :: struct {
	uri:   Uri,
	range: Range,
}

@(require_results)
uri_from_path :: proc(path: string, allocator: runtime.Allocator) -> (uri: Uri, ok: bool) {
	abs, err := os.get_absolute_path(path, context.temp_allocator)
	if err != nil {
		log.error("Failed to get file uri:", path, err)
		return
	}
	return Uri(fmt.aprintf("file://%v", abs, allocator = allocator)), true
}

@(require_results)
uri_clone :: proc(uri: Uri, allocator: runtime.Allocator) -> Uri {
	return Uri(strings.clone(string(uri), allocator))
}

request_definition :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Definition_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/definition(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location  := position_to_location(params.position)
	root, _   := get_hover_context(ast.stmts, location)

	response: Response = {
		id = request.id,
	}

	if root == nil {
		return send_message(response)
	}

	uri := params.textDocument.uri
	range: Range

	if import_decl, ok := root.derived.(^hep.Ast_Decl_Import); ok {
		ok: bool
		uri, ok = get_imported_library_uri(state, import_decl, context.temp_allocator)
		range   = {}

		if !ok {
			return send_message(response)
		}
	} else {
		lib, node := get_node_definition(root)

		if node == nil {
			return send_message(response)
		}

		range = Range {
			start = location_to_position(node.start),
			end   = location_to_position(node.end),
		}

		if lib != "" {
			uri = uri_from_path(lib, context.temp_allocator) or_else params.textDocument.uri
		}
	}

	response.result = Location {
		uri   = uri,
		range = range,
	}

	return send_message(response)
}

@(require_results)
location_to_position :: proc(location: hep.Location) -> Position {
	return {
		line      = location.line   - 1,
		character = location.column - 1,
	}
}

@(require_results)
position_to_location :: proc(location: Position) -> hep.Location {
	return {
		line   = location.line      + 1,
		column = location.character + 1,
	}
}

@(require_results)
location_before :: proc(a, b: hep.Location) -> bool {
	if a.line < b.line {
		return true
	}
	if a.line == b.line && a.column < b.column {
		return true
	}
	return false
}

Reference_Params :: struct {
	using _: Text_Document_Position_Params,
}

request_references :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Reference_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/references(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location := position_to_location(params.position)
	node, _  := get_hover_context(ast.stmts, location)
	entity   := get_node_entity(node)

	response: Response = {
		id = request.id,
	}

	if entity == nil {
		return send_message(response)
	}

	locations := make([dynamic]Location, context.temp_allocator)

	iter := ast_iterator_make(ast.stmts, context.temp_allocator)
	for node in ast_iterator(&iter) {
		e := get_node_entity(node)
		if e == entity {
			append(&locations, Location {
				uri   = params.textDocument.uri,
				range = {
					start = location_to_position(node.start),
					end   = location_to_position(node.end),
				},
			})
		}
	}

	response.result = locations[:]

	return send_message(response)
}

Highlight_Params :: struct {
	using _: Text_Document_Position_Params,
}

Document_Highlight :: struct {
	range: Range,
}

request_highlight :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Reference_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/documentHighlight(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location := position_to_location(params.position)
	node, _  := get_hover_context(ast.stmts, location)
	entity   := get_node_entity(node)

	response: Response = {
		id = request.id,
	}

	if entity == nil {
		return send_message(response)
	}

	highlights := make([dynamic]Document_Highlight, context.temp_allocator)

	iter := ast_iterator_make(ast.stmts, context.temp_allocator)
	for node in ast_iterator(&iter) {
		e := get_node_entity(node)
		if e == entity {
			append(&highlights, Document_Highlight {
				range = {
					start = location_to_position(node.start),
					end   = location_to_position(node.end),
				},
			})
		}
	}

	response.result = highlights[:]

	return send_message(response)
}

Rename_Params :: struct {
	using _: Text_Document_Position_Params,
	newName: string,
}

Workspace_Edit :: struct {
	changes: map[Uri][]Text_Edit,
}

Text_Edit :: struct {
	range:   Range,
	newText: string,
}

request_rename :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Rename_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/rename(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location := position_to_location(params.position)
	node, _  := get_hover_context(ast.stmts, location)
	entity   := get_node_entity(node)

	response: Response = {
		id = request.id,
	}

	if entity == nil {
		return send_message(response)
	}

	edits := make([dynamic]Text_Edit, context.temp_allocator)

	iter := ast_iterator_make(ast.stmts, context.temp_allocator)
	for node in ast_iterator(&iter) {
		e := get_node_entity(node)
		if e == entity {
			append(&edits, Text_Edit {
				range = {
					start = location_to_position(node.start),
					end   = location_to_position(node.end),
				},
				newText = params.newName,
			})
		}
	}

	changes                         := make(map[Uri][]Text_Edit, context.temp_allocator)
	changes[params.textDocument.uri] = edits[:]

	response.result = Workspace_Edit {
		changes = changes,
	}

	return send_message(response)
}

Signature_Help_Params :: struct {
	using _: Text_Document_Position_Params,
}

Signature_Help :: struct {
	signatures: []Signature_Information,
}

Signature_Information :: struct {
	label:           string,
	documentation:   Maybe(string),
	parameters:      []Parameter_Information,
	activeParameter: Maybe(int),
}

Parameter_Information :: struct {
	label:         string,
	documentation: Maybe(string),
}

request_signature_help :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Signature_Help_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	log.infof("textDocument/signatureHelp(%v)", params.textDocument.uri)

	ast := state.asts[params.textDocument.uri]

	location := position_to_location(params.position)
	_, ctx   := get_hover_context(ast.stmts, location)

	response: Response = {
		id = request.id,
	}

	text: string
	args: []hep_types.Field

	#partial switch v in ctx.expr {
	case ^hep_ast.Expr_Compound:
		if v.type == nil {
			break
		}
		text         = node_hover_text(v, context.temp_allocator)
		struct_type := v.type.variant.(^hep_types.Struct) or_break
		args         = struct_type.fields
	case ^hep_ast.Expr_Call:
		if v.lhs == nil || v.lhs.type == nil {
			break
		}
		text       = node_hover_text(v.lhs, context.temp_allocator)
		proc_type := v.lhs.type.variant.(^hep_types.Proc) or_break
		args       = proc_type.args
	case ^hep_ast.Stmt_Return:
		if ctx.procedure == nil || ctx.procedure.type == nil {
			break
		}
		text       = node_hover_text(ctx.procedure, context.temp_allocator)
		proc_type := ctx.procedure.type.variant.(^hep_types.Proc) or_break
		args       = proc_type.returns
	}

	if text == "" {
		return send_message(response)
	}

	signature := Signature_Information {
		label = text,
	}

	if len(args) != 0 {
		signature.parameters = make([]Parameter_Information, len(args))
		for &param, i in signature.parameters {
			param = { label = fmt.tprintf("%v: %v", args[i].name, args[i].type), }
		}
		if ctx.arg_index < len(args) {
			signature.activeParameter = ctx.arg_index
		}
	}

	response.result = Signature_Help {
		signatures = { signature, },
	}

	return send_message(response)
}
