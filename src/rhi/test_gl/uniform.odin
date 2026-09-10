package rhi_gl_smoke

import "core:mem"
import emath "ember:core/math"
import "ember:rhi"
import gl "vendor:OpenGL"

Draw_Data :: struct {
	mvp:  emath.Mat4,
	tint: [4]f32,
}

uniform_vertex_source :: `#version 410 core
layout(location = 0) in vec3 position;
layout(std140) uniform Draw_Data { mat4 mvp; vec4 tint; };
void main() { gl_Position = mvp * vec4(position, 1.0); }
`
uniform_fragment_source :: `#version 410 core
layout(std140) uniform Draw_Data { mat4 mvp; vec4 tint; };
out vec4 color;
void main() { color = tint; }
`

test_uniforms :: proc(platform_context: rhi.Device_Context) {
	device, err := rhi.create_device(
		platform_context,
		4,
		shader_capacity = 2,
		pipeline_capacity = 1,
	)
	assert(err == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	rhi.set_viewport(&device, 32, 32)

	vertex := smoke_shader(&device, .Vertex, uniform_vertex_source)
	fragment := smoke_shader(&device, .Fragment, uniform_fragment_source)
	desc := rhi.Pipeline_Desc {
		vertex_shader = vertex,
		fragment_shader = fragment,
		settings = {
			layout = {stride = 12, attribute_count = 1, attributes = {0 = {format = .F32x3}}},
		},
	}
	_, missing_error := rhi.create_pipeline(&device, desc)
	assert(missing_error == .Invalid_Uniform_Binding && device.pipelines.free_count == 1)
	desc.uniform_blocks = {{name = "Does_Not_Exist", binding = 3}}
	_, name_error := rhi.create_pipeline(&device, desc)
	assert(name_error == .Invalid_Uniform_Binding && device.pipelines.free_count == 1)
	desc.uniform_blocks = {{name = "Draw_Data", binding = 3}}
	pipeline, pipeline_error := rhi.create_pipeline(&device, desc)
	assert(pipeline_error == .None)
	assert(
		rhi.pipeline_pool_lookup(&device.pipelines, pipeline).uniform_sizes[3] ==
		u64(offset_of(Draw_Data, tint) + size_of([4]f32)),
	)
	assert(rhi.destroy_shader(&device, vertex) == .None)
	assert(rhi.destroy_shader(&device, fragment) == .None)

	vertices := [3][3]f32{{-0.6, -0.6, 0}, {0.6, -0.6, 0}, {0, 0.6, 0}}
	indices := [3]u16{0, 1, 2}
	vb, vb_error := rhi.create_buffer(
		&device,
		{size = size_of(vertices), usage = {.Vertex}},
		mem.slice_to_bytes(vertices[:]),
	)
	assert(vb_error == .None)
	ib, ib_error := rhi.create_buffer(
		&device,
		{size = size_of(indices), usage = {.Index}},
		mem.slice_to_bytes(indices[:]),
	)
	assert(ib_error == .None)
	ubo, ubo_error := rhi.create_buffer(&device, {size = size_of(Draw_Data), usage = {.Uniform}})
	assert(ubo_error == .None)
	small, small_error := rhi.create_buffer(&device, {size = 16, usage = {.Uniform}})
	assert(small_error == .None)
	assert(rhi.bind_pipeline(&device, pipeline) == .None)
	assert(rhi.bind_vertex_buffer(&device, vb) == .None)
	assert(rhi.bind_index_buffer(&device, ib, .U16) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .Invalid_Handle)
	assert(rhi.bind_uniform_buffer(&device, 3, vb) == .Invalid_Buffer_Binding)
	assert(
		rhi.bind_uniform_buffer(&device, rhi.MAX_UNIFORM_BINDINGS, ubo) ==
		.Invalid_Uniform_Binding,
	)
	assert(rhi.bind_uniform_buffer(&device, 3, small) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .Invalid_Buffer_Binding)
	assert(rhi.bind_uniform_buffer(&device, 3, ubo) == .None)

	// Native sentinel verifies that drawing restores indexed and generic bindings.
	sentinel: u32
	gl.GenBuffers(1, &sentinel)
	gl.BindBuffer(gl.UNIFORM_BUFFER, sentinel)
	gl.BufferData(gl.UNIFORM_BUFFER, size_of(Draw_Data), nil, gl.STATIC_DRAW)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 3, sentinel)
	defer gl.DeleteBuffers(1, &sentinel)

	projection := emath.perspective(1.570796327, 1, 0.1, 10)
	view := emath.look_at({0, 0, 2}, {0, 0, 0}, {0, 1, 0})
	data := [1]Draw_Data {
		{mvp = projection * view * emath.translation({-1, 0, 0}), tint = {1, 0, 0, 1}},
	}
	bytes := mem.slice_to_bytes(data[:])
	assert(rhi.update_buffer(&device, ubo, 0, bytes) == .None)
	rhi.clear(&device, {0, 0, 0, 1}, 1)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .None)

	// Reuse CPU storage and update the same GPU buffer between queued draws.
	data[0] = {
		mvp  = projection * view * emath.translation({1, 0, 0}),
		tint = {0, 1, 0, 1},
	}
	assert(rhi.update_buffer(&device, ubo, 0, bytes[:64]) == .None)
	assert(rhi.update_buffer(&device, ubo, 64, bytes[64:]) == .None)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .None)
	expect_pixel(8, 16, {255, 0, 0, 255})
	expect_pixel(24, 16, {0, 255, 0, 255})
	expect_pixel(16, 31, {0, 0, 0, 255})

	binding: i32
	gl.GetIntegeri_v(gl.UNIFORM_BUFFER_BINDING, 3, &binding)
	assert(u32(binding) == sentinel)
	gl.GetIntegerv(gl.UNIFORM_BUFFER_BINDING, &binding)
	assert(u32(binding) == sentinel)
	assert(rhi.update_buffer(&device, ubo, size_of(Draw_Data), bytes[:1]) == .Invalid_Buffer_Range)
	assert(rhi.update_buffer(&device, ubo, size_of(Draw_Data), nil) == .None)
	verify_contents(&device, ubo, bytes, size_of(Draw_Data))
	assert(rhi.destroy_buffer(&device, ubo) == .None)
	assert(rhi.update_buffer(&device, ubo, 0, bytes) == .Invalid_Handle)
	assert(rhi.draw_indexed(&device, {index_count = 3}) == .Invalid_Handle)
}
