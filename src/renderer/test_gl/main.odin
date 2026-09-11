// odin run src/renderer/test_gl -collection:ember=src
package renderer_gl_smoke

import "core:fmt"
import "ember:camera"
import emath "ember:core/math"
import "ember:geometry"
import win "ember:platform/window"
import render "ember:renderer"
import "ember:rhi"
import shader "ember:shaders"
import gl "vendor:OpenGL"
import "vendor:glfw"

load_shader :: proc(device: ^rhi.Device) -> (shader.Library, shader.Shader) {
	library := shader.create(device)
	program, err := shader.load(&library, "game/assets/shaders/banded")
	assert(err == .None)
	return library, program
}

test_failed_creation :: proc(platform_context: rhi.Device_Context) {
	// Renderer creation reaches the uniform allocation after building its pipeline.
	device, err := rhi.create_device(platform_context, 1)
	assert(err == .None)
	occupied, occupied_error := rhi.create_buffer(&device, {size = 4, usage = {.Vertex}})
	assert(occupied_error == .None)
	library, program := load_shader(&device)
	failed, failure := render.create(&device, program)
	assert(failure == .Pool_Exhausted && failed == render.Renderer{})
	assert(device.buffers.free_count == 0)
	assert(device.shaders.free_count == len(device.shaders.slots) - 2)
	assert(device.pipelines.free_count == len(device.pipelines.slots))
	assert(rhi.destroy_buffer(&device, occupied) == .None)
	assert(shader.destroy(&library) == .None)
	assert(rhi.destroy_device(&device) == .None)

	// Grid creation allocates buffers, then fails to obtain a second pipeline.
	device, err = rhi.create_device(platform_context, 4, pipeline_capacity = 1)
	assert(err == .None)
	library, program = load_shader(&device)
	renderer, renderer_error := render.create(&device, program)
	assert(renderer_error == .None)
	grid, grid_error := render.create_grid(&renderer)
	assert(grid_error == .Pool_Exhausted && grid == render.Grid{})
	assert(device.buffers.free_count == 3)
	assert(device.shaders.free_count == len(device.shaders.slots) - 2)
	assert(render.destroy(&renderer) == .None)
	assert(device.pipelines.free_count == 1)
	assert(shader.destroy(&library) == .None)
	assert(rhi.destroy_device(&device) == .None)
}

main :: proc() {
	assert(bool(glfw.Init()))
	defer glfw.Terminate()
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	window := glfw.CreateWindow(128, 64, "Ember renderer smoke", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	platform_window := win.Window {
		handle = window,
	}
	platform_context := win.gl_context(&platform_window)
	test_failed_creation(platform_context)
	vertices := [3]geometry.Vertex {
		{{-0.2, -0.25, 0}, {0, 0, 1}},
		{{0.2, -0.25, 0}, {0, 0, 1}},
		{{0, 0.3, 0}, {0, 0, 1}},
	}
	indices := [3]u32{0, 1, 2}

	// Only one buffer slot remains after creating the renderer.
	small, err := rhi.create_device(platform_context, 2)
	assert(err == .None)
	small_library, small_program := load_shader(&small)
	small_renderer, small_error := render.create(&small, small_program)
	assert(small_error == .None)
	failed, failure := render.create_mesh(&small_renderer, vertices[:], indices[:])
	assert(failure == .Pool_Exhausted && failed == render.Mesh{})
	assert(small.buffers.free_count == 1)
	assert(render.destroy(&small_renderer) == .None)
	assert(shader.destroy(&small_library) == .None)
	assert(rhi.destroy_device(&small) == .None)

	device, device_error := rhi.create_device(platform_context, 6)
	assert(device_error == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	library, program := load_shader(&device)
	renderer, renderer_error := render.create(&device, program)
	assert(renderer_error == .None)
	invalid_indices := [3]u32{0, 1, 3}
	invalid, invalid_error := render.create_mesh(&renderer, vertices[:], invalid_indices[:])
	assert(invalid_error == .Invalid_Draw && invalid == render.Mesh{})
	_, empty_error := render.create_mesh(&renderer, vertices[:0], indices[:])
	assert(empty_error == .Invalid_Size && device.buffers.free_count == 5)
	mesh, mesh_error := render.create_mesh(&renderer, vertices[:], indices[:])
	assert(mesh_error == .None)
	grid, grid_error := render.create_grid(&renderer)
	assert(grid_error == .None && device.buffers.free_count == 0)
	// Drawing must use the uploaded copy, independent of these CPU slices.
	vertices = {}
	indices = {}
	glfw.MakeContextCurrent(nil)
	assert(render.destroy_mesh(&renderer, &mesh) == .Wrong_Context)
	assert(mesh.vertices.generation != 0 && mesh.indices.generation != 0)
	assert(render.destroy_grid(&renderer, &grid) == .Wrong_Context)
	assert(grid.pipeline.generation != 0 && grid.uniforms.generation != 0)
	assert(render.destroy(&renderer) == .Wrong_Context)
	assert(renderer.pipeline.generation != 0 && renderer.uniforms.generation != 0)
	glfw.MakeContextCurrent(window)

	width, height := glfw.GetFramebufferSize(window)
	rhi.set_viewport(&device, width, height)
	assert(
		render.begin_frame(
			&renderer,
			camera.Camera{orientation = 1},
			emath.identity(),
			{0, 0, 0, 1},
		) ==
		.None,
	)
	assert(render.draw_grid(&renderer, &grid) == .None)
	for i in 0 ..< 3 {
		scale := 0.7 + f32(i) * 0.25
		transform := emath.Transform {
			position    = {f32(i - 1) * 0.6, 0, 0},
			orientation = emath.quaternion_angle_axis(f32(i - 1) * 0.4, {0, 0, 1}),
			scale       = {scale, scale, scale},
		}
		assert(render.draw_mesh(&renderer, &mesh, transform) == .None)
	}
	// Read after every draw: all three placements must survive later uniform writes.
	for i in 0 ..< 3 {
		x := f32(i - 1) * 0.6
		pixel: [4]u8
		gl.ReadPixels(
			i32((x * 0.5 + 0.5) * f32(width)),
			height / 2,
			1,
			1,
			gl.RGBA,
			gl.UNSIGNED_BYTE,
			&pixel,
		)
		assert(int(pixel[2]) > int(pixel[0]) + 30 && pixel[3] == 255)
	}
	assert(device.buffers.free_count == 0)
	assert(gl.GetError() == gl.NO_ERROR)
	borrowed := mesh
	vertex_id := rhi.buffer_pool_lookup(&device.buffers, mesh.vertices).native.id
	index_id := rhi.buffer_pool_lookup(&device.buffers, mesh.indices).native.id
	assert(render.destroy_mesh(&renderer, &mesh) == .None)
	assert(mesh == render.Mesh{} && !gl.IsBuffer(vertex_id) && !gl.IsBuffer(index_id))
	assert(
		render.draw_mesh(&renderer, &borrowed, {orientation = 1, scale = {1, 1, 1}}) ==
		.Invalid_Handle,
	)
	assert(render.destroy_mesh(&renderer, &mesh) == .None)
	assert(render.destroy_grid(&renderer, &grid) == .None)
	assert(render.destroy(&renderer) == .None)
	assert(shader.destroy(&library) == .None)
	assert(device.buffers.free_count == 6)
	assert(device.pipelines.free_count == len(device.pipelines.slots))
	assert(device.shaders.free_count == len(device.shaders.slots))
	fmt.println(
		"Renderer smoke passed: creation rollback, mesh/grid ownership, three transforms, pixels, cleanup",
	)
}
