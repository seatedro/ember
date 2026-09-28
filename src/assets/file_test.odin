package assets

import emath "../core/math"
import "../geometry"
import "core:encoding/endian"
import "core:mem"
import "core:testing"

MODEL_ID :: Asset_ID(0x6f3a9c2e81d4b705)

// Two nodes, one skinned mesh with two submeshes, and a cubic-spline rotation.
@(private = "file")
test_model :: proc() -> Model {
	@(static) nodes := [2]Node {
		{name = "root", parent = NO_INDEX, mesh = 0, skin = 0, rotation = 1, scale = 1},
		{
			name = "arm",
			parent = 0,
			mesh = NO_INDEX,
			skin = NO_INDEX,
			translation = {0, 1, 0},
			rotation = quaternion(x = 0.1, y = 0.2, z = 0.3, w = 0.9),
			scale = 1,
		},
	}
	@(static) meshes := [1]Mesh{{name = "body", first_submesh = 0, submesh_count = 2}}
	@(static) submeshes := [2]Submesh {
		{first_index = 0, index_count = 3, material = 0, bounds = {{0, 0.5, 0}, 1}},
		{first_index = 3, index_count = 3, material = NO_INDEX, bounds = {{0, 0.5, 0}, 1}},
	}
	@(static) materials := [1]Material {
		{
			name = "suit",
			base_color = {0.9, 0.9, 0.92, 1},
			roughness = 0.6,
			alpha_mode = .Mask,
			alpha_cutoff = 0.5,
			double_sided = true,
			textures = #partial{.Base_Color = 0xa1c07e5d93f2468b},
		},
	}
	@(static) vertices := [4]geometry.Vertex {
		{position = {0, 0, 0}, uv = {0, 0}},
		{position = {1, 0, 0}, uv = {1, 0}},
		{position = {0, 1, 0}, uv = {0, 1}},
		{position = {1, 1, 0}, uv = {1, 1}},
	}
	@(static) skin_vertices := [4]Skin_Vertex {
		{weights = {1, 0, 0, 0}},
		{joints = {1, 0, 0, 0}, weights = {1, 0, 0, 0}},
		{weights = {0.5, 0.5, 0, 0}, joints = {0, 1, 0, 0}},
		{joints = {1, 0, 0, 0}, weights = {1, 0, 0, 0}},
	}
	@(static) indices := [6]u16{0, 1, 2, 2, 1, 3}
	@(static) skins := [1]Skin{{first_joint = 0, joint_count = 2, root = 0}}
	@(static) skin_joints := [2]Skin_Joint {
		{node = 0, inverse_bind = emath.Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}},
		{node = 1, inverse_bind = emath.Mat4{1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, 0, 0, 1}},
	}
	@(static) animations := [1]Animation {
		{name = "wave", duration = 1, first_channel = 0, channel_count = 1},
	}
	@(static) channels := [1]Channel {
		{
			node = 1,
			path = .Rotation,
			interpolation = .Cubic_Spline,
			first_key = 0,
			key_count = 2,
			first_value = 0,
		},
	}
	@(static) key_times := [2]f32{0, 1}
	@(static) key_values: [24]f32

	return {
		nodes = nodes[:],
		meshes = meshes[:],
		submeshes = submeshes[:],
		materials = materials[:],
		vertices = vertices[:],
		skin_vertices = skin_vertices[:],
		indices = indices[:],
		skins = skins[:],
		skin_joints = skin_joints[:],
		animations = animations[:],
		channels = channels[:],
		key_times = key_times[:],
		key_values = key_values[:],
	}
}

@(test)
test_model_round_trip :: proc(t: ^testing.T) {
	data, err := encode_model(test_model(), MODEL_ID)
	defer delete(data)
	testing.expect_value(t, err, File_Error.None)

	model, decode_err := decode_model(data, MODEL_ID)
	defer destroy_model(&model)
	testing.expect_value(t, decode_err, File_Error.None)
	testing.expect_value(t, model.nodes[1].rotation.x, 0.1)
	testing.expect_value(t, model.nodes[1].rotation.w, 0.9)
	testing.expect_value(t, model.skin_joints[1].inverse_bind[1, 3], -1)
	testing.expect_value(t, model.materials[0].textures[.Base_Color], 0xa1c07e5d93f2468b)
	_, is_u16 := model.indices.([]u16)
	testing.expect(t, is_u16)

	again, again_err := encode_model(model, MODEL_ID)
	defer delete(again)
	testing.expect_value(t, again_err, File_Error.None)
	testing.expect(t, mem.compare(data, again) == 0)
}

