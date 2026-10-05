package toml

import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Write_Error :: enum {
	None,
	// A key or string that isn't UTF-8.
	Invalid_Encoding,
	// A date or time outside its calendar or clock range.
	Invalid_Date_Time,
	// A nil Value, which TOML cannot express.
	Empty_Value,
	Too_Deep,
}

// Keys are written in sorted order, so equal tables write equal text. Within a
// table, key/value pairs come first, then sub-tables as [sections], then
// arrays of tables as [[sections]]. A section is left implicit when its table
// holds only other sections. Arrays that mix tables with other values, and
// tables inside them, are written inline. On error the builder holds a
// partial document.
write :: proc(b: ^strings.Builder, table: Table) -> Write_Error {
	w := Writer {
		builder = b,
	}
	defer delete(w.path)
	return write_body(&w, table)
}

@(private = "file")
Writer :: struct {
	builder: ^strings.Builder,
	path:    [dynamic]string,
	depth:   int,
}

@(private = "file")
write_body :: proc(w: ^Writer, table: Table) -> Write_Error {
	keys := sorted_keys(table)
	defer delete(keys)
	for key in keys {
		value := table[key]
		if is_section(value) {
			continue
		}

		write_key(w, key) or_return
		strings.write_string(w.builder, " = ")
		write_inline(w, value) or_return
		strings.write_byte(w.builder, '\n')
	}

	for key in keys {
		child := table[key].(Table) or_continue
		append(&w.path, key)
		if has_pairs(child) || len(child) == 0 {
			write_header(w, "[", "]") or_return
		}
		write_body(w, child) or_return
		pop(&w.path)
	}

	for key in keys {
		elements := table[key].(Array) or_continue
		if !is_array_of_tables(elements) {
			continue
		}

		append(&w.path, key)
		for element in elements {
			write_header(w, "[[", "]]") or_return
			write_body(w, element.(Table)) or_return
		}
		pop(&w.path)
	}
	return .None
}

@(private = "file")
write_header :: proc(w: ^Writer, open, close: string) -> Write_Error {
	if strings.builder_len(w.builder^) > 0 {
		strings.write_byte(w.builder, '\n')
	}
	strings.write_string(w.builder, open)
	for key, i in w.path {
		if i > 0 {
			strings.write_byte(w.builder, '.')
		}
		write_key(w, key) or_return
	}
	strings.write_string(w.builder, close)
	strings.write_byte(w.builder, '\n')
	return .None
}

@(private = "file")
write_inline :: proc(w: ^Writer, value: Value) -> Write_Error {
	switch v in value {
	case String:
		return write_quoted(w, v)
	case Integer:
		strings.write_i64(w.builder, v)
	case Float:
		write_float(w, v)
	case Boolean:
		strings.write_string(w.builder, "true" if v else "false")
	case Offset_Date_Time:
		write_date(w, v.date) or_return
		strings.write_byte(w.builder, 'T')
		write_time(w, v.time) or_return
		return write_offset(w, v.offset_minutes)
	case Local_Date_Time:
		write_date(w, v.date) or_return
		strings.write_byte(w.builder, 'T')
		return write_time(w, v.time)
	case Local_Date:
		return write_date(w, v)
	case Local_Time:
		return write_time(w, v)
	case Array:
		return write_inline_array(w, v)
	case Table:
		return write_inline_table(w, v)
	case:
		return .Empty_Value
	}
	return .None
}

@(private = "file")
write_inline_array :: proc(w: ^Writer, array: Array) -> Write_Error {
	nest(w) or_return
	defer w.depth -= 1

	strings.write_byte(w.builder, '[')
	for element, i in array {
		if i > 0 {
			strings.write_string(w.builder, ", ")
		}
		write_inline(w, element) or_return
	}
	strings.write_byte(w.builder, ']')
	return .None
}

@(private = "file")
write_inline_table :: proc(w: ^Writer, table: Table) -> Write_Error {
	nest(w) or_return
	defer w.depth -= 1

	if len(table) == 0 {
		strings.write_string(w.builder, "{}")
		return .None
	}

	keys := sorted_keys(table)
	defer delete(keys)
	strings.write_string(w.builder, "{ ")
	for key, i in keys {
		if i > 0 {
			strings.write_string(w.builder, ", ")
		}
		write_key(w, key) or_return
		strings.write_string(w.builder, " = ")
		write_inline(w, table[key]) or_return
	}
	strings.write_string(w.builder, " }")
	return .None
}

@(private = "file")
nest :: proc(w: ^Writer) -> Write_Error {
	if w.depth >= MAX_DEPTH {
		return .Too_Deep
	}
	w.depth += 1
	return .None
}

@(private = "file")
write_key :: proc(w: ^Writer, key: string) -> Write_Error {
	if len(key) == 0 {
		strings.write_string(w.builder, `""`)
		return .None
	}
	for c in transmute([]byte)key {
		if !is_bare_key_char(c) {
			return write_quoted(w, key)
		}
	}
	strings.write_string(w.builder, key)
	return .None
}

