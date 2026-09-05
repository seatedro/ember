package rhi_gl_smoke

import "core:mem"
import "ember:rhi"
import gl "vendor:OpenGL"

original_link_program: proc "c" (program: u32)
last_linked_program: u32

track_link_program :: proc "c" (program: u32) {
	last_linked_program = program
	original_link_program(program)
}

expect_pixel :: proc(x, y: i32, expected: [4]u8) {
	pixel: [4]u8
	gl.ReadPixels(x, y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &pixel)
	for channel, i in expected {
		assert(abs(int(pixel[i]) - int(channel)) <= 2)
	}
}

smoke_shader :: proc(
	device: ^rhi.Device,
	stage: rhi.Shader_Stage,
	source: string,
) -> rhi.Shader_Handle {
	handle, err := rhi.create_shader(
		device,
		{stage = stage, source = source, label = "pipeline smoke"},
	)
	assert(err == .None)
	return handle
}

test_pipelines :: proc(platform_context: rhi.Device_Context) {
	device, err := rhi.create_device(
		platform_context,
		3,
		shader_capacity = 4,
		pipeline_capacity = 2,
	)
	assert(err == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	rhi.set_viewport(&device, 32, 32)

	settings := rhi.Pipeline_Settings {
		layout = {stride = 12, attribute_count = 1, attributes = {0 = {format = .F32x3}}},
		depth = {test_enabled = true, write_enabled = true, compare = .Less},
		raster = {cull = .Back, winding = .CCW},
	}

	// Both stages compile, but their active varying types disagree at link time.
	bad_vertex := smoke_shader(
		&device,
		.Vertex,
		"#version 410 core\nout vec3 varying_color; void main() { gl_Position = vec4(0); varying_color = vec3(1); }",
	)
	bad_fragment := smoke_shader(
		&device,
		.Fragment,
		"#version 410 core\nin vec4 varying_color; out vec4 color; void main() { color = varying_color; }",
	)
	original_link_program = gl.impl_LinkProgram
	gl.impl_LinkProgram = track_link_program
	failed, link_error := rhi.create_pipeline(
		&device,
		{
			vertex_shader = bad_vertex,
			fragment_shader = bad_fragment,
			settings = settings,
			label = "expected varying mismatch",
		},
	)
	gl.impl_LinkProgram = original_link_program
	assert(link_error == .Pipeline_Link_Failed && failed.generation == 0)
	assert(last_linked_program != 0 && !gl.IsProgram(last_linked_program))
	assert(device.pipelines.free_count == 2)
	assert(rhi.destroy_shader(&device, bad_vertex) == .None)
	assert(rhi.destroy_shader(&device, bad_fragment) == .None)

	vertex_source := vertex_source_with_suffix[:len(vertex_source_with_suffix) -
	len("THIS MUST NOT COMPILE")]
	vertex := smoke_shader(&device, .Vertex, vertex_source)
	fragment := smoke_shader(&device, .Fragment, fragment_source)
	desc := rhi.Pipeline_Desc {
		vertex_shader   = vertex,
		fragment_shader = fragment,
		settings        = settings,
	}
	good, good_error := rhi.create_pipeline(&device, desc)
	assert(good_error == .None)
	desc.settings.raster.winding = .CW
	culled, culled_error := rhi.create_pipeline(&device, desc)
	assert(culled_error == .None)
	_, full_error := rhi.create_pipeline(&device, desc)
	assert(full_error == .Pool_Exhausted)

	// Linked pipelines must remain usable after their original modules are freed.
	assert(rhi.destroy_shader(&device, vertex) == .None)
	assert(rhi.destroy_shader(&device, fragment) == .None)

	vertices := [7][3]f32 {
		{99, 99, 99},
		{-0.8, -0.8, -0.5},
		{0.8, -0.8, -0.5},
		{0, 0.8, -0.5},
		{-0.8, -0.8, 0.5},
		{0.8, -0.8, 0.5},
		{0, 0.8, 0.5},
	}
	indices16 := [4]u16{99, 0, 1, 2}
	indices32 := [3]u32{0, 1, 2}
	vb, vb_error := rhi.create_buffer(
		&device,
		{size = size_of(vertices), usage = {.Vertex}},
		mem.slice_to_bytes(vertices[:]),
	)
	assert(vb_error == .None)
	ib, ib_error := rhi.create_buffer(
		&device,
		{size = size_of(indices16), usage = {.Index}},
		mem.slice_to_bytes(indices16[:]),
	)
	assert(ib_error == .None)
	ib32, ib32_error := rhi.create_buffer(
		&device,
		{size = size_of(indices32), usage = {.Index}},
		mem.slice_to_bytes(indices32[:]),
	)
	assert(ib32_error == .None)

	assert(rhi.bind_vertex_buffer(&device, ib) == .Invalid_Buffer_Binding)
	assert(rhi.bind_index_buffer(&device, vb, .U16) == .Invalid_Buffer_Binding)
	assert(rhi.bind_vertex_buffer(&device, vb, 12) == .None)
	assert(rhi.bind_index_buffer(&device, ib, .U16) == .None)
	assert(rhi.bind_pipeline(&device, culled) == .None)
	rhi.clear(&device, {0, 0, 0, 1}, 1)
	assert(rhi.draw_indexed(&device, {index_count = 3, first_index = 1}) == .None)
	expect_pixel(16, 16, {0, 0, 0, 255})

	assert(rhi.bind_pipeline(&device, good) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 4, first_index = 1}) == .Invalid_Draw)
	assert(rhi.draw_indexed(&device, {index_count = 3, first_index = 1}) == .None)
	expect_pixel(16, 16, {255, 255, 255, 255})
	expect_pixel(0, 31, {0, 0, 0, 255})

	assert(rhi.destroy_pipeline(&device, culled) == .None)
	vertex = smoke_shader(&device, .Vertex, vertex_source)
	fragment = smoke_shader(
		&device,
		.Fragment,
		"#version 410 core\nout vec4 color; void main() { color = vec4(0, 1, 0, 1); }",
	)
	desc.vertex_shader, desc.fragment_shader = vertex, fragment
	desc.settings = settings
	desc.settings.depth.write_enabled = false
	green, green_error := rhi.create_pipeline(&device, desc)
	assert(green_error == .None)
	assert(green.index == culled.index && green.generation != culled.generation)
	assert(rhi.bind_pipeline(&device, culled) == .Invalid_Handle)
	assert(rhi.destroy_shader(&device, vertex) == .None)
	assert(rhi.destroy_shader(&device, fragment) == .None)

	// A farther green triangle must fail depth against the white triangle.
	assert(rhi.bind_pipeline(&device, green) == .None)
	assert(rhi.bind_vertex_buffer(&device, vb, 48) == .None)
	assert(rhi.bind_index_buffer(&device, ib, .U16, 2) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .None)
	expect_pixel(16, 16, {255, 255, 255, 255})

	// Clear must reset depth even though the previous pipeline disabled writes.
	rhi.clear(&device, {0, 0, 0, 1}, 1)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .None)
	expect_pixel(16, 16, {0, 255, 0, 255})

	green_native := rhi.pipeline_pool_lookup(&device.pipelines, green).native
	assert(rhi.destroy_pipeline(&device, green) == .None)
	assert(!gl.IsProgram(green_native.program) && !gl.IsVertexArray(green_native.vao))
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .Invalid_Handle)
	assert(rhi.bind_pipeline(&device, good) == .None)
	assert(rhi.destroy_buffer(&device, ib) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .Invalid_Handle)
	assert(rhi.bind_index_buffer(&device, ib32, .U32) == .None)
	rhi.clear(&device, {0, 0, 0, 1}, 1)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .None)
	expect_pixel(16, 16, {255, 255, 255, 255})

	good_native := rhi.pipeline_pool_lookup(&device.pipelines, good).native
	assert(rhi.destroy_device(&device) == .None)
	assert(!gl.IsProgram(good_native.program) && !gl.IsVertexArray(good_native.vao))
	assert(gl.GetError() == gl.NO_ERROR)
}
