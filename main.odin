#+feature dynamic-literals
package hepls

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:encoding/json"

Error :: union {
	json.Unmarshal_Error,
	json.Marshal_Error,
}

state: struct {
	initialized: bool,
}

main :: proc() {
	log_file, err := os.open("log.txt", { .Create, .Read, .Write, .Trunc, }, os.Permissions_Default_File)
	if err != 0 {
		return
	}
	context.logger = log.create_file_logger(log_file, lowest = .Info)

	// TODO(Franz): (init doc-format)

	s: bufio.Scanner
	bufio.scanner_init(&s, io.to_reader(os.to_stream(os.stdin)))
	s.split = split

	for bufio.scanner_scan(&s) {
		text := bufio.scanner_bytes(&s)
		method, contents, ok := decode_message(text)
		if !ok {
			log.error("Failed to decode message")
			return
		}
		handle_message(method, contents)

		free_all(context.temp_allocator)
	}
}

handle_message :: proc(method: string, contents: []byte) {
	log.info(method)
	if fn, ok := requests_map[method]; ok {
		err := fn(contents)
		if err != nil {
			log.panic(method, err, string(contents))
		}
		return
	}
	
	log.error("Invalid method:", method)
}

send_buffer: strings.Builder

@(require_results)
send_message :: proc(data: $T) -> (error: Error) {
	data        := data
	data.jsonrpc = "2.0"

	content := json.marshal(data) or_return
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

requests_map := map[string]proc(contents: []byte) -> (error: Error) {
	"textDocument/didOpen"    = notification_did_open_text_document,
	"textDocument/didChange"  = notification_did_change_text_document,
	"textDocument/didSave"    = notification_did_save_text_document,
	// "textDocument/completion" = request_completion,
	"shutdown"                = notification_shutdown,
	"initialize"              = request_initialize,
	"initialized"             = notification_initialized,
	"exit"                    = request_exit,
}

@(require_results)
notification_initialized :: proc(contents: []byte) -> Error {
	return nil
}

@(require_results)
notification_did_open_text_document :: proc(contents: []byte) -> (error: Error) {
	notification: Notification(Did_Open_Text_Document_Params)
	json.unmarshal(contents, &notification) or_return
	params := notification.params

	return check_file(notification.params.textDocument.text, params.textDocument.uri)
}

@(require_results)
notification_did_change_text_document :: proc(content: []byte) -> (error: Error) {
	notification: Notification(Did_Change_Text_Document_Params)
	json.unmarshal(content, &notification) or_return
	params := notification.params

	return check_file(params.contentChanges[0].text, params.textDocument.uri)
}

@(require_results)
notification_did_save_text_document :: proc(content: []byte) -> (error: Error) {
	notification: Notification(Did_Save_Text_Document_Params)
	json.unmarshal(content, &notification) or_return
	params := notification.params

	text, ok := params.text.?
	if !ok {
		return nil
	}

	return check_file(text, notification.params.textDocument.uri)
}

notification_shutdown :: proc(_: []byte) -> (error: Error) {
	send_message(Base_Notification{ method = "shutdown", }) or_return
	os.exit(0)
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
request_initialize :: proc(contents: []byte) -> (error: Error) {
	request: Request(Initialize_Request_Params)
	json.unmarshal(contents, &request) or_return
	params := request.params

	log.info("Connected to", params.clientInfo.name, params.clientInfo.version)

	response := Response {
		id     = request.id,
		result = Initialize_Result {
			serverInfo  = Server_Info {
				name    = "hephaistos lsp",
				version = "0.0.1",
			},
			capabilities = { textDocumentSync = .Full, },
		},
	}
	return send_message(response)
}

request_exit :: proc(_: []byte) -> (error: Error) {
	os.exit(0)
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
}

Base_Response :: struct {
	jsonrpc: string,
	id:      Maybe(int),
}

Completion_Result :: []Completion_Item

Completion_Item :: struct {
	label: string,
}

import hep "hephaistos"

@(require_results)
check_file :: proc(source: string, uri: Uri) -> (error: Error) {
	errors := check_file_internal(source, context.temp_allocator)

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
check_file_internal :: proc(source: string, allocator := context.allocator) -> (errors: []hep.Error) {
	tokens: []hep.Token
	tokens, errors = hep.tokenize(source, false, allocator = context.temp_allocator, error_allocator = allocator)
	if len(errors) != 0 {
		return
	}

	stmts: []^hep.Ast_Stmt
	stmts, errors = hep.parse(tokens, allocator = context.temp_allocator, error_allocator = allocator)
	if len(errors) != 0 {
		return
	}

	checker: hep.Checker
	checker, errors = hep.check(
		stmts,
		defines         = {},
		types           = {},
		libraries       = {},
		flags           = {},
		allocator       = context.temp_allocator,
		error_allocator = allocator,
	)
	if len(errors) != 0 {
		return
	}

	return
}