// Control characters are written as \u escapes rather than 1.1's \e and \x, so
// TOML 1.0 readers accept the output too.
@(private = "file")
write_quoted :: proc(w: ^Writer, s: string) -> Write_Error {
	if !utf8.valid_string(s) {
		return .Invalid_Encoding
	}

	b := w.builder
	strings.write_byte(b, '"')
	for c in transmute([]byte)s {
		switch c {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\b':
			strings.write_string(b, `\b`)
		case '\t':
			strings.write_string(b, `\t`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\f':
			strings.write_string(b, `\f`)
		case '\r':
			strings.write_string(b, `\r`)
		case 0x00 ..= 0x1f, 0x7f:
			hex := "0123456789ABCDEF"
			strings.write_string(b, `\u00`)
			strings.write_byte(b, hex[c >> 4])
			strings.write_byte(b, hex[c & 0xf])
		case:
			strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
	return .None
}

// The shortest text that reads back as the same f64. A float always gets a
// '.' or an exponent so it doesn't read back as an integer.
@(private = "file")
write_float :: proc(w: ^Writer, f: f64) {
	switch {
	case math.is_nan(f):
		strings.write_string(w.builder, "nan")
		return
	case math.is_inf(f):
		strings.write_string(w.builder, "inf" if f > 0 else "-inf")
		return
	}

	buffer: [32]byte
	text := strings.trim_prefix(strconv.write_float(buffer[:], f, 'g', -1, 64), "+")
	strings.write_string(w.builder, text)
	if strings.index_any(text, ".e") < 0 {
		strings.write_string(w.builder, ".0")
	}
}

@(private = "file")
write_date :: proc(w: ^Writer, date: Local_Date) -> Write_Error {
	if date.year < 0 ||
	   date.year > 9999 ||
	   date.month < 1 ||
	   date.month > 12 ||
	   date.day < 1 ||
	   date.day > days_in_month(date.year, date.month) {
		return .Invalid_Date_Time
	}

	write_digits(w, date.year / 100)
	write_digits(w, date.year % 100)
	strings.write_byte(w.builder, '-')
	write_digits(w, date.month)
	strings.write_byte(w.builder, '-')
	write_digits(w, date.day)
	return .None
}

// Seconds are always written, which TOML 1.0 requires.
@(private = "file")
write_time :: proc(w: ^Writer, time: Local_Time) -> Write_Error {
	if time.hour < 0 ||
	   time.hour > 23 ||
	   time.minute < 0 ||
	   time.minute > 59 ||
	   time.second < 0 ||
	   time.second > 60 ||
	   time.nanosecond < 0 ||
	   time.nanosecond > 999_999_999 {
		return .Invalid_Date_Time
	}

	write_digits(w, time.hour)
	strings.write_byte(w.builder, ':')
	write_digits(w, time.minute)
	strings.write_byte(w.builder, ':')
	write_digits(w, time.second)
	if time.nanosecond == 0 {
		return .None
	}

	digits: [9]byte
	n := time.nanosecond
	for i := 8; i >= 0; i -= 1 {
		digits[i] = '0' + byte(n % 10)
		n /= 10
	}
	strings.write_byte(w.builder, '.')
	strings.write_string(w.builder, strings.trim_right(string(digits[:]), "0"))
	return .None
}

@(private = "file")
write_offset :: proc(w: ^Writer, minutes: int) -> Write_Error {
	if minutes == 0 {
		strings.write_byte(w.builder, 'Z')
		return .None
	}
	if abs(minutes) >= 24 * 60 {
		return .Invalid_Date_Time
	}

	strings.write_byte(w.builder, '-' if minutes < 0 else '+')
	write_digits(w, abs(minutes) / 60)
	strings.write_byte(w.builder, ':')
	write_digits(w, abs(minutes) % 60)
	return .None
}

@(private = "file")
write_digits :: proc(w: ^Writer, n: int) {
	strings.write_byte(w.builder, '0' + byte(n / 10))
	strings.write_byte(w.builder, '0' + byte(n % 10))
}

@(private = "file")
sorted_keys :: proc(table: Table) -> []string {
	keys := make([]string, len(table))
	i := 0
	for key in table {
		keys[i] = key
		i += 1
	}
	slice.sort(keys)
	return keys
}

@(private = "file")
is_section :: proc(value: Value) -> bool {
	#partial switch v in value {
	case Table:
		return true
	case Array:
		return is_array_of_tables(v)
	}
	return false
}

@(private = "file")
is_array_of_tables :: proc(array: Array) -> bool {
	if len(array) == 0 {
		return false
	}
	for element in array {
		if _, is_table := element.(Table); !is_table {
			return false
		}
	}
	return true
}

@(private = "file")
has_pairs :: proc(table: Table) -> bool {
	for _, value in table {
		if !is_section(value) {
			return true
		}
	}
	return false
}
