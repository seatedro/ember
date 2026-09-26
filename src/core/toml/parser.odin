#+private
package toml

import "base:intrinsics"
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

// How a table that headers or dotted keys can still reach came to exist,
// which decides what may add to it.
Definition :: enum u8 {
	// A parent named on the way to a [header]. A later [header] may define it.
	Implicit,
	// Named by its own [header].
	Header,
	// Created by a dotted key. Only dotted keys in the same section may add to it.
	Dotted,
	// An array made by [[header]]. Its place's id names its last element.
	Array_Of_Tables,
}

// Tables that arrived whole, as inline tables or inside arrays, get no place,
// and having no place is what keeps them closed.
Place :: struct {
	id:         u32,
	definition: Definition,
}

Parser :: struct {
	data:       string,
	pos:        int,
	root:       ^Table,
	current:    ^Table,
	current_id: u32,
	// places[id] maps keys of the table with that id to their places; the
	// root's id is 0. It lives in scratch and dies with the parse.
	places:     [dynamic]map[string]Place,
	scratch:    runtime.Allocator,
	keys:       [dynamic]string,
	depth:      int,
	error:      Error,
}

parse_document :: proc(data: string, allocator := context.allocator) -> (^Document, Error) {
	if bad := first_invalid_utf8(data); bad >= 0 {
		return nil, error_at(data, .Invalid_Encoding, bad)
	}

	document, err := new(Document, allocator)
	if err != nil {
		return nil, {kind = .Allocation_Failed}
	}
	scratch: runtime.Arena
	if runtime.arena_init(&document.arena, uint(len(data)), allocator) != nil ||
	   runtime.arena_init(&scratch, 0, allocator) != nil {
		runtime.arena_destroy(&document.arena)
		free(document, allocator)
		return nil, {kind = .Allocation_Failed}
	}
	defer runtime.arena_destroy(&scratch)

	p := Parser {
		data    = data,
		root    = &document.root,
		current = &document.root,
		scratch = runtime.arena_allocator(&scratch),
	}
	context.allocator = runtime.arena_allocator(&document.arena)
	if _, root_ok := new_id(&p); !root_ok || !parse_lines(&p) {
		destroy(document)
		return nil, p.error
	}
	return document, {}
}

parse_lines :: proc(p: ^Parser) -> bool {
	// The spec allows no byte order mark, but editors write one; skip it.
	if strings.has_prefix(p.data, "\uFEFF") {
		p.pos = len("\uFEFF")
	}

	for p.pos < len(p.data) {
		skip_whitespace(p)
		switch peek(p) {
		case '#', '\n', '\r', 0:
		case '[':
			parse_header(p) or_return
		case:
			parse_keyval(p, p.current, p.current_id) or_return
		}

		end_line(p) or_return
	}
	return true
}

// Whitespace, an optional comment, then a newline or the end of the input.
end_line :: proc(p: ^Parser) -> bool {
	skip_whitespace(p)
	if peek(p) == '#' {
		skip_comment(p) or_return
	}

	if p.pos >= len(p.data) {
		return true
	}
	return skip_newline(p) || fail(p, .Unexpected_Character)
}

parse_header :: proc(p: ^Parser) -> bool {
	p.pos += 1
	array := peek(p) == '['
	if array {
		p.pos += 1
	}

	skip_whitespace(p)
	parse_key(p) or_return
	skip_whitespace(p)
	expect(p, ']') or_return
	if array {
		expect(p, ']') or_return
	}

	table, id := p.root, u32(0)
	for key in p.keys[:len(p.keys) - 1] {
		table, id = header_parent(p, table, id, key) or_return
	}

	name := p.keys[len(p.keys) - 1]
	value, inserted := entry(p, table, name) or_return
	place, known := find_place(p, id, name)
	if array {
		if inserted {
			value^ = empty_array()
			place.definition = .Array_Of_Tables
		} else if !known || place.definition != .Array_Of_Tables {
			return fail(p, .Invalid_Table)
		}

		elements := &value.(Array)
		if _, err := append(elements, empty_table()); err != nil {
			return fail(p, .Allocation_Failed)
		}
		place.id = new_id(p) or_return
		p.current, p.current_id = &elements[len(elements) - 1].(Table), place.id
		return set_place(p, id, name, place)
	}

	switch {
	case inserted:
		value^ = empty_table()
		place = {new_id(p) or_return, .Header}
	case !known || place.definition != .Implicit:
		return fail(p, .Invalid_Table)
	case:
		place.definition = .Header
	}
	p.current, p.current_id = &value.(Table), place.id
	return set_place(p, id, name, place)
}

