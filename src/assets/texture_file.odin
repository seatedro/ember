package assets

import "../image"
import "core:encoding/endian"

TEXTURE_INFO_SIZE :: 16

Texture_Format :: enum u32 {
	RGBA8_Linear = 1,
	RGBA8_SRGB   = 2,
}

Texture :: struct {
	width, height: u32,
	format:        Texture_Format,
	mip_count:     u32,
	pixels:        []byte,
}

encode_texture :: proc(
	texture: Texture,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: File_Error,
) {
	validate_texture(texture) or_return

	info: [TEXTURE_INFO_SIZE]byte
	endian.put_u32(info[0:4], .Little, texture.width)
	endian.put_u32(info[4:8], .Little, texture.height)
	endian.put_u32(info[8:12], .Little, u32(texture.format))
	endian.put_u32(info[12:16], .Little, texture.mip_count)
	sections := []Section {
		{.Texture_Info, TEXTURE_INFO_SIZE, info[:]},
		{.Pixels, 1, texture.pixels},
	}
	return encode_file(TEXTURE_MAGIC, u64(id), sections, allocator)
}

decode_texture :: proc(
	data: []byte,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	texture: Texture,
	err: File_Error,
) {
	sections := decode_file(data, TEXTURE_MAGIC, u64(id), context.temp_allocator) or_return
	info := find_section(sections, .Texture_Info, TEXTURE_INFO_SIZE) or_return
	pixels := find_section(sections, .Pixels, 1) or_return
	if len(info) != TEXTURE_INFO_SIZE {
		return {}, .Invalid_Value
	}

	width, _ := endian.get_u32(info[0:4], .Little)
	height, _ := endian.get_u32(info[4:8], .Little)
	format, _ := endian.get_u32(info[8:12], .Little)
	mip_count, _ := endian.get_u32(info[12:16], .Little)
	texture = {width, height, Texture_Format(format), mip_count, pixels}
	validate_texture(texture) or_return

	copied, alloc_err := make([]byte, len(pixels), allocator)
	if alloc_err != nil {
		return {}, .Allocation_Failed
	}
	copy(copied, pixels)
	texture.pixels = copied
	return texture, .None
}

destroy_texture :: proc(texture: ^Texture, allocator := context.allocator) {
	delete(texture.pixels, allocator)
	texture^ = {}
}

texture_size :: proc(width, height, mip_count: u32) -> int {
	size := 0
	w, h := int(width), int(height)
	for _ in 0 ..< mip_count {
		size += w * h * 4
		w, h = max(w / 2, 1), max(h / 2, 1)
	}
	return size
}

@(private)
validate_texture :: proc(texture: Texture) -> File_Error {
	switch texture.format {
	case .RGBA8_Linear, .RGBA8_SRGB:
	case:
		return .Invalid_Value
	}
	if texture.width == 0 ||
	   texture.height == 0 ||
	   texture.width > image.MAX_DIMENSION ||
	   texture.height > image.MAX_DIMENSION ||
	   texture.mip_count == 0 ||
	   texture.mip_count > max_mip_count(max(texture.width, texture.height)) {
		return .Invalid_Value
	}
	if len(texture.pixels) != texture_size(texture.width, texture.height, texture.mip_count) {
		return .Invalid_Reference
	}
	return .None
}

@(private)
max_mip_count :: proc(size: u32) -> u32 {
	count := u32(1)
	for s := size; s > 1; s /= 2 {
		count += 1
	}
	return count
}
