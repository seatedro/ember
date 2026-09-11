// odin run src/renderer/test_gl -collection:ember=src
package renderer_gl_smoke

import "core:fmt"
import "ember:camera"
import emath "ember:core/math"
import "ember:geometry"
import win "ember:platform/window"
import render "ember:renderer"
import "ember:rhi"
import gl "vendor:OpenGL"
import "vendor:glfw"

main :: proc() {
	assert(bool(glfw.Init()))
	defer glfw.Terminate()
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	window := glfw.CreateWindow(64, 64, "Ember renderer smoke", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	platform_window := win.Window {
		handle = window,
	}
	platform_context := win.gl_context(&platform_window)
	vertices := [3]geometry.Sphere_Vertex {
		{{-0.5, -0.5, 0}, {0, 0, 1}},
		{{0.5, -0.5, 0}, {0, 0, 1}},
		{{0, 0.5, 0}, {0, 0, 1}},
	}
	indices := [3]u32{0, 1, 2}
	// Exhaust the pool after one buffer has been created.
	small, small_error := rhi.create_device(platform_context, 1)
	assert(small_error == .None)
	failed, failure := render.create(&small, vertices[:], indices[:])
	assert(failure == .Pool_Exhausted && failed == render.Renderer{})
	assert(small.buffers.free_count == 1)
	assert(rhi.destroy_device(&small) == .None)

	device, err := rhi.create_device(platform_context, 6)
	assert(err == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	renderer, renderer_error := render.create(&device, vertices[:], indices[:])
	assert(renderer_error == .None)
	grid, grid_error := render.create_grid(&renderer)
	assert(grid_error == .None && device.buffers.free_count == 0)
	vertices = {}
	indices = {}
	width, height := glfw.GetFramebufferSize(window)
	rhi.set_viewport(&device, width, height)
	assert(
		render.begin_frame(&renderer, camera.Camera{orientation = 1}, emath.identity()) == .None,
	)
	assert(render.draw_grid(&renderer, &grid) == .None)
	assert(render.draw(&renderer, {orientation = 1, scale = {1, 1, 1}}) == .None)
	pixel: [4]u8
	gl.ReadPixels(width / 2, height / 2, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &pixel)
	assert(int(pixel[2]) > int(pixel[0]) + 30)
	assert(gl.GetError() == gl.NO_ERROR)
	glfw.MakeContextCurrent(nil)
	assert(render.destroy_grid(&renderer, &grid) == .Wrong_Context)
	assert(render.destroy(&renderer) == .Wrong_Context)
	assert(renderer.pipeline.generation != 0 && renderer.vertices.generation != 0)
	glfw.MakeContextCurrent(window)
	assert(render.destroy_grid(&renderer, &grid) == .None)
	assert(render.destroy(&renderer) == .None)
	assert(device.buffers.free_count == 6)
	assert(device.pipelines.free_count == len(device.pipelines.slots))
	assert(device.shaders.free_count == len(device.shaders.slots))
	fmt.println("Renderer smoke passed: upload rollback, pixels, grid bindings, cleanup")
}
