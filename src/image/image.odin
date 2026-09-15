package image

import "core:os"
import stbi "vendor:stb/image"

// Decoded 8-bit RGBA pixels. Color space is not a property of the image: 8-bit
// files carry no reliable tag (stb_image ignores PNG gAMA/iCCP/sRGB chunks), so
// the consumer states it through the texture format when uploading.
Image :: struct {
	width, height: i32,
	pixels:        []u8,
}

// Largest side either backend accepts as a texture on macOS (Metal and the GL
// implementation limit, from memory). Checked from the header before decoding,
// so a hostile file is refused before it costs width * height * 4 bytes;
// stb_image's own guard is 2^24 per side, which bounds nothing useful.
MAX_DIMENSION :: 16384

Error :: enum {
	None,
	Read_Failed,
	Decode_Failed,
	Too_Large,
}

load :: proc(path: string) -> (Image, Error) {
	source, read_error := os.read_entire_file(path, context.allocator)
	defer delete(source)

	if read_error != nil {
		return {}, .Read_Failed
	}

	if len(source) == 0 || len(source) > int(max(i32)) {
		return {}, .Decode_Failed
	}

	width, height: i32
	if stbi.info_from_memory(raw_data(source), i32(len(source)), &width, &height, nil) == 0 {
		return {}, .Decode_Failed
	}

	if width > MAX_DIMENSION || height > MAX_DIMENSION {
		return {}, .Too_Large
	}

	pixels := stbi.load_from_memory(raw_data(source), i32(len(source)), &width, &height, nil, 4)
	if pixels == nil {
		return {}, .Decode_Failed
	}

	return {width = width, height = height, pixels = pixels[:int(width) * int(height) * 4]}, .None
}

destroy :: proc(image: ^Image) {
	stbi.image_free(raw_data(image.pixels))
	image^ = {}
}
