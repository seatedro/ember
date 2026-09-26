// Decoder for the toml-test suite (https://github.com/toml-lang/toml-test):
// reads TOML on stdin, writes its tagged JSON form on stdout, and exits 1 on
// invalid input.
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "ember:core/toml"

main :: proc() {
	data, read_error := os.read_entire_file(os.stdin, context.allocator)
	if read_error != nil {
		fmt.eprintln("read stdin:", read_error)
		os.exit(1)
	}

	document, err := toml.parse(data)
	if err.kind != .None {
		fmt.eprintfln("%d:%d: %v", err.line, err.column, err.kind)
		os.exit(1)
	}

	builder := strings.builder_make()
	write_table(&builder, document.root)
	os.write_string(os.stdout, strings.to_string(builder))
}

write_table :: proc(b: ^strings.Builder, table: toml.Table) {
	strings.write_byte(b, '{')
	first := true
	for key, value in table {
		if !first {
			strings.write_byte(b, ',')
		}
		first = false
		write_json_string(b, key)
		strings.write_byte(b, ':')
		write_value(b, value)
	}
	strings.write_byte(b, '}')
}

write_value :: proc(b: ^strings.Builder, value: toml.Value) {
	switch v in value {
	case toml.Table:
		write_table(b, v)
	case toml.Array:
		strings.write_byte(b, '[')
		for element, i in v {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			write_value(b, element)
		}
		strings.write_byte(b, ']')
	case toml.String:
		write_tagged(b, "string", v)
	case toml.Integer:
		write_tagged(b, "integer", fmt.tprint(v))
	case toml.Float:
		write_tagged(b, "float", format_float(v))
	case toml.Boolean:
		write_tagged(b, "bool", "true" if v else "false")
	case toml.Offset_Date_Time:
		offset := "Z"
		if v.offset_minutes != 0 {
			sign := '-' if v.offset_minutes < 0 else '+'
			minutes := abs(v.offset_minutes)
			offset = fmt.tprintf("%c%02d:%02d", sign, minutes / 60, minutes % 60)
		}
		write_tagged(b, "datetime", fmt.tprintf("%sT%s%s", date(v.date), time(v.time), offset))
	case toml.Local_Date_Time:
		write_tagged(b, "datetime-local", fmt.tprintf("%sT%s", date(v.date), time(v.time)))
	case toml.Local_Date:
		write_tagged(b, "date-local", date(v))
	case toml.Local_Time:
		write_tagged(b, "time-local", time(v))
	case:
		strings.write_string(b, "null")
	}
}

format_float :: proc(f: f64) -> string {
	switch {
	case math.is_nan(f):
		return "nan"
	case math.is_inf(f, 1):
		return "inf"
	case math.is_inf(f, -1):
		return "-inf"
	}
	buffer := make([]byte, 32, context.temp_allocator)
	return strconv.write_float(buffer, f, 'g', -1, 64)
}

date :: proc(d: toml.Local_Date) -> string {
	return fmt.tprintf("%04d-%02d-%02d", d.year, d.month, d.day)
}

time :: proc(t: toml.Local_Time) -> string {
	text := fmt.tprintf("%02d:%02d:%02d", t.hour, t.minute, t.second)
	if t.nanosecond == 0 {
		return text
	}
	fraction := strings.trim_right(fmt.tprintf("%09d", t.nanosecond), "0")
	return fmt.tprintf("%s.%s", text, fraction)
}

write_tagged :: proc(b: ^strings.Builder, type, value: string) {
	strings.write_string(b, `{"type":`)
	write_json_string(b, type)
	strings.write_string(b, `,"value":`)
	write_json_string(b, value)
	strings.write_byte(b, '}')
}

write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for c in transmute([]byte)s {
		switch {
		case c == '"':
			strings.write_string(b, `\"`)
		case c == '\\':
			strings.write_string(b, `\\`)
		case c < 0x20 || c == 0x7f:
			fmt.sbprintf(b, `\u%04x`, c)
		case:
			strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
}
