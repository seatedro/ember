package shadergen

import "core:slice"
import "core:testing"

@(private = "file")
spirv_name :: proc(module: []u32, id: u32) -> string {
	for offset := HEADER_WORDS; offset < len(module); offset += int(module[offset] >> 16) {
		if module[offset] & 0xffff == OP_NAME && module[offset + 1] == id {
			bytes := slice.to_bytes(module[offset + 2:offset + int(module[offset] >> 16)])
			return string(bytes[:slice.linear_search(bytes, 0) or_else len(bytes)])
		}
	}
	return ""
}

// %1 is a Block struct, %2 a Uniform pointer to it, and %3 the anonymous
// instance glslang emits for `uniform Material {...};`.
@(private = "file")
MODULE :: [?]u32 {
	SPIRV_MAGIC,
	0x00010000,
	0,
	4,
	0,
	5 << 16 | OP_NAME,
	1,
	0x6574614d, // "Mate"
	0x6c616972, // "rial"
	0,
	3 << 16 | OP_NAME,
	3,
	0,
	3 << 16 | OP_DECORATE,
	1,
	DECORATION_BLOCK,
	4 << 16 | OP_TYPE_POINTER,
	2,
	STORAGE_CLASS_UNIFORM,
	1,
	4 << 16 | OP_VARIABLE,
	2,
	3,
	STORAGE_CLASS_UNIFORM,
}

@(test)
test_uniform_block_takes_its_type_name :: proc(t: ^testing.T) {
	module := MODULE
	renamed, ok := name_uniform_blocks(module[:], context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, spirv_name(renamed, 3), "Material")
	testing.expect_value(t, spirv_name(renamed, 1), "Material_Block")

	// The instance's name grows from one word to three, the type's from three
	// to four.
	testing.expect_value(t, len(renamed), len(module) + 3)
}

@(test)
test_uniform_block_rejects_truncated_and_unnamed_modules :: proc(t: ^testing.T) {
	module := MODULE
	_, ok := name_uniform_blocks(module[:len(module) - 1], context.temp_allocator)
	testing.expect(t, !ok)

	// Point the instance's OpName elsewhere, leaving %3 without one.
	module[11] = 4
	_, ok = name_uniform_blocks(module[:], context.temp_allocator)
	testing.expect(t, !ok)
}
