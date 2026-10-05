package assets

import "core:encoding/endian"
import "core:mem"

FILE_VERSION :: 1
HEADER_SIZE :: 32
DIRECTORY_ENTRY_SIZE :: 24
SECTION_ALIGNMENT :: 16

MODEL_MAGIC :: [4]u8{'E', 'M', 'D', 'L'}
TEXTURE_MAGIC :: [4]u8{'E', 'T', 'E', 'X'}

// Four characters read as a little-endian u32, so "VERT" is 'V' | 'E' << 8 ...
Section_Kind :: enum u32 {
	Strings       = 'S' | 'T' << 8 | 'R' << 16 | 'S' << 24,
	Nodes         = 'N' | 'O' << 8 | 'D' << 16 | 'E' << 24,
	Meshes        = 'M' | 'E' << 8 | 'S' << 16 | 'H' << 24,
	Submeshes     = 'S' | 'U' << 8 | 'B' << 16 | 'M' << 24,
	Materials     = 'M' | 'A' << 8 | 'T' << 16 | 'L' << 24,
	Vertices      = 'V' | 'E' << 8 | 'R' << 16 | 'T' << 24,
	Skin_Vertices = 'S' | 'K' << 8 | 'N' << 16 | 'V' << 24,
	Indices       = 'I' | 'N' << 8 | 'D' << 16 | 'X' << 24,
	Skins         = 'S' | 'K' << 8 | 'I' << 16 | 'N' << 24,
	Skin_Joints   = 'S' | 'J' << 8 | 'N' << 16 | 'T' << 24,
	Animations    = 'A' | 'N' << 8 | 'I' << 16 | 'M' << 24,
	Channels      = 'C' | 'H' << 8 | 'A' << 16 | 'N' << 24,
	Key_Times     = 'K' | 'T' << 8 | 'I' << 16 | 'M' << 24,
	Key_Values    = 'K' | 'V' << 8 | 'A' << 16 | 'L' << 24,
	Texture_Info  = 'T' | 'X' << 8 | 'H' << 16 | 'D' << 24,
	Pixels        = 'P' | 'I' << 8 | 'X' << 16 | 'L' << 24,
	Index_Entries = 'E' | 'N' << 8 | 'T' << 16 | 'R' << 24,
}

// stride is the size of one record; byte blobs use 1.
Section :: struct {
	kind:   Section_Kind,
	stride: u32,
	data:   []byte,
}

File_Error :: enum {
	None,
	Too_Short,
	Wrong_Magic,
	Unsupported_Version,
	// The file names a different asset than the one asked for.
	Wrong_ID,
	// A section outside the file or off its 16-byte boundary.
	Bad_Directory,
	Duplicate_Section,
	Missing_Section,
	// A section's record size isn't the one this version defines.
	Wrong_Stride,
	// A count, index, or range that points outside what it refers to.
	Invalid_Reference,
	// An enum value, dimension, or size this version doesn't allow.
	Invalid_Value,
	Allocation_Failed,
}

encode_file :: proc(
	magic: [4]u8,
	id: u64,
	sections: []Section,
	allocator := context.allocator,
) -> (
	[]byte,
	File_Error,
) {
	directory_end := HEADER_SIZE + DIRECTORY_ENTRY_SIZE * len(sections)
	size := align(directory_end)
	for section in sections {
		size = align(size + len(section.data))
	}

	data, err := make([]byte, size, allocator)
	if err != nil {
		return nil, .Allocation_Failed
	}
	magic := magic
	copy(data[0:4], magic[:])
	endian.put_u32(data[4:8], .Little, FILE_VERSION)
	endian.put_u32(data[8:12], .Little, u32(len(sections)))
	endian.put_u64(data[16:24], .Little, id)

	offset := align(directory_end)
	for section, i in sections {
		entry := data[HEADER_SIZE + DIRECTORY_ENTRY_SIZE * i:]
		endian.put_u32(entry[0:4], .Little, u32(section.kind))
		endian.put_u32(entry[4:8], .Little, section.stride)
		endian.put_u64(entry[8:16], .Little, u64(offset))
		endian.put_u64(entry[16:24], .Little, u64(len(section.data)))
		copy(data[offset:], section.data)
		offset = align(offset + len(section.data))
	}
	return data, .None
}

decode_file :: proc(
	data: []byte,
	magic: [4]u8,
	id: u64,
	allocator := context.allocator,
) -> (
	[]Section,
	File_Error,
) {
	if len(data) < HEADER_SIZE {
		return nil, .Too_Short
	}
	magic := magic
	if mem.compare(data[0:4], magic[:]) != 0 {
		return nil, .Wrong_Magic
	}
	if version, _ := endian.get_u32(data[4:8], .Little); version != FILE_VERSION {
		return nil, .Unsupported_Version
	}
	if file_id, _ := endian.get_u64(data[16:24], .Little); file_id != id {
		return nil, .Wrong_ID
	}

	count, _ := endian.get_u32(data[8:12], .Little)
	if u64(count) > u64(len(data) - HEADER_SIZE) / DIRECTORY_ENTRY_SIZE {
		return nil, .Too_Short
	}
	directory_end := u64(HEADER_SIZE + DIRECTORY_ENTRY_SIZE * int(count))

	sections, err := make([]Section, count, allocator)
	if err != nil {
		return nil, .Allocation_Failed
	}
	for &section, i in sections {
		entry := data[HEADER_SIZE + DIRECTORY_ENTRY_SIZE * i:]
		kind, _ := endian.get_u32(entry[0:4], .Little)
		stride, _ := endian.get_u32(entry[4:8], .Little)
		offset, _ := endian.get_u64(entry[8:16], .Little)
		size, _ := endian.get_u64(entry[16:24], .Little)
		if offset % SECTION_ALIGNMENT != 0 ||
		   offset < directory_end ||
		   offset > u64(len(data)) ||
		   size > u64(len(data)) - offset {
			delete(sections, allocator)
			return nil, .Bad_Directory
		}
		for other in sections[:i] {
			if u32(other.kind) == kind {
				delete(sections, allocator)
				return nil, .Duplicate_Section
			}
		}
		section = {Section_Kind(kind), stride, data[offset:][:size]}
	}
	return sections, .None
}

find_section :: proc(
	sections: []Section,
	kind: Section_Kind,
	stride: u32,
) -> (
	[]byte,
	File_Error,
) {
	for section in sections {
		if section.kind != kind {
			continue
		}
		if section.stride != stride || len(section.data) % int(stride) != 0 {
			return nil, .Wrong_Stride
		}
		return section.data, .None
	}
	return nil, .Missing_Section
}

@(private)
align :: proc(n: int) -> int {
	return (n + SECTION_ALIGNMENT - 1) &~ (SECTION_ALIGNMENT - 1)
}