@(test)
test_model_rejects_bad_references :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, model: Model, want: File_Error, loc := #caller_location) {
		data, err := encode_model(model, MODEL_ID)
		delete(data)
		testing.expect_value(t, err, want, loc = loc)
	}

	model := test_model()
	bad_indices := [6]u16{0, 1, 2, 2, 1, 4}
	model.indices = bad_indices[:]
	check(t, model, .Invalid_Reference)

	model = test_model()
	nodes := [2]Node{model.nodes[1], model.nodes[0]}
	nodes[0].parent = 1
	model.nodes = nodes[:]
	check(t, model, .Invalid_Reference)

	model = test_model()
	times := [2]f32{1, 0}
	model.key_times = times[:]
	check(t, model, .Invalid_Value)

	model = test_model()
	values := [23]f32{}
	model.key_values = values[:]
	check(t, model, .Invalid_Reference)

	model = test_model()
	model.skin_vertices = model.skin_vertices[:3]
	check(t, model, .Invalid_Reference)
}

@(test)
test_corrupt_files_are_rejected :: proc(t: ^testing.T) {
	data, _ := encode_model(test_model(), MODEL_ID)
	defer delete(data)

	decode :: proc(data: []byte, id := MODEL_ID) -> File_Error {
		model, err := decode_model(data, id)
		destroy_model(&model)
		return err
	}
	patched :: proc(data: []byte, offset: int, value: u32) -> []byte {
		copied := make([]byte, len(data), context.temp_allocator)
		copy(copied, data)
		endian.put_u32(copied[offset:], .Little, value)
		return copied
	}
	directory :: proc(entry, field: int) -> int {
		return HEADER_SIZE + DIRECTORY_ENTRY_SIZE * entry + field
	}

	testing.expect_value(t, decode(data[:HEADER_SIZE - 1]), File_Error.Too_Short)
	testing.expect_value(t, decode(data, 1), File_Error.Wrong_ID)
	testing.expect_value(t, decode(patched(data, 0, 0)), File_Error.Wrong_Magic)
	testing.expect_value(t, decode(patched(data, 4, 2)), File_Error.Unsupported_Version)
	testing.expect_value(t, decode(patched(data, 8, 1 << 30)), File_Error.Too_Short)
	testing.expect_value(t, decode(data[:len(data) - 16]), File_Error.Bad_Directory)
	testing.expect_value(t, decode(patched(data, directory(1, 8), 1)), File_Error.Bad_Directory)
	testing.expect_value(
		t,
		decode(patched(data, directory(1, 0), u32(Section_Kind.Strings))),
		File_Error.Duplicate_Section,
	)
	testing.expect_value(t, decode(patched(data, directory(1, 4), 64)), File_Error.Wrong_Stride)
	testing.expect_value(
		t,
		decode(patched(data, directory(1, 0), u32('X' | 'X' << 8 | 'X' << 16 | 'X' << 24))),
		File_Error.Missing_Section,
	)

	sections, _ := decode_file(data, MODEL_MAGIC, u64(MODEL_ID), context.temp_allocator)
	indices, _ := find_section(sections, .Indices, 2)
	offset := mem.ptr_sub(raw_data(indices), raw_data(data))
	testing.expect_value(t, decode(patched(data, offset, 9)), File_Error.Invalid_Reference)
}

@(test)
test_texture_round_trip_and_limits :: proc(t: ^testing.T) {
	pixels: [44]byte
	for &p, i in pixels {
		p = byte(i)
	}
	texture := Texture {
		width     = 4,
		height    = 2,
		format    = .RGBA8_SRGB,
		mip_count = 3,
		pixels    = pixels[:],
	}
	data, err := encode_texture(texture, MODEL_ID)
	defer delete(data)
	testing.expect_value(t, err, File_Error.None)

	decoded, decode_err := decode_texture(data, MODEL_ID)
	defer destroy_texture(&decoded)
	testing.expect_value(t, decode_err, File_Error.None)
	testing.expect(t, decoded.width == 4 && decoded.height == 2 && decoded.mip_count == 3)
	testing.expect(t, mem.compare(decoded.pixels, pixels[:]) == 0)

	cases := []struct {
		texture: Texture,
		error:   File_Error,
	} {
		{{4, 2, .RGBA8_SRGB, 3, pixels[:40]}, .Invalid_Reference},
		{{4, 2, .RGBA8_SRGB, 4, pixels[:]}, .Invalid_Value},
		{{4, 2, Texture_Format(0), 3, pixels[:]}, .Invalid_Value},
		{{16385, 1, .RGBA8_Linear, 1, nil}, .Invalid_Value},
	}
	for c in cases {
		bad, bad_err := encode_texture(c.texture, MODEL_ID)
		delete(bad)
		testing.expect_value(t, bad_err, c.error)
	}
}