// A table named on the way to a header's last key. An array of tables stands
// for its last element.
header_parent :: proc(
	p: ^Parser,
	table: ^Table,
	id: u32,
	key: string,
) -> (
	child: ^Table,
	child_id: u32,
	ok: bool,
) {
	value, inserted := entry(p, table, key) or_return
	if inserted {
		value^ = empty_table()
		child_id = new_id(p) or_return
		return &value.(Table), child_id, set_place(p, id, key, {child_id, .Implicit})
	}

	place, known := find_place(p, id, key)
	switch {
	case !known:
		return nil, 0, fail(p, .Invalid_Table)
	case place.definition == .Array_Of_Tables:
		elements := &value.(Array)
		return &elements[len(elements) - 1].(Table), place.id, true
	}
	return &value.(Table), place.id, true
}

parse_keyval :: proc(p: ^Parser, table: ^Table, id: u32) -> bool {
	start := p.pos
	parse_key(p) or_return

	target, target_id := table, id
	for key in p.keys[:len(p.keys) - 1] {
		target, target_id = dotted_parent(p, target, target_id, key) or_return
	}
	// A nested inline table reuses p.keys, so take the name out first.
	name := p.keys[len(p.keys) - 1]

	skip_whitespace(p)
	expect(p, '=') or_return
	skip_whitespace(p)
	value := parse_value(p) or_return

	slot, inserted := entry(p, target, name) or_return
	if !inserted {
		return fail(p, .Duplicate_Key, start)
	}
	slot^ = value
	return true
}

dotted_parent :: proc(
	p: ^Parser,
	table: ^Table,
	id: u32,
	key: string,
) -> (
	child: ^Table,
	child_id: u32,
	ok: bool,
) {
	value, inserted := entry(p, table, key) or_return
	if inserted {
		value^ = empty_table()
		child_id = new_id(p) or_return
		return &value.(Table), child_id, set_place(p, id, key, {child_id, .Dotted})
	}

	place, known := find_place(p, id, key)
	if known && place.definition == .Dotted {
		return &value.(Table), place.id, true
	}
	_, is_table := value.(Table)
	return nil, 0, fail(p, .Invalid_Table if known || is_table else .Duplicate_Key)
}

// Reads a possibly dotted key into p.keys.
parse_key :: proc(p: ^Parser) -> bool {
	clear(&p.keys)
	for {
		key := parse_simple_key(p) or_return
		if _, err := append(&p.keys, key); err != nil {
			return fail(p, .Allocation_Failed)
		}

		skip_whitespace(p)
		if peek(p) != '.' {
			return true
		}
		p.pos += 1
		skip_whitespace(p)
	}
}

// Keys point into the input until entry copies the ones it stores.
parse_simple_key :: proc(p: ^Parser) -> (text: string, ok: bool) {
	switch peek(p) {
	case '"':
		if strings.has_prefix(p.data[p.pos:], `"""`) {
			return "", fail(p, .Unexpected_Character)
		}
		return parse_basic_string(p)
	case '\'':
		if strings.has_prefix(p.data[p.pos:], "'''") {
			return "", fail(p, .Unexpected_Character)
		}
		return parse_literal_string(p)
	}

	start := p.pos
	for p.pos < len(p.data) && is_bare_key_char(p.data[p.pos]) {
		p.pos += 1
	}
	if p.pos == start {
		return "", fail_here(p)
	}
	return p.data[start:p.pos], true
}

