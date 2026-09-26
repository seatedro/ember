package shadergen

import "core:slice"
import "core:strings"

// Values from spirv-headers/include/spirv/1.1/spirv.h.
SPIRV_MAGIC :: 0x07230203
HEADER_WORDS :: 5
OP_NAME :: 5
OP_TYPE_POINTER :: 32
OP_VARIABLE :: 59
OP_DECORATE :: 71
DECORATION_BLOCK :: 2
STORAGE_CLASS_UNIFORM :: 2

// OpenGL finds a uniform block by its type name, and the Metal backend by its
// argument name, which SPIRV-Cross takes from the instance variable. Each
// uniform block variable takes its type's name, and the type becomes
// <name>_Block, because SPIRV-Cross renames one of two identical names.
//
// Every block variable must already have an OpName, as glslang emits one even
// for an anonymous block.
name_uniform_blocks :: proc(module: []u32, allocator := context.allocator) -> ([]u32, bool) {
	if len(module) < HEADER_WORDS || module[0] != SPIRV_MAGIC {
		return nil, false
	}

	names := make(map[u32]string, context.temp_allocator)
	blocks := make(map[u32]bool, context.temp_allocator)
	uniform_pointees := make(map[u32]u32, context.temp_allocator)
	uniform_variables := make(map[u32]u32, context.temp_allocator)
	for offset := HEADER_WORDS; offset < len(module); {
		count := int(module[offset] >> 16)
		if count == 0 || offset + count > len(module) {
			return nil, false
		}

		operands := module[offset + 1:offset + count]
		switch module[offset] & 0xffff {
		case OP_NAME:
			if len(operands) < 2 {
				return nil, false
			}

			bytes := slice.to_bytes(operands[1:])
			names[operands[0]] = string(bytes[:slice.linear_search(bytes, 0) or_else len(bytes)])
		case OP_DECORATE:
			if len(operands) >= 2 && operands[1] == DECORATION_BLOCK {
				blocks[operands[0]] = true
			}
		case OP_TYPE_POINTER:
			if len(operands) == 3 && operands[1] == STORAGE_CLASS_UNIFORM {
				uniform_pointees[operands[0]] = operands[2]
			}
		case OP_VARIABLE:
			if len(operands) >= 3 && operands[2] == STORAGE_CLASS_UNIFORM {
				uniform_variables[operands[1]] = operands[0]
			}
		}
		offset += count
	}

	renames := make(map[u32]string, context.temp_allocator)
	for variable, pointer in uniform_variables {
		block, is_uniform := uniform_pointees[pointer]
		if !is_uniform || !blocks[block] {
			continue
		}

		name, named := names[block]
		if !named || variable not_in names {
			return nil, false
		}

		renames[variable] = name
		renames[block] = strings.concatenate({name, "_Block"}, context.temp_allocator)
	}

	renamed := make([dynamic]u32, 0, len(module) + 4 * len(renames), allocator)
	append(&renamed, ..module[:HEADER_WORDS])
	for offset := HEADER_WORDS; offset < len(module); {
		instruction := module[offset:offset + int(module[offset] >> 16)]
		offset += len(instruction)
		name, rename := "", false
		if instruction[0] & 0xffff == OP_NAME {
			name, rename = renames[instruction[1]]
		}

		if !rename {
			append(&renamed, ..instruction)
			continue
		}

		// The string is NUL-terminated and zero-padded to a whole word.
		start := len(renamed)
		count := 2 + (len(name) + 4) / 4
		append(&renamed, u32(count) << 16 | OP_NAME, instruction[1])
		resize(&renamed, start + count)
		copy(slice.to_bytes(renamed[start + 2:]), name)
	}

	return renamed[:], true
}
