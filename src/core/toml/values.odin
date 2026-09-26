#+private
package toml

import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

parse_basic_string :: proc(p: ^Parser) -> (text: string, ok: bool) {
	p.pos += 1
	start := p.pos
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		switch {
		case c == '"':
			p.pos += 1
			return p.data[start:p.pos - 1], true
		case c == '\\':
			// Copy only once an escape shows up.
			builder := strings.builder_make()
			strings.write_string(&builder, p.data[start:p.pos])
			return finish_basic_string(p, &builder)
		case is_control(c) && c != '\t':
			return "", fail_string_character(p)
		}
		p.pos += 1
	}
	return "", fail(p, .Unexpected_End)
}

finish_basic_string :: proc(p: ^Parser, builder: ^strings.Builder) -> (text: string, ok: bool) {
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		switch {
		case c == '"':
			p.pos += 1
			return strings.to_string(builder^), true
		case c == '\\':
			write_escape(p, builder) or_return
			continue
		case is_control(c) && c != '\t':
			return "", fail_string_character(p)
		}
		strings.write_byte(builder, c)
		p.pos += 1
	}
	return "", fail(p, .Unexpected_End)
}

// Opening `"""`, an optional newline right after it, then the body.
parse_multiline_basic_string :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	p.pos += 3
	skip_newline(p)
	builder := strings.builder_make()
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		switch {
		case c == '"':
			quotes := count_run(p, '"')
			if quotes >= 3 {
				return close_multiline(p, &builder, quotes, '"')
			}
			strings.write_string(&builder, p.data[p.pos:p.pos + quotes])
			p.pos += quotes
		case c == '\\' && at_line_ending_backslash(p):
			p.pos += 1
			skip_whitespace(p)
			skip_newline(p) or_return
			skip_multiline_blank(p) or_return
		case c == '\\':
			write_escape(p, &builder) or_return
		case c == '\n' || c == '\r':
			skip_newline(p) or_return
			strings.write_byte(&builder, '\n')
		case is_control(c) && c != '\t':
			return nil, fail(p, .Invalid_Encoding)
		case:
			strings.write_byte(&builder, c)
			p.pos += 1
		}
	}
	return nil, fail(p, .Unexpected_End)
}

parse_literal_string :: proc(p: ^Parser) -> (text: string, ok: bool) {
	p.pos += 1
	start := p.pos
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		if c == '\'' {
			p.pos += 1
			return p.data[start:p.pos - 1], true
		}
		if is_control(c) && c != '\t' {
			return "", fail_string_character(p)
		}
		p.pos += 1
	}
	return "", fail(p, .Unexpected_End)
}

parse_multiline_literal_string :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	p.pos += 3
	skip_newline(p)
	builder := strings.builder_make()
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		switch {
		case c == '\'':
			quotes := count_run(p, '\'')
			if quotes >= 3 {
				return close_multiline(p, &builder, quotes, '\'')
			}
			strings.write_string(&builder, p.data[p.pos:p.pos + quotes])
			p.pos += quotes
		case c == '\n' || c == '\r':
			skip_newline(p) or_return
			strings.write_byte(&builder, '\n')
		case is_control(c) && c != '\t':
			return nil, fail(p, .Invalid_Encoding)
		case:
			strings.write_byte(&builder, c)
			p.pos += 1
		}
	}
	return nil, fail(p, .Unexpected_End)
}

// Up to two quotes may end the body just before the closing three.
close_multiline :: proc(
	p: ^Parser,
	builder: ^strings.Builder,
	quotes: int,
	quote: byte,
) -> (
	value: Value,
	ok: bool,
) {
	if quotes > 5 {
		p.pos += 5
		return nil, fail(p, .Unexpected_Character)
	}
	for _ in 0 ..< quotes - 3 {
		strings.write_byte(builder, quote)
	}
	p.pos += quotes
	return strings.to_string(builder^), true
}

count_run :: proc(p: ^Parser, c: byte) -> int {
	n := 0
	for p.pos + n < len(p.data) && p.data[p.pos + n] == c {
		n += 1
	}
	return n
}

// A backslash followed by optional whitespace and a newline.
at_line_ending_backslash :: proc(p: ^Parser) -> bool {
	i := p.pos + 1
	for i < len(p.data) && (p.data[i] == ' ' || p.data[i] == '\t') {
		i += 1
	}
	return i < len(p.data) && (p.data[i] == '\n' || p.data[i] == '\r')
}

skip_multiline_blank :: proc(p: ^Parser) -> bool {
	for {
		skip_whitespace(p)
		if peek(p) != '\n' && peek(p) != '\r' {
			return true
		}
		skip_newline(p) or_return
	}
}

