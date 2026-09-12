package image

import "core:os"
import stbi "vendor:stb/image"

Image :: struct {
	width, height: i32,
	pixels:        []u8,
}

Error :: enum {
	None,
	Read_Failed,
	Decode_Failed,
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
