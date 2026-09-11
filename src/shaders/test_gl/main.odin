// odin run src/shaders/test_gl -collection:ember=src
package shader_library_gl_smoke

import "core:fmt"
import "core:log"
import win "ember:platform/window"
import "ember:rhi"
import shader "ember:shaders"
import gl "vendor:OpenGL"
import "vendor:glfw"

VALID :: "src/shaders/test_gl/fixtures/valid"
INVALID :: "src/shaders/test_gl/fixtures/invalid"

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger
	assert(bool(glfw.Init()))
	defer glfw.Terminate()
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	window := glfw.CreateWindow(32, 32, "Shader library smoke", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	platform_window := win.Window {
		handle = window,
	}
	platform_context := win.gl_context(&platform_window)
	device, err := rhi.create_device(platform_context, shader_capacity = 4)
	assert(err == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	library := shader.create(&device)
	missing, missing_error := shader.load(&library, "src/shaders/test_gl/fixtures/missing")
	assert(missing_error == .Read_Failed && missing == shader.Shader{})
	assert(len(library.entries) == 0 && device.shaders.free_count == 4)
	loaded, loaded_error := shader.load(&library, VALID)
	assert(loaded_error == .None && device.shaders.free_count == 2)
	cached, cached_error := shader.load(&library, "src/shaders/test_gl/fixtures/./valid")
	assert(cached_error == .None && cached == loaded)
	assert(len(library.entries) == 1 && device.shaders.free_count == 2)
	// The vertex stage compiles before the fragment stage fails.
	invalid, invalid_error := shader.load(&library, INVALID)
	assert(invalid_error == .GPU_Failed && invalid == shader.Shader{})
	assert(len(library.entries) == 1 && device.shaders.free_count == 2)
	vertex_id := rhi.shader_pool_lookup(&device.shaders, loaded.vertex).native.id
	fragment_id := rhi.shader_pool_lookup(&device.shaders, loaded.fragment).native.id
	glfw.MakeContextCurrent(nil)
	assert(shader.destroy(&library) == .GPU_Failed)
	assert(len(library.entries) == 1)
	_, closed_error := shader.load(&library, VALID)
	assert(closed_error == .Invalid_Library)
	glfw.MakeContextCurrent(window)
	assert(shader.destroy(&library) == .None)
	assert(!gl.IsShader(vertex_id) && !gl.IsShader(fragment_id))
	assert(device.shaders.free_count == 4)
	assert(rhi.shader_pool_lookup(&device.shaders, loaded.vertex) == nil)
	assert(shader.destroy(&library) == .None)
	_, destroyed_error := shader.load(&library, VALID)
	assert(destroyed_error == .Invalid_Library)

	// A full pool after the vertex stage must also roll back the partial load.
	small, small_error := rhi.create_device(platform_context, shader_capacity = 1)
	assert(small_error == .None)
	small_library := shader.create(&small)
	partial, partial_error := shader.load(&small_library, VALID)
	assert(partial_error == .GPU_Failed && partial == shader.Shader{})
	assert(len(small_library.entries) == 0 && small.shaders.free_count == 1)
	assert(shader.destroy(&small_library) == .None)
	assert(rhi.destroy_device(&small) == .None)
	fmt.println(
		"Shader library smoke passed: files, cached reuse, compile failure rollback, context retry, cleanup",
	)
}