write_escape :: proc(p: ^Parser, builder: ^strings.Builder) -> bool {
	escape_pos := p.pos
	p.pos += 1
	c := peek(p)
	p.pos += 1
	switch c {
	case '"':
		strings.write_byte(builder, '"')
	case '\\':
		strings.write_byte(builder, '\\')
	case 'b':
		strings.write_byte(builder, '\b')
	case 'e':
		strings.write_byte(builder, 0x1b)
	case 'f':
		strings.write_byte(builder, '\f')
	case 'n':
		strings.write_byte(builder, '\n')
	case 'r':
		strings.write_byte(builder, '\r')
	case 't':
		strings.write_byte(builder, '\t')
	case 'x', 'u', 'U':
		digits := 2 if c == 'x' else (4 if c == 'u' else 8)
		code, ok := parse_hex(p.data[p.pos:], digits)
		if !ok || code > utf8.MAX_RUNE || (code >= 0xd800 && code <= 0xdfff) {
			return fail(p, .Invalid_Escape, escape_pos)
		}
		strings.write_rune(builder, rune(code))
		p.pos += digits
	case:
		return fail(p, .Invalid_Escape, escape_pos)
	}
	return true
}

parse_hex :: proc(s: string, digits: int) -> (value: u32, ok: bool) {
	if len(s) < digits {
		return 0, false
	}
	for c in transmute([]byte)s[:digits] {
		d := digit_value(c)
		if d >= 16 {
			return 0, false
		}
		value = value * 16 + u32(d)
	}
	return value, true
}

// A newline ends a single-line string too early; other control characters
// are encoding errors.
fail_string_character :: proc(p: ^Parser) -> bool {
	c := p.data[p.pos]
	return fail(p, .Unexpected_Character if c == '\n' || c == '\r' else .Invalid_Encoding)
}

parse_number :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	start := p.pos
	signed := peek(p) == '+' || peek(p) == '-'
	if signed {
		p.pos += 1
	}

	rest := p.data[p.pos:]
	switch {
	case strings.has_prefix(rest, "inf"):
		p.pos += 3
		return math.inf_f64(-1 if p.data[start] == '-' else 1), true
	case strings.has_prefix(rest, "nan"):
		p.pos += 3
		return math.nan_f64(), true
	case len(rest) >= 2 && rest[0] == '0' && (rest[1] == 'x' || rest[1] == 'o' || rest[1] == 'b'):
		if signed {
			return nil, fail(p, .Invalid_Number, start)
		}
		radix := 16 if rest[1] == 'x' else (8 if rest[1] == 'o' else 2)
		p.pos += 2
		digits_start := p.pos
		scan_digits(p, radix) or_return
		return integer_value(p, start, p.data[digits_start:p.pos], radix)
	}

	integer_start := p.pos
	scan_digits(p, 10) or_return
	if p.data[integer_start] == '0' && p.pos - integer_start > 1 {
		return nil, fail(p, .Invalid_Number, start)
	}

	is_float := false
	if peek(p) == '.' {
		p.pos += 1
		scan_digits(p, 10) or_return
		is_float = true
	}
	if peek(p) == 'e' || peek(p) == 'E' {
		p.pos += 1
		if peek(p) == '+' || peek(p) == '-' {
			p.pos += 1
		}
		scan_digits(p, 10) or_return
		is_float = true
	}

	if !is_float {
		return integer_value(p, start, p.data[integer_start:p.pos], 10)
	}
	return parse_float(p, start)
}

// DIGIT *( DIGIT / "_" DIGIT ) in the given radix.
scan_digits :: proc(p: ^Parser, radix: int) -> bool {
	if digit_value(peek(p)) >= radix {
		return fail_number(p)
	}
	p.pos += 1
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		switch {
		case c == '_':
			if digit_value(peek_at(p, 1)) >= radix {
				return fail_number(p)
			}
			p.pos += 2
		case digit_value(c) < radix:
			p.pos += 1
		case:
			return true
		}
	}
	return true
}

// Past the end, the number was cut off; before it, the character is wrong.
fail_number :: proc(p: ^Parser) -> bool {
	return fail(p, .Unexpected_End if p.pos >= len(p.data) else .Invalid_Number)
}

// digits have been scanned; start is where the number began, sign included.
integer_value :: proc(p: ^Parser, start: int, digits: string, radix: int) -> (Value, bool) {
	negative := p.data[start] == '-'
	limit := u64(max(i64)) + (1 if negative else 0)
	magnitude: u64
	for c in transmute([]byte)digits {
		if c == '_' {
			continue
		}
		d := u64(digit_value(c))
		if magnitude > (limit - d) / u64(radix) {
			return nil, fail(p, .Number_Out_Of_Range, start)
		}
		magnitude = magnitude * u64(radix) + d
	}

	if negative {
		return i64(-i128(magnitude)), true
	}
	return i64(magnitude), true
}

