package assets

import "../core/toml"
import "core:crypto"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

REGISTRY_VERSION :: 1

// Random, and never 0. Written as 16 lowercase hex digits, since TOML integers
// are signed and would not hold IDs above 2^63.
Asset_ID :: distinct u64

Asset_Type :: enum u8 {
	// A .glb or .gltf file; its meshes, materials, and animations are named by
	// this ID plus their name.
	Model,
}

TYPE_NAMES := [Asset_Type]string {
	.Model = "model",
}

Entry :: struct {
	id:   Asset_ID,
	type: Asset_Type,
	path: string,
}

Registry :: struct {
	entries:   [dynamic]Entry,
	by_id:     map[Asset_ID]int,
	by_path:   map[string]int,
	allocator: mem.Allocator,
}

Error_Kind :: enum {
	None,
	Read_Failed,
	Write_Failed,
	Syntax,
	Unsupported_Version,
	Invalid_Entry,
	Invalid_ID,
	Invalid_Path,
	Unknown_Type,
	Duplicate_ID,
	Duplicate_Path,
	Not_Found,
	Allocation_Failed,
}

Error :: struct {
	kind:   Error_Kind,
	entry:  int,
	syntax: toml.Error,
}

create :: proc(allocator := context.allocator) -> Registry {
	return {
		entries = make([dynamic]Entry, allocator),
		by_id = make(map[Asset_ID]int, allocator),
		by_path = make(map[string]int, allocator),
		allocator = allocator,
	}
}

destroy :: proc(registry: ^Registry) {
	for entry in registry.entries {
		delete(entry.path, registry.allocator)
	}
	delete(registry.entries)
	delete(registry.by_id)
	delete(registry.by_path)
	registry^ = {}
}

load :: proc(path: string, allocator := context.allocator) -> (Registry, Error) {
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return {}, {kind = .Read_Failed}
	}
	defer delete(data, allocator)
	return parse(string(data), allocator)
}

parse :: proc(text: string, allocator := context.allocator) -> (Registry, Error) {
	document, syntax := toml.parse(text, allocator)
	if syntax.kind != .None {
		return {}, {kind = .Syntax, syntax = syntax}
	}
	defer toml.destroy(document)

	for key, value in document.root {
		switch key {
		case "version":
			if version, ok := value.(toml.Integer); !ok || version != REGISTRY_VERSION {
				return {}, {kind = .Unsupported_Version}
			}
		case "asset":
			if _, ok := value.(toml.Array); !ok {
				return {}, {kind = .Invalid_Entry}
			}
		case:
			return {}, {kind = .Invalid_Entry}
		}
	}
	if "version" not_in document.root {
		return {}, {kind = .Unsupported_Version}
	}

	registry := create(allocator)
	assets, _ := document.root["asset"].(toml.Array)
	for value, i in assets {
		entry, err := parse_entry(value)
		if err == .None {
			err = insert(&registry, entry)
		}
		if err != .None {
			destroy(&registry)
			return {}, {kind = err, entry = i + 1}
		}
	}
	return registry, {}
}

@(private)
parse_entry :: proc(value: toml.Value) -> (Entry, Error_Kind) {
	table, is_table := value.(toml.Table)
	if !is_table || len(table) != 3 {
		return {}, .Invalid_Entry
	}
	id_text, has_id := table["id"].(toml.String)
	type_name, has_type := table["type"].(toml.String)
	path, has_path := table["path"].(toml.String)
	if !has_id || !has_type || !has_path {
		return {}, .Invalid_Entry
	}

	id, id_ok := parse_id(id_text)
	if !id_ok {
		return {}, .Invalid_ID
	}
	type, type_ok := parse_type(type_name)
	if !type_ok {
		return {}, .Unknown_Type
	}
	return {id = id, type = type, path = path}, .None
}

write :: proc(b: ^strings.Builder, registry: Registry) -> Error {
	entries := slice.clone(registry.entries[:], context.temp_allocator)
	slice.sort_by(entries, proc(a, b: Entry) -> bool {
		return a.path < b.path
	})

	assets := make(toml.Array, 0, len(entries), context.temp_allocator)
	for entry in entries {
		table := make(toml.Table, 3, context.temp_allocator)
		table["id"] = format_id(entry.id)
		table["type"] = TYPE_NAMES[entry.type]
		table["path"] = entry.path
		append(&assets, table)
	}

	root := make(toml.Table, 2, context.temp_allocator)
	root["version"] = toml.Integer(REGISTRY_VERSION)
	if len(assets) > 0 {
		root["asset"] = assets
	}
	if toml.write(b, root) != .None {
		return {kind = .Write_Failed}
	}
	return {}
}

save :: proc(registry: Registry, path: string) -> Error {
	b := strings.builder_make(context.temp_allocator)
	if err := write(&b, registry); err.kind != .None {
		return err
	}

	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, transmute([]byte)strings.to_string(b)) != nil {
		return {kind = .Write_Failed}
	}
	if os.rename(temporary, path) != nil {
		os.remove(temporary)
		return {kind = .Write_Failed}
	}
	return {}
}

