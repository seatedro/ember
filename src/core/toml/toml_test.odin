package toml

import "core:math"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_error_position_counts_characters :: proc(t: ^testing.T) {
	_, err := parse_string("a = 1\nb = 2\na = 3\n")
	testing.expect_value(t, err, Error{kind = .Duplicate_Key, line = 3, column = 1})

	_, err = parse_string("name = \"héllo\" !")
	testing.expect_value(t, err, Error{kind = .Unexpected_Character, line = 1, column = 16})

	_, err = parse_string("a = \"abc")
	testing.expect_value(t, err.kind, Error_Kind.Unexpected_End)
}

@(test)
test_parse_leaves_nothing_allocated :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	_, err := parse_string("[a]\nx = [1, 2]\ns = 'text'\n[a]\n", allocator)
	testing.expect_value(t, err.kind, Error_Kind.Invalid_Table)
	testing.expect_value(t, len(tracking.allocation_map), 0)

	document, ok_err := parse_string("[a]\nx = [1, {y = \"z\\n\"}]\n[[b]]\n", allocator)
	testing.expect_value(t, ok_err.kind, Error_Kind.None)
	element := &document.root["b"].(Array)[0].(Table)
	element["added"] = "after parsing"
	destroy(document)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}

@(test)
test_integer_limits :: proc(t: ^testing.T) {
	document, err := parse_string(
		"max = 9_223_372_036_854_775_807\nmin = -9223372036854775808\nhex = 0x7fff_ffff_ffff_ffff",
	)
	defer destroy(document)
	testing.expect_value(t, err.kind, Error_Kind.None)
	testing.expect_value(t, document.root["max"].(Integer), max(i64))
	testing.expect_value(t, document.root["min"].(Integer), min(i64))
	testing.expect_value(t, document.root["hex"].(Integer), max(i64))

	for text in ([]string {
			"a = 9223372036854775808",
			"a = -9223372036854775809",
			"a = 0x8000000000000000",
			"a = 1e400",
		}) {
		_, overflow := parse_string(text)
		testing.expectf(t, overflow.kind == .Number_Out_Of_Range, "%q: %v", text, overflow)
	}
}

@(test)
test_float_values :: proc(t: ^testing.T) {
	document, err := parse_string("a = 0.1\nb = -0.0\nc = 6.626e-34\nd = 1_000.5e1_0")
	defer destroy(document)
	testing.expect_value(t, err.kind, Error_Kind.None)
	testing.expect_value(t, document.root["a"].(Float), 0.1)
	testing.expect(t, math.sign_bit(document.root["b"].(Float)))
	testing.expect_value(t, document.root["c"].(Float), 6.626e-34)
	testing.expect_value(t, document.root["d"].(Float), 1000.5e10)
}

@(test)
test_date_time_validation :: proc(t: ^testing.T) {
	document, err := parse_string("leap = 2024-02-29\nfine = 00:00:00.1234567899\nshort = 07:32")
	defer destroy(document)
	testing.expect_value(t, err.kind, Error_Kind.None)
	testing.expect_value(t, document.root["leap"].(Local_Date), Local_Date{2024, 2, 29})
	testing.expect_value(
		t,
		document.root["fine"].(Local_Time),
		Local_Time{nanosecond = 123_456_789},
	)
	testing.expect_value(t, document.root["short"].(Local_Time), Local_Time{hour = 7, minute = 32})

	for text in ([]string{"a = 2023-02-29", "a = 1900-02-29", "a = 24:00:00", "a = 07:32.5"}) {
		_, invalid := parse_string(text)
		testing.expectf(t, invalid.kind != .None, "%q parsed", text)
	}
}

@(test)
test_table_definition_rules :: proc(t: ^testing.T) {
	valid := []string {
		"[x.y.z.w]\n[x]\n",
		"[fruit]\napple.color = 'red'\n[fruit.apple.texture]\nsmooth = true\n",
		"[[a.b]]\nx = 1\n[a]\ny = 2\n",
	}
	for text in valid {
		document, err := parse_string(text)
		testing.expectf(t, err.kind == .None, "%q: %v", text, err)
		if document != nil {
			destroy(document)
		}
	}

	invalid := []string {
		"[fruit]\napple.color = 'red'\n[fruit.apple]\n",
		"[a.b.c]\nz = 9\n[a]\nb.c.t = 1\n",
		"[product]\ntype = { name = 'Nail' }\ntype.edible = false\n",
		"a = [{b = 1}]\n[[a]]\n",
		"[[a]]\n[a]\n",
	}
	for text in invalid {
		_, err := parse_string(text)
		testing.expectf(t, err.kind == .Invalid_Table, "%q: %v", text, err)
	}
}

@(test)
test_write_layout :: proc(t: ^testing.T) {
	document, err := parse_string(
		"version = 1\n" +
		"[[asset]]\npath = \"models/astronaut.glb\"\nid = \"6f3a9c2e81d4b705\"\n" +
		"[[asset]]\ntype = \"texture\"\nid = \"a1c07e5d93f2468b\"\n" +
		"[build.cache]\nroot = 'build/assets'\n" +
		"[\"odd key\"]\nlist = [1, {b = 2, a = 1}]\n",
	)
	defer destroy(document)
	testing.expect_value(t, err.kind, Error_Kind.None)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write(&builder, document.root), Write_Error.None)
	testing.expect_value(
		t,
		strings.to_string(builder),
		"version = 1\n" +
		"\n[build.cache]\nroot = \"build/assets\"\n" +
		"\n[\"odd key\"]\nlist = [1, { a = 1, b = 2 }]\n" +
		"\n[[asset]]\nid = \"6f3a9c2e81d4b705\"\npath = \"models/astronaut.glb\"\n" +
		"\n[[asset]]\nid = \"a1c07e5d93f2468b\"\ntype = \"texture\"\n",
	)
}

@(test)
test_write_floats_read_back_as_floats :: proc(t: ^testing.T) {
	table := make(Table)
	defer delete(table)
	table["whole"] = Float(300)
	table["negative_zero"] = math.copy_sign(f64(0), -1)
	table["tiny"] = Float(6.626e-34)
	table["infinite"] = math.inf_f64(-1)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write(&builder, table), Write_Error.None)
	testing.expect_value(
		t,
		strings.to_string(builder),
		"infinite = -inf\nnegative_zero = -0.0\ntiny = 6.626e-34\nwhole = 300.0\n",
	)
}

@(test)
test_write_rejects_what_toml_cannot_hold :: proc(t: ^testing.T) {
	cases := []struct {
		value: Value,
		error: Write_Error,
	} {
		{nil, .Empty_Value},
		{Local_Date{2023, 2, 29}, .Invalid_Date_Time},
		{Offset_Date_Time{date = {2024, 1, 1}, offset_minutes = 24 * 60}, .Invalid_Date_Time},
		{String("\xff"), .Invalid_Encoding},
	}
	for c in cases {
		table := make(Table)
		table["v"] = c.value
		builder := strings.builder_make()
		testing.expect_value(t, write(&builder, table), c.error)
		strings.builder_destroy(&builder)
		delete(table)
	}
}
