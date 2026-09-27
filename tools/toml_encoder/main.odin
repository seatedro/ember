// Encoder for the toml-test suite (https://github.com/toml-lang/toml-test):
// reads tagged JSON on stdin, writes it as TOML on stdout, and exits 1 on
// input it cannot encode.
//
// The JSON reader is local because core:encoding/json drops empty keys, which
// the suite uses. The suite's JSON holds only objects, arrays, and strings.
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf16"
import "ember:core/toml"

main :: proc() {
	data, read_error := os.read_entire_file(os.stdin, context.allocator)
	if read_error != nil {
		fmt.eprintln("read stdin:", read_error)
		os.exit(1)
	}

	reader := Reader {
		data = string(data),
	}
	value, ok := read_value(&reader)
	table, is_table := value.(toml.Table)
	if !ok || !is_table {
		fmt.eprintln("input is not a tagged table")
		os.exit(1)
	}

	builder := strings.builder_make()
	if err := toml.write(&builder, table); err != .None {
		fmt.eprintln("write:", err)
		os.exit(1)
	}
	os.write_string(os.stdout, strings.to_string(builder))
}

Reader :: struct {
	data: string,
	pos:  int,
}

read_value :: proc(r: ^Reader) -> (result: toml.Value, ok: bool) {
	skip_space(r)
	switch peek(r) {
	case '{':
		r.pos += 1
		table := make(toml.Table)
		for {
			skip_space(r)
			if peek(r) == '}' {
				r.pos += 1
				break
			}
			key := read_string(r) or_return
			skip_space(r)
			expect(r, ':') or_return
			table[key] = read_value(r) or_return
			skip_space(r)
			if peek(r) == ',' {
				r.pos += 1
			}
		}
		return untag(table)
	case '[':
		r.pos += 1
		array: toml.Array
		for {
			skip_space(r)
			if peek(r) == ']' {
				r.pos += 1
				return array, true
			}
			append(&array, read_value(r) or_return)
			skip_space(r)
			if peek(r) == ',' {
				r.pos += 1
			}
		}
	case '"':
		return read_string(r)
	}
	return nil, false
}

// A {"type", "value"} pair of strings is a scalar; any other object is a table.
untag :: proc(table: toml.Table) -> (toml.Value, bool) {
	type, has_type := table["type"].(toml.String)
	text, has_value := table["value"].(toml.String)
	if len(table) != 2 || !has_type || !has_value {
		return table, true
	}

	switch type {
	case "string":
		return text, true
	case "float":
		switch text {
		case "inf", "+inf":
			return math.inf_f64(1), true
		case "-inf":
			return math.inf_f64(-1), true
		case "nan", "+nan", "-nan":
			return math.nan_f64(), true
		}
		return strconv.parse_f64(text)
	case "integer", "bool", "datetime", "datetime-local", "date-local", "time-local":
		// These are written in TOML's own syntax, so the parser reads them.
		document, err := toml.parse(fmt.tprintf("v = %s", text))
		if err.kind != .None {
			return nil, false
		}
		return document.root["v"], true
	}
	return nil, false
}

read_string :: proc(r: ^Reader) -> (result: string, ok: bool) {
	expect(r, '"') or_return
	b := strings.builder_make()
	for r.pos < len(r.data) {
		c := r.data[r.pos]
		r.pos += 1
		switch c {
		case '"':
			return strings.to_string(b), true
		case '\\':
			escape := peek(r)
			r.pos += 1
			switch escape {
			case 'n':
				strings.write_byte(&b, '\n')
			case 't':
				strings.write_byte(&b, '\t')
			case 'r':
				strings.write_byte(&b, '\r')
			case 'b':
				strings.write_byte(&b, '\b')
			case 'f':
				strings.write_byte(&b, '\f')
			case 'u':
				code := read_hex4(r) or_return
				if utf16.is_surrogate(code) && strings.has_prefix(r.data[r.pos:], `\u`) {
					r.pos += 2
					low := read_hex4(r) or_return
					code = utf16.decode_surrogate_pair(code, low)
				}
				strings.write_rune(&b, code)
			case:
				strings.write_byte(&b, escape)
			}
		case:
			strings.write_byte(&b, c)
		}
	}
	return "", false
}

read_hex4 :: proc(r: ^Reader) -> (rune, bool) {
	if r.pos + 4 > len(r.data) {
		return 0, false
	}
	value, ok := strconv.parse_u64_of_base(r.data[r.pos:r.pos + 4], 16)
	r.pos += 4
	return rune(value), ok
}

skip_space :: proc(r: ^Reader) {
	for r.pos < len(r.data) && strings.is_space(rune(r.data[r.pos])) {
		r.pos += 1
	}
}

peek :: proc(r: ^Reader) -> byte {
	return r.data[r.pos] if r.pos < len(r.data) else 0
}

expect :: proc(r: ^Reader, c: byte) -> bool {
	if peek(r) != c {
		return false
	}
	r.pos += 1
	return true
}