// Gives path a new random ID.
add :: proc(registry: ^Registry, path: string, type: Asset_Type) -> (Asset_ID, Error) {
	if !valid_path(path) {
		return 0, {kind = .Invalid_Path}
	}
	if path in registry.by_path {
		return 0, {kind = .Duplicate_Path}
	}

	id := new_id()
	for {
		if id not_in registry.by_id {
			break
		}
		id = new_id()
	}
	if kind := insert(registry, {id = id, type = type, path = path}); kind != .None {
		return 0, {kind = kind}
	}
	return id, {}
}

rename :: proc(registry: ^Registry, id: Asset_ID, path: string) -> Error {
	index, found := registry.by_id[id]
	if !found {
		return {kind = .Not_Found}
	}
	if registry.entries[index].path == path {
		return {}
	}
	if !valid_path(path) {
		return {kind = .Invalid_Path}
	}
	if path in registry.by_path {
		return {kind = .Duplicate_Path}
	}

	owned, err := strings.clone(path, registry.allocator)
	if err != nil {
		return {kind = .Allocation_Failed}
	}
	entry := &registry.entries[index]
	delete_key(&registry.by_path, entry.path)
	delete(entry.path, registry.allocator)
	entry.path = owned
	registry.by_path[owned] = index
	return {}
}

remove :: proc(registry: ^Registry, id: Asset_ID) -> bool {
	index, found := registry.by_id[id]
	if !found {
		return false
	}

	entry := registry.entries[index]
	delete_key(&registry.by_id, id)
	delete_key(&registry.by_path, entry.path)
	delete(entry.path, registry.allocator)

	last := len(registry.entries) - 1
	if index != last {
		moved := registry.entries[last]
		registry.entries[index] = moved
		registry.by_id[moved.id] = index
		registry.by_path[moved.path] = index
	}
	pop(&registry.entries)
	return true
}

find :: proc(registry: Registry, path: string) -> (Asset_ID, bool) {
	index, found := registry.by_path[path]
	if !found {
		return 0, false
	}
	return registry.entries[index].id, true
}

lookup :: proc(registry: Registry, id: Asset_ID) -> (Entry, bool) {
	index, found := registry.by_id[id]
	if !found {
		return {}, false
	}
	return registry.entries[index], true
}

// Entries whose file is gone from root, usually because it was moved or
// renamed outside the tools.
missing_files :: proc(
	registry: Registry,
	root: string,
	allocator := context.allocator,
) -> (
	[]Asset_ID,
	Error,
) {
	missing := make([dynamic]Asset_ID, allocator)
	for entry in registry.entries {
		full := fmt.tprintf("%s/%s", root, entry.path)
		if os.is_file(full) {
			continue
		}
		if _, err := append(&missing, entry.id); err != nil {
			delete(missing)
			return nil, {kind = .Allocation_Failed}
		}
	}
	return missing[:], {}
}

// Relative to the project root, '/'-separated, and without empty, "." or ".."
// parts.
valid_path :: proc(path: string) -> bool {
	if len(path) == 0 ||
	   path[0] == '/' ||
	   path[len(path) - 1] == '/' ||
	   strings.contains_rune(path, '\\') {
		return false
	}
	rest := path
	for part in strings.split_iterator(&rest, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

format_id :: proc(id: Asset_ID, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%016x", u64(id), allocator = allocator)
}

parse_id :: proc(text: string) -> (Asset_ID, bool) {
	if len(text) != 16 {
		return 0, false
	}
	for c in transmute([]byte)text {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
			return 0, false
		}
	}
	value, ok := strconv.parse_u64_of_base(text, 16)
	if !ok || value == 0 {
		return 0, false
	}
	return Asset_ID(value), true
}

parse_type :: proc(name: string) -> (Asset_Type, bool) {
	for type_name, type in TYPE_NAMES {
		if type_name == name {
			return type, true
		}
	}
	return {}, false
}

@(private)
new_id :: proc() -> Asset_ID {
	for {
		bytes: [8]byte
		crypto.rand_bytes(bytes[:])
		if id := transmute(Asset_ID)bytes; id != 0 {
			return id
		}
	}
}

// Takes a copy of entry.path.
@(private)
insert :: proc(registry: ^Registry, entry: Entry) -> Error_Kind {
	if !valid_path(entry.path) {
		return .Invalid_Path
	}
	if entry.id in registry.by_id {
		return .Duplicate_ID
	}
	if entry.path in registry.by_path {
		return .Duplicate_Path
	}

	owned, err := strings.clone(entry.path, registry.allocator)
	if err != nil {
		return .Allocation_Failed
	}
	stored := entry
	stored.path = owned
	if _, append_err := append(&registry.entries, stored); append_err != nil {
		delete(owned, registry.allocator)
		return .Allocation_Failed
	}
	registry.by_id[stored.id] = len(registry.entries) - 1
	registry.by_path[owned] = len(registry.entries) - 1
	return .None
}
