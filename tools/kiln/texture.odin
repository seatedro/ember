package kiln

import "core:encoding/base64"
import "core:fmt"
import "core:hash/xxhash"
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

	texture := assets.Texture {
		width     = u32(decoded.width),
		height    = u32(decoded.height),
		format    = format,
		mip_count = 1,
		pixels    = decoded.pixels,
	}
	file_err: assets.File_Error
	if encoded, file_err = assets.encode_texture(texture, id, allocator); file_err != .None {
		return nil, fmt.tprintf("cannot encode: %v", file_err)
	}
	return encoded, ""
}
