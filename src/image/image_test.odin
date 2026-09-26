package image

import "core:encoding/endian"
import "core:os"
import "core:path/filepath"
import "core:testing"

// Writes a PNG signature and an IHDR chunk with the given size. That's enough
// for the header check; there's no pixel data, so a full decode would fail.
write_png_header :: proc(t: ^testing.T, name: string, width, height: u32) -> string {
	directory, dir_err := os.temp_directory(context.temp_allocator)
	testing.expect(t, dir_err == nil)
	path, join_err := filepath.join({directory, name}, context.temp_allocator)
	testing.expect(t, join_err == nil)

	header: [33]u8
	copy(header[:], []u8{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A})
	endian.put_u32(header[8:], .Big, 13)
	copy(header[12:], "IHDR")
	endian.put_u32(header[16:], .Big, width)
	endian.put_u32(header[20:], .Big, height)
	header[24] = 8
	header[25] = 6
	testing.expect(t, os.write_entire_file(path, header[:]) == nil)
	return path
}

@(test)
test_load_rejects_oversized_before_decoding :: proc(t: ^testing.T) {
	path := write_png_header(t, "ember_image_too_large.png", MAX_DIMENSION + 1, 1)
	defer os.remove(path)

	image, err := load(path)
	testing.expect(t, err == .Too_Large)
	testing.expect(t, image.pixels == nil)
}

@(test)
test_load_reports_truncated_file_as_decode_failure :: proc(t: ^testing.T) {
	path := write_png_header(t, "ember_image_truncated.png", 2, 2)
	defer os.remove(path)

	image, err := load(path)
	testing.expect(t, err == .Decode_Failed)
	testing.expect(t, image.pixels == nil)
}
