#+private
package assets

import "core:encoding/endian"
import "core:strings"
import "core:unicode/utf8"

put_name :: proc(w: ^[dynamic]byte, table: ^[dynamic]byte, s: string) {
	put_u32(w, u32(len(table)))
	put_u32(w, u32(len(s)))
	append(table, s)
}

put_u16 :: proc(w: ^[dynamic]byte, value: u16) {
	bytes: [2]byte
	endian.put_u16(bytes[:], .Little, value)
	append(w, ..bytes[:])
}

put_u32 :: proc(w: ^[dynamic]byte, value: u32) {
	bytes: [4]byte
	endian.put_u32(bytes[:], .Little, value)
	append(w, ..bytes[:])
}

put_i32 :: proc(w: ^[dynamic]byte, value: i32) {
	put_u32(w, u32(value))
}

put_u64 :: proc(w: ^[dynamic]byte, value: u64) {
	bytes: [8]byte
	endian.put_u64(bytes[:], .Little, value)
	append(w, ..bytes[:])
}

put_f32s :: proc(w: ^[dynamic]byte, values: []f32) {
	for value in values {
		put_u32(w, transmute(u32)value)
	}
}

// Walks one section's records. Record sizes were checked against the section
// length, so reads stay inside data.
Reader :: struct {
	data:  []byte,
	table: []byte,
}

read_u16 :: proc(r: ^Reader) -> u16 {
	value, _ := endian.get_u16(r.data, .Little)
	r.data = r.data[2:]
	return value
}

read_u32 :: proc(r: ^Reader) -> u32 {
	value, _ := endian.get_u32(r.data, .Little)
	r.data = r.data[4:]
	return value
}

read_i32 :: proc(r: ^Reader) -> i32 {
	return i32(read_u32(r))
}

read_u64 :: proc(r: ^Reader) -> u64 {
	value, _ := endian.get_u64(r.data, .Little)
	r.data = r.data[8:]
	return value
}

read_f32 :: proc(r: ^Reader) -> f32 {
	return transmute(f32)read_u32(r)
}

read_vec3 :: proc(r: ^Reader) -> [3]f32 {
	return {read_f32(r), read_f32(r), read_f32(r)}
}

// An offset and length into the string table, copied out as UTF-8.
read_name :: proc(r: ^Reader) -> (string, File_Error) {
	offset, length := read_u32(r), read_u32(r)
	if u64(offset) + u64(length) > u64(len(r.table)) {
		return "", .Invalid_Reference
	}
	text := string(r.table[offset:][:length])
	if !utf8.valid_string(text) {
		return "", .Invalid_Value
	}
	copied, err := strings.clone(text)
	if err != nil {
		return "", .Allocation_Failed
	}
	return copied, .None
}

make_records :: proc($T: typeid, count: int) -> ([]T, File_Error) {
	records, err := make([]T, count)
	if err != nil {
		return nil, .Allocation_Failed
	}
	return records, .None
}
