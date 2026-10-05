package assets

import "core:fmt"

INDEX_MAGIC :: [4]u8{'E', 'I', 'D', 'X'}
INDEX_FILE :: "index.eidx"
INDEX_ENTRY_SIZE :: 24

File_Kind :: enum u32 {
	Model,
	Texture,
}

@(rodata)
FILE_EXTENSIONS := [File_Kind]string {
	.Model   = ".emdl",
	.Texture = ".etex",
}

Index_Entry :: struct {
	id:   Asset_ID,
	kind: File_Kind,
	path: string,
}

file_name :: proc(id: Asset_ID, kind: File_Kind, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%016x%s", u64(id), FILE_EXTENSIONS[kind], allocator = allocator)
}

encode_index :: proc(
	entries: []Index_Entry,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: File_Error,
) {
	validate_index(entries) or_return
	context.allocator = context.temp_allocator

	strings_table: [dynamic]byte
	records := make([dynamic]byte, 0, INDEX_ENTRY_SIZE * len(entries))
	for entry in entries {
		put_u64(&records, u64(entry.id))
		put_u32(&records, u32(entry.kind))
		put_name(&records, &strings_table, entry.path)
		put_u32(&records, 0)
	}

	sections := []Section {
		{.Strings, 1, strings_table[:]},
		{.Index_Entries, INDEX_ENTRY_SIZE, records[:]},
	}
	return encode_file(INDEX_MAGIC, 0, sections, allocator)
}

decode_index :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	entries: []Index_Entry,
	err: File_Error,
) {
	defer if err != .None {
		destroy_index(entries, allocator)
		entries = nil
	}

	sections := decode_file(data, INDEX_MAGIC, 0, context.temp_allocator) or_return
	r := Reader {
		table = find_section(sections, .Strings, 1) or_return,
		data  = find_section(sections, .Index_Entries, INDEX_ENTRY_SIZE) or_return,
	}

	context.allocator = allocator
	entries = make_records(Index_Entry, len(r.data) / INDEX_ENTRY_SIZE) or_return
	for &entry in entries {
		entry.id = Asset_ID(read_u64(&r))
		entry.kind = File_Kind(read_u32(&r))
		entry.path = read_name(&r) or_return
		read_u32(&r)
	}
	validate_index(entries) or_return
	return entries, .None
}

destroy_index :: proc(entries: []Index_Entry, allocator := context.allocator) {
	for entry in entries {
		delete(entry.path, allocator)
	}
	delete(entries, allocator)
}

validate_index :: proc(entries: []Index_Entry) -> File_Error {
	previous := Asset_ID(0)
	for entry in entries {
		if entry.id <= previous {
			return .Invalid_Value
		}
		previous = entry.id

		switch entry.kind {
		case .Model:
			if !valid_path(entry.path) {
				return .Invalid_Value
			}
		case .Texture:
			if entry.path != "" {
				return .Invalid_Value
			}
		case:
			return .Invalid_Value
		}
	}
	return .None
}
