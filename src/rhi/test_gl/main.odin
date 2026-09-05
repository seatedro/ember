// Run on the main thread (GLFW on macOS cannot run in odin test workers):
// odin run src/rhi/test_gl -collection:ember=src -out:/tmp/ember-rhi-gl-smoke
package rhi_gl_smoke

import "core:fmt"
import "core:log"
import "ember:rhi"
import win "ember:platform/window"
import gl "vendor:OpenGL"
import "vendor:glfw"

failed_native_id: u32

fail_buffer_data :: proc "c" (target: u32, size: int, data: rawptr, usage: u32) {
	binding: i32
	gl.impl_GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &binding)
	failed_native_id = u32(binding)
	// Generate a real GL error after the object has been created and bound.
	gl.impl_BindBuffer(max(u32), 0)
}

verify_contents :: proc(device: ^rhi.Device, handle: rhi.Buffer_Handle, expected: []u8, size: int) {
	slot := rhi.buffer_pool_lookup(&device.buffers, handle)
	assert(slot != nil)
	assert(gl.IsBuffer(slot.native.id))
	previous: i32
	gl.GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &previous)
	gl.BindBuffer(gl.COPY_WRITE_BUFFER, slot.native.id)
	defer gl.BindBuffer(gl.COPY_WRITE_BUFFER, u32(previous))
	actual_size: i32
	gl.GetBufferParameteriv(gl.COPY_WRITE_BUFFER, gl.BUFFER_SIZE, &actual_size)
	assert(int(actual_size) == size)
	actual := make([]u8, len(expected))
	defer delete(actual)
	gl.GetBufferSubData(gl.COPY_WRITE_BUFFER, 0, len(actual), raw_data(actual))
	for byte, i in expected {
		assert(actual[i] == byte)
	}
	assert(gl.GetError() == gl.NO_ERROR)
}

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
	window := glfw.CreateWindow(32, 32, "Ember buffer smoke", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)
	platform_window := win.Window{handle = window}
	platform_context := win.gl_context(&platform_window)

	// Failed initialization releases the already allocated pool.
	missing, missing_error := rhi.create_device(platform_context, 2)
	assert(missing_error == .Wrong_Context && !missing.initialized)
	glfw.MakeContextCurrent(window)
	device, err := rhi.create_device(platform_context, 2, shader_capacity = 2)
	assert(err == .None)
	defer assert(rhi.destroy_device(&device) == .None)
	major, minor: i32
	gl.GetIntegerv(gl.MAJOR_VERSION, &major)
	gl.GetIntegerv(gl.MINOR_VERSION, &minor)
	assert(gl.loaded_up_to_major == int(major))
	assert(gl.loaded_up_to_minor == int(minor))

	sentinel: u32
	gl.GenBuffers(1, &sentinel)
	gl.BindBuffer(gl.COPY_WRITE_BUFFER, sentinel)
	defer gl.DeleteBuffers(1, &sentinel)

	bytes := [8]u8{1, 2, 3, 4, 250, 251, 252, 253}
	vertex_desc := rhi.Buffer_Desc{size = 16, usage = {.Vertex}, label = "smoke vertices"}
	index_desc := rhi.Buffer_Desc{size = 8, usage = {.Index}, label = "smoke indices"}
	invalid_desc := vertex_desc
	invalid_desc.size = 0
	invalid, invalid_error := rhi.create_buffer(&device, invalid_desc)
	assert(invalid_error == .Invalid_Size && invalid.generation == 0)
	assert(device.buffers.free_count == 2)

	// Inject a native allocation failure to verify rollback of the object and slot.
	original_buffer_data := gl.impl_BufferData
	gl.impl_BufferData = fail_buffer_data
	failed, failed_error := rhi.create_buffer(&device, vertex_desc, bytes[:])
	gl.impl_BufferData = original_buffer_data
	assert(failed_error == .Backend_Failed && failed.generation == 0)
	assert(failed_native_id != 0 && !gl.IsBuffer(failed_native_id))
	assert(device.buffers.free_count == 2)
	binding: i32
	gl.GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &binding)
	assert(u32(binding) == sentinel)

	vertex, vertex_error := rhi.create_buffer(&device, vertex_desc, bytes[:])
	assert(vertex_error == .None)
	index, index_error := rhi.create_buffer(&device, index_desc, bytes[:])
	assert(index_error == .None)
	gl.GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &binding)
	assert(u32(binding) == sentinel)
	verify_contents(&device, vertex, bytes[:], 16)
	verify_contents(&device, index, bytes[:], 8)
	_, full_error := rhi.create_buffer(&device, vertex_desc)
	assert(full_error == .Pool_Exhausted)
	vertex_shader, fragment_shader := test_shaders(&device)

	// Missing context must preserve live buffers and device ownership.
	glfw.MakeContextCurrent(nil)
	_, wrong_create := rhi.create_buffer(&device, vertex_desc)
	assert(wrong_create == .Wrong_Context)
	assert(rhi.destroy_buffer(&device, vertex) == .Wrong_Context)
	_, wrong_shader_create := rhi.create_shader(&device, rhi.Shader_Desc{source = "void main() {}"})
	assert(wrong_shader_create == .Wrong_Context)
	assert(rhi.destroy_shader(&device, vertex_shader) == .Wrong_Context)
	assert(rhi.destroy_device(&device) == .Wrong_Context)
	assert(device.initialized)

	// A different current context must also fail the platform identity check.
	other_window := glfw.CreateWindow(32, 32, "Other context", nil, nil)
	assert(other_window != nil)
	defer glfw.DestroyWindow(other_window)
	glfw.MakeContextCurrent(other_window)
	assert(rhi.destroy_buffer(&device, vertex) == .Wrong_Context)
	assert(rhi.destroy_shader(&device, vertex_shader) == .Wrong_Context)
	assert(rhi.destroy_device(&device) == .Wrong_Context)
	glfw.MakeContextCurrent(window)

	vertex_id := rhi.buffer_pool_lookup(&device.buffers, vertex).native.id
	assert(rhi.destroy_buffer(&device, vertex) == .None)
	assert(!gl.IsBuffer(vertex_id))
	assert(rhi.destroy_buffer(&device, vertex) == .Invalid_Handle)
	replacement, replacement_error := rhi.create_buffer(&device, vertex_desc)
	assert(replacement_error == .None)
	assert(replacement.index == vertex.index && replacement.generation != vertex.generation)
	assert(rhi.buffer_pool_lookup(&device.buffers, vertex) == nil)

	index_id := rhi.buffer_pool_lookup(&device.buffers, index).native.id
	replacement_id := rhi.buffer_pool_lookup(&device.buffers, replacement).native.id
	vertex_shader_id := rhi.shader_pool_lookup(&device.shaders, vertex_shader).native.id
	fragment_shader_id := rhi.shader_pool_lookup(&device.shaders, fragment_shader).native.id
	assert(rhi.destroy_device(&device) == .None)
	assert(!gl.IsBuffer(index_id) && !gl.IsBuffer(replacement_id))
	assert(!gl.IsShader(vertex_shader_id) && !gl.IsShader(fragment_shader_id))
	assert(!device.initialized && len(device.buffers.slots) == 0)
	assert(len(device.shaders.slots) == 0)
	_, dead_error := rhi.create_buffer(&device, vertex_desc)
	assert(dead_error == .Device_Not_Initialized)
	assert(gl.GetError() == gl.NO_ERROR)
	fmt.println("OpenGL smoke passed: buffers, shader compilation/diagnostics, rollback, reuse, context checks, shutdown")
}
