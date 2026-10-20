package kiln

import "core:encoding/base64"
import "core:fmt"
import "core:hash/xxhash"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "ember:assets"
import "ember:image"
import "vendor:cgltf"

texture_id :: proc(
	model: assets.Asset_ID,
	image_name: string,
	format: assets.Texture_Format,
) -> assets.Asset_ID {
	key := make([]byte, 1 + len(image_name), context.temp_allocator)
	key[0] = u8(format)
	copy(key[1:], image_name)
	return assets.Asset_ID(xxhash.XXH3_64_with_seed(key, u64(model)))
}

Image_Bytes :: struct {
	bytes: []byte,
	file:  string,
}

read_image :: proc(
	data: ^cgltf.data,
	image: ^cgltf.image,
	root, directory: string,
) -> (
	result: Image_Bytes,
	problem: string,
) {
	if view := image.buffer_view; view != nil {
		bytes := cgltf.buffer_view_data(view)
		if bytes == nil {
			return {}, fmt.tprintf("image %q has no buffer data", image.name)
		}
		return {bytes = bytes[:view.size]}, ""
	}

	uri := string(image.uri)
	if strings.has_prefix(uri, "data:") {
		comma := strings.index_byte(uri, ',')
		if comma < 0 || !strings.has_suffix(uri[:comma], ";base64") {
			return {}, fmt.tprintf("image %q has a data URI that is not base64", image.name)
		}
		bytes, err := base64.decode(uri[comma + 1:])
		if err != nil {
			return {}, fmt.tprintf("image %q has invalid base64", image.name)
		}
		return {bytes = bytes}, ""
	}

	file, ok := external_file(uri, directory)
	if !ok {
		return {}, fmt.tprintf("image %q points outside the project: %s", image.name, uri)
	}
	bytes, err := os.read_entire_file(filepath.join({root, file}) or_else "", context.allocator)
	if err != nil {
		return {}, fmt.tprintf("cannot read image %s: %v", file, err)
	}
	return {bytes = bytes, file = file}, ""
}

external_file :: proc(uri, directory: string) -> (file: string, ok: bool) {
	encoded := strings.clone_to_cstring(uri, context.temp_allocator)
	length := cgltf.decode_uri(cast([^]byte)encoded)
	decoded := string((cast([^]byte)encoded)[:length])
	file = filepath.join({directory, decoded}) or_else ""
	return file, assets.valid_path(file)
}

convert_texture :: proc(
	bytes: []byte,
	format: assets.Texture_Format,
	id: assets.Asset_ID,
	allocator := context.allocator,
) -> (
	encoded: []byte,
	problem: string,
) {
	decoded, err := image.decode(bytes)
	if err != .None {
		return nil, fmt.tprintf("cannot decode: %v", err)
	}
	defer image.destroy(&decoded)

	width, height := u32(decoded.width), u32(decoded.height)
	mip_count := full_mip_count(max(width, height))
	pixels, alloc_err := make([]byte, assets.texture_size(width, height, mip_count), allocator)
	if alloc_err != nil {
		return nil, "out of memory"
	}
	defer delete(pixels, allocator)
	build_mips(pixels, decoded.pixels, width, height, mip_count, format == .RGBA8_SRGB)

	texture := assets.Texture {
		width     = width,
		height    = height,
		format    = format,
		mip_count = mip_count,
		pixels    = pixels,
	}
	file_err: assets.File_Error
	if encoded, file_err = assets.encode_texture(texture, id, allocator); file_err != .None {
		return nil, fmt.tprintf("cannot encode: %v", file_err)
	}
	return encoded, ""
}

full_mip_count :: proc(size: u32) -> u32 {
	count := u32(1)
	for s := size; s > 1; s /= 2 {
		count += 1
	}
	return count
}

build_mips :: proc(pixels, base: []byte, width, height, mip_count: u32, srgb: bool) {
	copy(pixels, base)
	source := pixels[:len(base)]
	offset := len(base)
	w, h := int(width), int(height)
	for _ in 1 ..< mip_count {
		next_w, next_h := max(w / 2, 1), max(h / 2, 1)
		target := pixels[offset:][:next_w * next_h * 4]
		downsample(source, w, h, target, next_w, next_h, srgb)
		offset += len(target)
		source = target
		w, h = next_w, next_h
	}
}

@(private = "file")
downsample :: proc(source: []byte, w, h: int, target: []byte, next_w, next_h: int, srgb: bool) {
	lookup := srgb_tables()
	for y in 0 ..< next_h {
		rows := [2]int{min(2 * y, h - 1), min(2 * y + 1, h - 1)}
		for x in 0 ..< next_w {
			columns := [2]int{min(2 * x, w - 1), min(2 * x + 1, w - 1)}
			sum: [4]f32
			for row in rows {
				for column in columns {
					texel := source[(row * w + column) * 4:][:4]
					for channel in 0 ..< 4 {
						value := f32(texel[channel])
						if srgb && channel < 3 {
							value = lookup.to_linear[texel[channel]]
						}
						sum[channel] += value
					}
				}
			}
			out := target[(y * next_w + x) * 4:][:4]
			for channel in 0 ..< 4 {
				average := sum[channel] / 4
				if srgb && channel < 3 {
					index := int(clamp(average, 0, 1) * f32(len(lookup.to_srgb) - 1) + 0.5)
					out[channel] = lookup.to_srgb[index]
				} else {
					out[channel] = u8(clamp(average + 0.5, 0, 255))
				}
			}
		}
	}
}

@(private = "file")
Srgb_Tables :: struct {
	to_linear: [256]f32,
	to_srgb:   [4096]u8,
}

@(private = "file")
tables_ready: bool
@(private = "file")
tables: Srgb_Tables

@(private = "file")
srgb_tables :: proc() -> ^Srgb_Tables {
	if !tables_ready {
		for &value, i in tables.to_linear {
			c := f32(i) / 255
			value = c / 12.92 if c <= 0.04045 else math.pow((c + 0.055) / 1.055, 2.4)
		}
		for &value, i in tables.to_srgb {
			l := f32(i) / f32(len(tables.to_srgb) - 1)
			c := l * 12.92 if l <= 0.0031308 else 1.055 * math.pow(l, 1 / 2.4) - 0.055
			value = u8(clamp(c * 255 + 0.5, 0, 255))
		}
		tables_ready = true
	}
	return &tables
}
