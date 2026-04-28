package hepls

import "core:bytes"
import "core:encoding/json"
import "core:strconv"
import "core:strings"

Base_Message :: struct {
	method: string,
}

decode_message :: proc(data: []byte) -> (
	method:   string,
	contents: []byte,
	ok:       bool,
) {
	header_len := bytes.index(data, []byte{'\r', '\n', '\r', '\n'})
	if header_len == -1 {
		return
	}

	header := string(data[:header_len])
	content_len: int

	for line in strings.split_lines_iterator(&header) {
		l := len("Content-Length: ")
		if len(line) > l && line[:l] == "Content-Length: " {
			content_len = strconv.parse_int(line[l:]) or_return
		}
	}

	contents = data[header_len + 4:]

	msg: Base_Message
	if err := json.unmarshal(contents, &msg, allocator = context.temp_allocator); err != nil {
		return
	}

	method = msg.method

	ok = len(contents) == content_len
	return
}

Response_Error :: struct {
	/**
	 * A number indicating the error type that occurred.
	 */
	code:    int,

	/**
	 * A string providing a short description of the error.
	 */
	message: string,

	/**
	 * A primitive or structured value that contains additional
	 * information about the error. Can be omitted.
	 */
	data:    any,
}

Error_Code :: enum {
	// Defined by JSON-RPC
	Parse_Error                        = -32700,
	Invalid_Request                    = -32600,
	Method_Not_Found                   = -32601,
	Invalid_Params                     = -32602,
	Internal_Error                     = -32603,

	/**
	 * This is the start range of JSON-RPC reserved error codes.
	 * It doesn't denote a real error code. No LSP error codes should
	 * be defined between the start and end range. For backwards
	 * compatibility the `ServerNotInitialized` and the `UnknownErrorCode`
	 * are left in the range.
	 *
	 * @since 3.16.0
	 */
	jsonrpc_Reserved_Error_Range_Start = -32099,
	/**
	 * Error code indicating that a server received a notification or
	 * request before the server has received the `initialize` request.
	 */
	Server_Not_Initialized             = -32002,
	Unknown_Error_Code                 = -32001,

	/**
	 * This is the end range of JSON-RPC reserved error codes.
	 * It doesn't denote a real error code.
	 *
	 * @since 3.16.0
	 */
	jsonrpc_Reserved_Error_Range_End   = -32000,

	/**
	 * This is the start range of LSP reserved error codes.
	 * It doesn't denote a real error code.
	 *
	 * @since 3.16.0
	 */
	lsp_Reserved_Error_Range_Start     = -32899,

	/**
	 * A request failed but it was syntactically correct, e.g the
	 * method name was known and the parameters were valid. The error
	 * message should contain human readable information about why
	 * the request failed.
	 *
	 * @since 3.17.0
	 */
	Request_Failed                     = -32803,

	/**
	 * The server cancelled the request. This error code should
	 * only be used for requests that explicitly support being
	 * server cancellable.
	 *
	 * @since 3.17.0
	 */
	Server_Cancelled                   = -32802,

	/**
	 * The server detected that the content of a document got
	 * modified outside normal conditions. A server should
	 * NOT send this error code if it detects a content change
	 * in it unprocessed messages. The result even computed
	 * on an older state might still be useful for the client.
	 *
	 * If a client decides that a result is not of any use anymore
	 * the client should cancel the request.
	 */
	Content_Modified                    = -32801,

	/**
	 * The client has canceled a request and a server as detected
	 * the cancel.
	 */
	Request_Cancelled                   = -32800,

	/**
	 * This is the end range of LSP reserved error codes.
	 * It doesn't denote a real error code.
	 *
	 * @since 3.16.0
	 */
	lsp_Reserved_Error_Range_End           = -32800,
}
