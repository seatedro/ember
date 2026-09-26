package toml

import "base:runtime"

// TOML 1.1.0, https://toml.io/en/v1.1.0

Integer :: i64
Float :: f64
Boolean :: bool
// Multi-line strings keep their newlines as \n, whether the file used LF or CRLF.
String :: string

Local_Date :: struct {
	year, month, day: int,
}

// Precision below a nanosecond is truncated
Local_Time :: struct {
	hour, minute, second, nanosecond: int,
}

Local_Date_Time :: struct {
	date: Local_Date,
	time: Local_Time,
}

// A `Z` offset is 0 minutes.
Offset_Date_Time :: struct {
	date:           Local_Date,
	time:           Local_Time,
	offset_minutes: int,
}

Array :: distinct [dynamic]Value
Table :: distinct map[string]Value

Value :: union {
	String,
	Integer,
	Float,
	Boolean,
	Offset_Date_Time,
	Local_Date_Time,
	Local_Date,
	Local_Time,
	Array,
	Table,
}

Error_Kind :: enum {
	None,
	// Not UTF-8, or a control character where TOML allows none.
	Invalid_Encoding,
	Unexpected_Character,
	Unexpected_End,
	Invalid_Escape,
	Invalid_Number,
	Number_Out_Of_Range,
	Invalid_Date_Time,
	Duplicate_Key,
	// A table defined twice, or extended in a way TOML forbids.
	Invalid_Table,
	Too_Deep,
	Allocation_Failed,
}

// line and column start at 1; column counts characters.
// Allocation_Failed has no position.
Error :: struct {
	kind:         Error_Kind,
	line, column: int,
}

// Arrays and inline tables nest at most this deep.
MAX_DEPTH :: 128

// Every table, array, key, and string under root lives in the document's
// arena and is freed with it. Tables may be edited after parsing; new entries
// allocate from the same arena.
Document :: struct {
	root:  Table,
	arena: runtime.Arena,
}

parse :: proc {
	parse_bytes,
	parse_string,
}

parse_bytes :: proc(data: []byte, allocator := context.allocator) -> (^Document, Error) {
	return parse_string(string(data), allocator)
}

// The arena's blocks come from allocator. A failed parse frees everything it
// allocated before returning.
parse_string :: proc(data: string, allocator := context.allocator) -> (^Document, Error) {
	return parse_document(data, allocator)
}

destroy :: proc(document: ^Document) {
	allocator := document.arena.backing_allocator
	runtime.arena_destroy(&document.arena)
	free(document, allocator)
}
