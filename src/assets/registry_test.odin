package assets

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_parse_rejects_bad_files :: proc(t: ^testing.T) {
	entry :: proc(id, type, path: string) -> string {
		return fmt.tprintf("[[asset]]\nid = %q\ntype = %q\npath = %q\n", id, type, path)
	}
	file :: proc(entries: ..string) -> string {
		return strings.concatenate(
			{"version = 1\n", strings.concatenate(entries, context.temp_allocator)},
			context.temp_allocator,
		)
	}
	good := entry("6f3a9c2e81d4b705", "model", "models/a.glb")

	cases := []struct {
		text:  string,
		error: Error,
	} {
		{
			"version = 1\nasset = [",
			{kind = .Syntax, syntax = {kind = .Unexpected_End, line = 2, column = 10}},
		},
		{"version = 2\n", {kind = .Unsupported_Version}},
		{good, {kind = .Unsupported_Version}},
		{"version = 1\nextra = true\n", {kind = .Invalid_Entry}},
		{
			"version = 1\n[[asset]]\nid = '6f3a9c2e81d4b705'\ntype = 'model'\n",
			{kind = .Invalid_Entry, entry = 1},
		},
		{file(entry("6F3A9C2E81D4B705", "model", "a.glb")), {kind = .Invalid_ID, entry = 1}},
		{file(entry("0000000000000000", "model", "a.glb")), {kind = .Invalid_ID, entry = 1}},
		{file(entry("6f3a9c2e81d4b70", "model", "a.glb")), {kind = .Invalid_ID, entry = 1}},
		{file(entry("6f3a9c2e81d4b705", "mesh", "a.glb")), {kind = .Unknown_Type, entry = 1}},
		{
			file(good, entry("6f3a9c2e81d4b705", "model", "models/b.glb")),
			{kind = .Duplicate_ID, entry = 2},
		},
		{
			file(good, entry("a1c07e5d93f2468b", "model", "models/a.glb")),
			{kind = .Duplicate_Path, entry = 2},
		},
	}
	for c in cases {
		registry, err := parse(c.text)
		testing.expectf(t, err == c.error, "%q: got %v, want %v", c.text, err, c.error)
		testing.expect(t, len(registry.entries) == 0)
	}

	for path in ([]string {
			"",
			"/abs.glb",
			"../up.glb",
			"a/./b.glb",
			"a//b.glb",
			"a\\b.glb",
			"dir/",
		}) {
		testing.expectf(t, !valid_path(path), "%q accepted", path)
	}
}

@(test)
test_save_writes_sorted_text_that_loads_back :: proc(t: ^testing.T) {
	text :=
		"version = 1\n" +
		"\n[[asset]]\nid = \"a1c07e5d93f2468b\"\npath = \"models/astronaut.glb\"\ntype = \"model\"\n" +
		"\n[[asset]]\nid = \"6f3a9c2e81d4b705\"\npath = \"models/ship.glb\"\ntype = \"model\"\n"

	registry, err := parse(
		"version = 1\n" +
		"[[asset]]\ntype = 'model'\npath = 'models/ship.glb'\nid = '6f3a9c2e81d4b705'\n" +
		"[[asset]]\nid = 'a1c07e5d93f2468b'\npath = 'models/astronaut.glb'\ntype = 'model'\n",
	)
	defer destroy(&registry)
	testing.expect_value(t, err, Error{})

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	testing.expect_value(t, write(&b, registry), Error{})
	testing.expect_value(t, strings.to_string(b), text)

	id, found := find(registry, "models/astronaut.glb")
	testing.expect(t, found && id == 0xa1c07e5d93f2468b)
}

@(test)
test_add_rename_remove :: proc(t: ^testing.T) {
	registry := create()
	defer destroy(&registry)

	ids := make(map[Asset_ID]bool, context.temp_allocator)
	for i in 0 ..< 1000 {
		id, err := add(&registry, fmt.tprintf("models/m%d.glb", i), .Model)
		testing.expect_value(t, err, Error{})
		testing.expect(t, id != 0 && id not_in ids)
		ids[id] = true
		parsed, ok := parse_id(format_id(id))
		testing.expect(t, ok && parsed == id)
	}

	first, _ := find(registry, "models/m0.glb")
	_, duplicate := add(&registry, "models/m0.glb", .Model)
	testing.expect_value(t, duplicate.kind, Error_Kind.Duplicate_Path)
	testing.expect_value(
		t,
		rename(&registry, first, "models/m1.glb").kind,
		Error_Kind.Duplicate_Path,
	)
	testing.expect_value(t, rename(&registry, first, "models/renamed.glb"), Error{})
	renamed, found := find(registry, "models/renamed.glb")
	testing.expect(t, found && renamed == first)
	_, still_there := find(registry, "models/m0.glb")
	testing.expect(t, !still_there)

	testing.expect(t, remove(&registry, first))
	testing.expect(t, !remove(&registry, first))
	for i in 1 ..< 1000 {
		path := fmt.tprintf("models/m%d.glb", i)
		id, ok := find(registry, path)
		entry, _ := lookup(registry, id)
		testing.expectf(t, ok && entry.path == path, "%s lost after remove", path)
	}
}

@(test)
test_missing_files :: proc(t: ^testing.T) {
	root := fmt.tprintf("%s/ember-registry-test", os.get_env("TMPDIR", context.temp_allocator))
	testing.expect(t, os.make_directory_all(fmt.tprintf("%s/models", root)) == nil)
	defer os.remove_all(root)
	testing.expect(
		t,
		os.write_entire_file(fmt.tprintf("%s/models/here.glb", root), []byte{}) == nil,
	)

	registry := create()
	defer destroy(&registry)
	add(&registry, "models/here.glb", .Model)
	gone, _ := add(&registry, "models/gone.glb", .Model)

	missing, err := missing_files(registry, root)
	defer delete(missing)
	testing.expect_value(t, err, Error{})
	testing.expect(t, len(missing) == 1 && missing[0] == gone)
}