parse_value :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	rest := p.data[p.pos:]
	switch peek(p) {
	case '"':
		if strings.has_prefix(rest, `"""`) {
			return parse_multiline_basic_string(p)
		}
		return own_string(p, parse_basic_string(p) or_return)
	case '\'':
		if strings.has_prefix(rest, "'''") {
			return parse_multiline_literal_string(p)
		}
		return own_string(p, parse_literal_string(p) or_return)
	case '[':
		return parse_array(p)
	case '{':
		return parse_inline_table(p)
	case 't':
		if strings.has_prefix(rest, "true") {
			p.pos += len("true")
			return true, true
		}
	case 'f':
		if strings.has_prefix(rest, "false") {
			p.pos += len("false")
			return false, true
		}
	case '0' ..= '9':
		if looks_like_date_time(rest) {
			return parse_date_time(p)
		}
		return parse_number(p)
	case '+', '-', 'i', 'n':
		return parse_number(p)
	}
	return nil, fail_here(p)
}

// A string that still points into the input is copied into the document.
own_string :: proc(p: ^Parser, s: string) -> (Value, bool) {
	input := uintptr(raw_data(p.data))
	at := uintptr(raw_data(s))
	if at < input || at >= input + uintptr(len(p.data)) {
		return s, true
	}

	copied, err := strings.clone(s)
	if err != nil {
		return nil, fail(p, .Allocation_Failed)
	}
	return copied, true
}

parse_array :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	enter(p) or_return
	defer p.depth -= 1
	p.pos += 1

	array := empty_array()
	for {
		skip_blank(p) or_return
		if peek(p) == ']' {
			p.pos += 1
			return array, true
		}

		element := parse_value(p) or_return
		if _, err := append(&array, element); err != nil {
			return nil, fail(p, .Allocation_Failed)
		}

		skip_blank(p) or_return
		switch peek(p) {
		case ',':
			p.pos += 1
		case ']':
			p.pos += 1
			return array, true
		case:
			return nil, fail_here(p)
		}
	}
}

// The table gets an id so dotted keys inside the braces can extend what they
// create, but no place, so nothing outside can.
parse_inline_table :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	enter(p) or_return
	defer p.depth -= 1
	p.pos += 1

	table := empty_table()
	id := new_id(p) or_return
	for {
		skip_blank(p) or_return
		if peek(p) == '}' {
			p.pos += 1
			return table, true
		}

		parse_keyval(p, &table, id) or_return
		skip_blank(p) or_return
		switch peek(p) {
		case ',':
			p.pos += 1
		case '}':
			p.pos += 1
			return table, true
		case:
			return nil, fail_here(p)
		}
	}
}

enter :: proc(p: ^Parser) -> bool {
	if p.depth >= MAX_DEPTH {
		return fail(p, .Too_Deep)
	}
	p.depth += 1
	return true
}

// Finds key in table, adding it if it's missing. A new key is copied into the
// document; lookups copy nothing.
entry :: proc(
	p: ^Parser,
	table: ^Table,
	key: string,
) -> (
	value: ^Value,
	inserted: bool,
	ok: bool,
) {
	key_ptr, value_ptr, just_inserted, err := map_entry(table, key)
	if err != nil {
		return nil, false, fail(p, .Allocation_Failed)
	}
	if just_inserted {
		copied, clone_err := strings.clone(key)
		if clone_err != nil {
			return nil, false, fail(p, .Allocation_Failed)
		}
		key_ptr^ = copied
	}
	return value_ptr, just_inserted, true
}

// Empty tables and arrays remember the arena, so entries added after parsing
// land in it too.
empty_table :: proc() -> Table {
	table: Table
	(^runtime.Raw_Map)(&table).allocator = context.allocator
	return table
}

empty_array :: proc() -> Array {
	array: Array
	(^runtime.Raw_Dynamic_Array)(&array).allocator = context.allocator
	return array
}

new_id :: proc(p: ^Parser) -> (u32, bool) {
	context.allocator = p.scratch
	if _, err := append(&p.places, nil); err != nil {
		return 0, fail(p, .Allocation_Failed)
	}
	return u32(len(p.places) - 1), true
}