parse_float :: proc(p: ^Parser, start: int) -> (Value, bool) {
	text := p.data[start:p.pos]
	if strings.index_byte(text, '_') >= 0 {
		text, _ = strings.remove_all(text, "_")
	}

	value, parsed := strconv.parse_f64(text)
	if !parsed {
		return nil, fail(p, .Number_Out_Of_Range, start)
	}
	return value, true
}

digit_value :: proc(c: byte) -> int {
	switch c {
	case '0' ..= '9':
		return int(c - '0')
	case 'a' ..= 'f':
		return int(c - 'a') + 10
	case 'A' ..= 'F':
		return int(c - 'A') + 10
	}
	return 16
}

// A value starting YYYY- or HH: is a date or time, not a number.
looks_like_date_time :: proc(s: string) -> bool {
	digits :: proc(s: string, n: int) -> bool {
		if len(s) < n {
			return false
		}
		for c in transmute([]byte)s[:n] {
			if c < '0' || c > '9' {
				return false
			}
		}
		return true
	}

	return(
		(digits(s, 4) && len(s) > 4 && s[4] == '-') ||
		(digits(s, 2) && len(s) > 2 && s[2] == ':') \
	)
}

parse_date_time :: proc(p: ^Parser) -> (value: Value, ok: bool) {
	start := p.pos
	if p.data[p.pos + 2] == ':' {
		time := parse_time(p, start) or_return
		return time, true
	}

	date := parse_date(p, start) or_return
	switch peek(p) {
	case 'T', 't':
		p.pos += 1
	case ' ':
		// A space starts a time only if one follows; otherwise it's just a date.
		if !looks_like_date_time(p.data[p.pos + 1:]) {
			return date, true
		}
		p.pos += 1
	case:
		return date, true
	}

	time := parse_time(p, start) or_return
	switch peek(p) {
	case 'Z', 'z':
		p.pos += 1
		return Offset_Date_Time{date = date, time = time}, true
	case '+', '-':
		negative := peek(p) == '-'
		p.pos += 1
		hour := parse_two_digits(p, start) or_return
		expect_date_time(p, ':', start) or_return
		minute := parse_two_digits(p, start) or_return
		if hour > 23 || minute > 59 {
			return nil, fail(p, .Invalid_Date_Time, start)
		}
		offset := hour * 60 + minute
		return Offset_Date_Time {
				date = date,
				time = time,
				offset_minutes = -offset if negative else offset,
			},
			true
	}
	return Local_Date_Time{date = date, time = time}, true
}

parse_date :: proc(p: ^Parser, start: int) -> (result: Local_Date, ok: bool) {
	year := parse_two_digits(p, start) or_return
	year = year * 100 + (parse_two_digits(p, start) or_return)
	expect_date_time(p, '-', start) or_return
	month := parse_two_digits(p, start) or_return
	expect_date_time(p, '-', start) or_return
	day := parse_two_digits(p, start) or_return

	if month < 1 || month > 12 || day < 1 || day > days_in_month(year, month) {
		return {}, fail(p, .Invalid_Date_Time, start)
	}
	return {year, month, day}, true
}

// Seconds are optional since TOML 1.1; a fraction needs seconds before it.
parse_time :: proc(p: ^Parser, start: int) -> (result: Local_Time, ok: bool) {
	time: Local_Time
	time.hour = parse_two_digits(p, start) or_return
	expect_date_time(p, ':', start) or_return
	time.minute = parse_two_digits(p, start) or_return
	if peek(p) == ':' {
		p.pos += 1
		time.second = parse_two_digits(p, start) or_return
		if peek(p) == '.' {
			p.pos += 1
			fraction_start := p.pos
			for peek(p) >= '0' && peek(p) <= '9' {
				if p.pos - fraction_start < 9 {
					time.nanosecond = time.nanosecond * 10 + int(peek(p) - '0')
				}
				p.pos += 1
			}
			digits := p.pos - fraction_start
			if digits == 0 {
				return {}, fail(p, .Invalid_Date_Time, start)
			}
			for _ in digits ..< 9 {
				time.nanosecond *= 10
			}
		}
	}

	// 60 allows a leap second, as RFC 3339 does.
	if time.hour > 23 || time.minute > 59 || time.second > 60 {
		return {}, fail(p, .Invalid_Date_Time, start)
	}
	return time, true
}

parse_two_digits :: proc(p: ^Parser, start: int) -> (value: int, ok: bool) {
	a, b := peek(p), peek_at(p, 1)
	if a < '0' || a > '9' || b < '0' || b > '9' {
		return 0, fail(p, .Invalid_Date_Time, start)
	}
	p.pos += 2
	return int(a - '0') * 10 + int(b - '0'), true
}

expect_date_time :: proc(p: ^Parser, c: byte, start: int) -> bool {
	if peek(p) != c {
		return fail(p, .Invalid_Date_Time, start)
	}
	p.pos += 1
	return true
}

days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 2:
		leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
		return 29 if leap else 28
	case 4, 6, 9, 11:
		return 30
	}
	return 31
}
