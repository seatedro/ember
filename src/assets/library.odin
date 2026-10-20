package assets

import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Library :: struct {
	directory: string,
	entries:   []Index_Entry,
	allocator: mem.Allocator,
}

Library_Error :: enum {
	None,
	Read_Failed,
	Not_Found,
	Allocation_Failed,
}

Load_Error :: union {
	Library_Error,
	File_Error,
}

open_library :: proc(
	directory: string,
	allocator := context.allocator,
) -> (
	library: Library,
	err: Load_Error,
) {
	path, join_err := filepath.join({directory, INDEX_FILE}, context.temp_allocator)
	if join_err != nil {
		return {}, Library_Error.Allocation_Failed
	}
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return {}, Library_Error.Read_Failed
	}

	entries, file_err := decode_index(data, allocator)
	if file_err != .None {
		return {}, file_err
	}
	owned, clone_err := strings.clone(directory, allocator)
	if clone_err != nil {
		destroy_index(entries, allocator)
		return {}, Library_Error.Allocation_Failed
	}
	return {directory = owned, entries = entries, allocator = allocator}, nil
}

close_library :: proc(library: ^Library) {
	destroy_index(library.entries, library.allocator)
	delete(library.directory, library.allocator)
	library^ = {}
}

find_model :: proc(library: Library, path: string) -> (Asset_ID, bool) {
	for entry in library.entries {
		if entry.kind == .Model && entry.path == path {
			return entry.id, true
		}
	}
	return 0, false
}

load_model :: proc(
	library: Library,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	model: Model,
	err: Load_Error,
) {
	data := read_asset(library, id, .Model) or_return
	defer delete(data)

	file_err: File_Error
	if model, file_err = decode_model(data, id, allocator); file_err != .None {
		return {}, file_err
	}
	return model, nil
}

load_texture :: proc(
	library: Library,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	texture: Texture,
	err: Load_Error,
) {
	data := read_asset(library, id, .Texture) or_return
	defer delete(data)

	file_err: File_Error
	if texture, file_err = decode_texture(data, id, allocator); file_err != .None {
		return {}, file_err
	}
	return texture, nil
}

@(private)
read_asset :: proc(library: Library, id: Asset_ID, kind: File_Kind) -> ([]byte, Load_Error) {
	index, found := slice.binary_search_by(
		library.entries,
		id,
		proc(entry: Index_Entry, id: Asset_ID) -> slice.Ordering {
			return slice.cmp(entry.id, id)
		},
	)
	if !found || library.entries[index].kind != kind {
		return nil, Library_Error.Not_Found
	}

	path, join_err := filepath.join(
		{library.directory, file_name(id, kind)},
		context.temp_allocator,
	)
	if join_err != nil {
		return nil, Library_Error.Allocation_Failed
	}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return nil, Library_Error.Read_Failed
	}
	return data, nil
}
