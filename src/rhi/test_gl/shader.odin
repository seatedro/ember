package rhi_gl_smoke

import "ember:rhi"
import gl "vendor:OpenGL"

// The suffix must be excluded by the explicit length passed to glShaderSource.
vertex_source_with_suffix :: `#version 410 core
layout(location = 0) in vec3 position;
void main() { gl_Position = vec4(position, 1.0); }
THIS MUST NOT COMPILE`
fragment_source :: `#version 410 core
layout(location = 0) out vec4 color;
void main() { color = vec4(1.0); }
`

original_compile_shader: proc "c" (shader: u32)
last_compiled_shader: u32

track_compile_shader :: proc "c" (shader: u32) {
	last_compiled_shader = shader
	original_compile_shader(shader)
}

verify_shader :: proc(device: ^rhi.Device, handle: rhi.Shader_Handle, kind: u32) {
	slot := rhi.shader_pool_lookup(&device.shaders, handle)
	assert(slot != nil && gl.IsShader(slot.native.id))
	compiled, actual_kind: i32
	gl.GetShaderiv(slot.native.id, gl.COMPILE_STATUS, &compiled)
	gl.GetShaderiv(slot.native.id, gl.SHADER_TYPE, &actual_kind)
	assert(compiled != 0 && u32(actual_kind) == kind)
}

// Leaves both stages live for the device shutdown test.
test_shaders :: proc(device: ^rhi.Device) -> (rhi.Shader_Handle, rhi.Shader_Handle) {
	vertex_desc := rhi.Shader_Desc {
		stage  = .Vertex,
		source = vertex_source_with_suffix[:len(
			vertex_source_with_suffix,
		) - len("THIS MUST NOT COMPILE")],
		label  = "smoke vertex",
	}
	fragment_desc := rhi.Shader_Desc {
		stage  = .Fragment,
		source = fragment_source,
		label  = "smoke fragment",
	}
	invalid_desc := vertex_desc
	invalid_desc.source = ""
	_, empty_error := rhi.create_shader(device, invalid_desc)
	assert(empty_error == .Invalid_Shader_Source)
	invalid_desc = vertex_desc
	invalid_desc.stage = rhi.Shader_Stage(99)
	_, stage_error := rhi.create_shader(device, invalid_desc)
	assert(stage_error == .Unsupported_Shader_Stage)
	assert(device.shaders.free_count == 2)

	// Compilation failure is a status result, not a glGetError failure.
	original_compile_shader = gl.impl_CompileShader
	gl.impl_CompileShader = track_compile_shader
	defer gl.impl_CompileShader = original_compile_shader
	invalid_desc = vertex_desc
	invalid_desc.source = "#version 410 core\nvoid main() { gl_Position = ; }\n"
	invalid_desc.label = "expected syntax error"
	failed, compile_error := rhi.create_shader(device, invalid_desc)
	assert(compile_error == .Shader_Compile_Failed && failed.generation == 0)
	assert(last_compiled_shader != 0 && !gl.IsShader(last_compiled_shader))
	assert(device.shaders.free_count == 2)
	assert(gl.GetError() == gl.NO_ERROR)

	vertex, vertex_error := rhi.create_shader(device, vertex_desc)
	assert(vertex_error == .None)
	fragment, fragment_error := rhi.create_shader(device, fragment_desc)
	assert(fragment_error == .None)
	verify_shader(device, vertex, gl.VERTEX_SHADER)
	verify_shader(device, fragment, gl.FRAGMENT_SHADER)
	_, full_error := rhi.create_shader(device, vertex_desc)
	assert(full_error == .Pool_Exhausted)
	vertex_id := rhi.shader_pool_lookup(&device.shaders, vertex).native.id
	assert(rhi.destroy_shader(device, vertex) == .None)
	assert(!gl.IsShader(vertex_id))
	assert(rhi.destroy_shader(device, vertex) == .Invalid_Handle)
	replacement, replacement_error := rhi.create_shader(device, vertex_desc)
	assert(replacement_error == .None)
	assert(replacement.index == vertex.index && replacement.generation != vertex.generation)
	assert(rhi.shader_pool_lookup(&device.shaders, vertex) == nil)
	return replacement, fragment
}