find_place :: proc(p: ^Parser, id: u32, key: string) -> (Place, bool) {
	return p.places[id][key]
}

set_place :: proc(p: ^Parser, id: u32, key: string, place: Place) -> bool {
	context.allocator = p.scratch
	_, slot, _, err := map_entry(&p.places[id], key)
	if err != nil {
		return fail(p, .Allocation_Failed)
	}
	slot^ = place
	return true
}

skip_whitespace :: proc(p: ^Parser) {
	for p.pos < len(p.data) && (p.data[p.pos] == ' ' || p.data[p.pos] == '\t') {
		p.pos += 1
	}
}

// Whitespace, comments, and newlines, as allowed inside arrays and inline tables.
skip_blank :: proc(p: ^Parser) -> bool {
	for {
		skip_whitespace(p)
		switch peek(p) {
		case '#':
			skip_comment(p) or_return
		case '\n', '\r':
			skip_newline(p) or_return
		case:
			return true
		}
	}
}

skip_comment :: proc(p: ^Parser) -> bool {
	p.pos += 1
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		if c == '\n' || (c == '\r' && peek_at(p, 1) == '\n') {
			return true
		}
		if is_control(c) && c != '\t' {
			return fail(p, .Invalid_Encoding)
		}
		p.pos += 1
	}
	return true
}

skip_newline :: proc(p: ^Parser) -> bool {
	switch {
	case peek(p) == '\n':
		p.pos += 1
		return true
	case peek(p) == '\r' && peek_at(p, 1) == '\n':
		p.pos += 2
		return true
	case peek(p) == '\r':
		return fail(p, .Invalid_Encoding)
	}
	return false
}

expect :: proc(p: ^Parser, c: byte) -> bool {
	if peek(p) != c {
		return fail_here(p)
	}
	p.pos += 1
	return true
}

peek :: proc(p: ^Parser) -> byte {
	return peek_at(p, 0)
}

// 0 past the end. A 0 byte in the input is a control character, which every
// caller rejects on its own.
peek_at :: proc(p: ^Parser, offset: int) -> byte {
	i := p.pos + offset
	return p.data[i] if i < len(p.data) else 0
}

is_bare_key_char :: proc(c: byte) -> bool {
	switch c {
	case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '-', '_':
		return true
	}
	return false
}

is_control :: proc(c: byte) -> bool {
	return c < 0x20 || c == 0x7f
}

// Unexpected_End at the end of the input, Unexpected_Character before it.
fail_here :: proc(p: ^Parser) -> bool {
	return fail(p, .Unexpected_End if p.pos >= len(p.data) else .Unexpected_Character)
}

// Keeps the first error.
fail :: proc(p: ^Parser, kind: Error_Kind, pos := -1) -> bool {
	if p.error.kind == .None {
		p.error = error_at(p.data, kind, p.pos if pos < 0 else pos)
	}
	return false
}

error_at :: proc(data: string, kind: Error_Kind, pos: int) -> Error {
	if kind == .Allocation_Failed {
		return {kind = kind}
	}

	line_start := strings.last_index_byte(data[:pos], '\n') + 1
	return {
		kind = kind,
		line = strings.count(data[:pos], "\n") + 1,
		column = utf8.rune_count_in_string(data[line_start:pos]) + 1,
	}
}

first_invalid_utf8 :: proc(data: string) -> int {
	for i := 0; i < len(data); {
		// ASCII, eight bytes at a time.
		for i + 8 <= len(data) &&
		    intrinsics.unaligned_load((^u64)(raw_data(data[i:]))) & 0x8080_8080_8080_8080 == 0 {
			i += 8
		}
		if i >= len(data) {
			break
		}
		if data[i] < 0x80 {
			i += 1
			continue
		}

		r, size := utf8.decode_rune_in_string(data[i:])
		if r == utf8.RUNE_ERROR && size <= 1 {
			return i
		}
		i += size
	}
	return -1
}
