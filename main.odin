#+feature dynamic-literals
package hepls

import "base:intrinsics"

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:encoding/json"
import vmem "core:mem/virtual"
import "core:mem"

import hep "hephaistos"

Error :: union {
	json.Unmarshal_Error,
	json.Marshal_Error,
}

State :: struct {
	initialized: bool,
	shutdown:    bool,
	ast:         []^hep.Ast_Stmt,
	ast_arena:   vmem.Arena,
}

main :: proc() {
	log_file, err := os.open("log.txt", { .Create, .Read, .Write, .Trunc, }, os.Permissions_Default_File)
	if err != 0 {
		return
	}
	context.logger = log.create_file_logger(log_file, lowest = .Info, allocator = context.allocator)
	defer log.destroy_file_logger(context.logger, allocator = context.allocator)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)

		defer for _, leak in track.allocation_map {
			log.infof("%v leaked %m\n", leak.location, leak.size)
		}
		defer for free in track.bad_free_array {
			log.errorf("%v was freed badly %m\n", free.location)
		}
	}

	// TODO(Franz): fetch shared types (somehow)

	state: State
	arena_err := vmem.arena_init_growing(&state.ast_arena)
	log.assert(arena_err == nil)
	defer vmem.arena_destroy(&state.ast_arena)

	s: bufio.Scanner
	bufio.scanner_init(&s, io.to_reader(os.to_stream(os.stdin)), buf_allocator = context.allocator)
	s.split = split
	defer bufio.scanner_destroy(&s)

	for bufio.scanner_scan(&s) {
		text := bufio.scanner_bytes(&s)
		method, contents, ok := decode_message(text)
		if !ok {
			log.error("Failed to decode message")
			return
		}
		handle_message(&state, method, contents)

		free_all(context.temp_allocator)
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

send_buffer: strings.Builder

@(require_results)
send_message :: proc(data: $T) -> (error: Error) where intrinsics.type_has_field(T, "jsonrpc") {
	data        := data
	data.jsonrpc = "2.0"

	content := json.marshal(data, allocator = context.temp_allocator) or_return
	strings.builder_reset(&send_buffer)
	message := fmt.sbprintf(&send_buffer, "Content-Length: %d\r\n\r\n%s", len(content), content)

	os.write(os.stdout, transmute([]byte)message)
	return nil
}

split :: proc(data: []byte, _: bool) -> (
	advance:     int,
	token:       []byte,
	err:         bufio.Scanner_Error,
	final_token: bool,
) {
	data := string(data)
	header_len := strings.index(data, "\r\n\r\n")
	if header_len == -1 {
		return
	}

	header := data[:header_len]
	content_len: int

	for line in strings.split_lines_iterator(&header) {
		l := len("Content-Length: ")
		if len(line) > l && line[:l] == "Content-Length: " {
			err         = io.Error.Unknown
			content_len = strconv.parse_int(line[l:]) or_return
			err         = nil
		}
	}

	if len(data) - header_len - 4 < content_len {
		return
	}

	advance = header_len + 4 + content_len
	token   = transmute([]byte)data[:advance]

	return
}

requests_map := map[string]proc(state: ^State, contents: []byte) -> (error: Error) {
	"textDocument/didOpen"    = notification_did_open_text_document,
	"textDocument/didChange"  = notification_did_change_text_document,
	"textDocument/didSave"    = notification_did_save_text_document,
	"textDocument/completion" = request_completion,
	"textDocument/hover"      = request_hover,
	"textDocument/definition" = request_definition,
	"shutdown"                = request_shutdown,
	"initialize"              = request_initialize,
	"initialized"             = notification_initialized,
	"exit"                    = notification_exit,
}

notification_initialized :: proc(state: ^State, contents: []byte) -> Error {
	return nil
}

notification_did_open_text_document :: proc(state: ^State, contents: []byte) -> (error: Error) {
	notification: Notification(Did_Open_Text_Document_Params)
	json.unmarshal(contents, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

	return check_file(state, notification.params.textDocument.text, params.textDocument.uri)
}

notification_did_change_text_document :: proc(state: ^State, content: []byte) -> (error: Error) {
	notification: Notification(Did_Change_Text_Document_Params)
	json.unmarshal(content, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

	return check_file(state, params.contentChanges[0].text, params.textDocument.uri)
}

notification_did_save_text_document :: proc(state: ^State, content: []byte) -> (error: Error) {
	notification: Request(Did_Save_Text_Document_Params)
	json.unmarshal(content, &notification, allocator = context.temp_allocator) or_return
	params := notification.params

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

	os.exit(state.shutdown ? 0 : 1)
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
				name    = "hephaistos lsp",
				version = "0.0.1",
			},
			capabilities = {
				textDocumentSync   = .Full,
				hoverProvider      = true,
				definitionProvider = true,
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

Capabilities :: struct {
	textDocumentSync:   Text_Document_Sync_Kind,
	completionProvider: Completion_Options,
	hoverProvider:      bool,
	definitionProvider: bool,
}

Completion_Options :: struct {}

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
}

Base_Response :: struct {
	jsonrpc: string,
	id:      Maybe(int),
}

Completion_Result :: []Completion_Item

Completion_Item :: struct {
	label: string,
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
	context_: struct {
		triggerKind: Completion_Trigger_Kind,
	} `json:"context"`,
	triggerCharacter: Maybe(string),
}

request_completion :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Completion_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return

	response := Response {
		id     = request.id,
		result = Completion_Result {
			{ "return",  },
			{ "import",  },
			{ "for",     },
			{ "in",      },
			{ "proc",    },
			{ "struct",  },
			{ "enum",    },
			{ "bit_set", },
			{ "cast",    },
		},
	}
	return send_message(response)
}

Text_Document_Position_Params :: struct {
	textDocument: Text_Document_Identifier,
	position:     Position,
}

Hover_Params :: struct {
	using _: Text_Document_Position_Params,
}

MarkupKind :: distinct string

MarkupContent :: struct {
	kind:  MarkupKind,
	value: string,
}

Hover_Result :: struct {
	contents: MarkupContent,
	range:    Maybe(Range),
}

request_hover :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Hover_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	position           := params.position
	position.line      += 1
	position.character += 1

	node := hovered_node_in_block(state.ast, position)

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
			value = text,
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

request_definition :: proc(state: ^State, content: []byte) -> Error {
	request: Request(Definition_Params)
	json.unmarshal(content, &request, allocator = context.temp_allocator) or_return
	params := request.params

	position           := params.position
	position.line      += 1
	position.character += 1

	node := hovered_node_in_block(state.ast, position)

	response: Response = {
		id = request.id,
	}

	if node == nil {
		return send_message(response)
	}

	response.result = Location {
		uri   = params.textDocument.uri,
		range = {
			start = covert_position_to_lsp(node.start),
			end   = covert_position_to_lsp(node.end),
		},
	}

	return send_message(response)
}

covert_position_to_lsp :: proc(location: hep.Location) -> Position {
	return {
		line      = location.line - 1,
		character = location.column - 1,
	}
}
