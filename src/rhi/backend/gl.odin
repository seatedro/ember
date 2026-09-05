package backend

import "core:log"
import "../types"
import gl "vendor:OpenGL"
import platform_gl "../../platform/gl_context"

Device_Context :: platform_gl.Context

Device :: struct {
	platform_context: Device_Context,
}

Buffer :: struct {
	id: u32,
}

Shader :: struct {
	id: u32,
}

// Use impl_* for operations with explicit error handling. The vendor's debug
// wrappers consume glGetError themselves, which would hide allocation failures.
check_errors :: proc(operation: string) -> types.Error {
	result := types.Error.None
	for code := gl.impl_GetError(); code != gl.NO_ERROR; code = gl.impl_GetError() {
		log.errorf("OpenGL %s: error 0x%x", operation, code)
		result = .Backend_Failed
	}
	return result
}

create_device :: proc(platform_context: Device_Context) -> (Device, types.Error) {
	backend := Device{platform_context = platform_context}
	if err := validate_context(&backend); err != .None {
		return {}, err
	}
	if platform_context.load_proc == nil {
		return {}, .Unsupported_Backend
	}
	if platform_context.major < 4 || (platform_context.major == 4 && platform_context.minor < 1) {
		return {}, .Unsupported_Backend
	}

	gl.load_up_to(platform_context.major, platform_context.minor, platform_context.load_proc)
	if gl.impl_GetError == nil || gl.impl_GetIntegerv == nil ||
	   gl.impl_GenBuffers == nil || gl.impl_BindBuffer == nil ||
	   gl.impl_BufferData == nil || gl.impl_BufferSubData == nil ||
	   gl.impl_DeleteBuffers == nil || gl.impl_Finish == nil ||
	   gl.impl_Enable == nil || gl.impl_Viewport == nil ||
	   gl.impl_ClearColor == nil || gl.impl_ClearDepth == nil || gl.impl_Clear == nil ||
	   gl.impl_CreateShader == nil || gl.impl_ShaderSource == nil ||
	   gl.impl_CompileShader == nil || gl.impl_GetShaderiv == nil ||
	   gl.impl_GetShaderInfoLog == nil || gl.impl_DeleteShader == nil {
		return {}, .Unsupported_Backend
	}
	if err := check_errors("before device initialization"); err != .None {
		return {}, err
	}
	major, minor: i32
	gl.impl_GetIntegerv(gl.MAJOR_VERSION, &major)
	gl.impl_GetIntegerv(gl.MINOR_VERSION, &minor)
	if err := check_errors("query version"); err != .None {
		return {}, err
	}
	if major < 4 || (major == 4 && minor < 1) {
		return {}, .Unsupported_Backend
	}
	gl.impl_Enable(gl.DEPTH_TEST)
	if err := check_errors("enable depth test"); err != .None {
		return {}, err
	}
	return backend, .None
}

validate_context :: proc(backend: ^Device) -> types.Error {
	platform_context := backend.platform_context
	if platform_context.id == nil || platform_context.is_current == nil ||
	   !platform_context.is_current(platform_context.id) {
		return .Wrong_Context
	}
	return .None
}

create_buffer :: proc(desc: types.Buffer_Desc, initial_data: []u8) -> (Buffer, types.Error) {
	if err := check_errors("before buffer creation"); err != .None {
		return {}, err
	}

	previous: i32
	gl.impl_GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &previous)
	if err := check_errors("query buffer binding"); err != .None {
		return {}, err
	}
	// COPY_WRITE avoids changing vertex state or requiring a bound VAO for indices.
	defer gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, u32(previous))

	native: Buffer
	gl.impl_GenBuffers(1, &native.id)
	succeeded := false
	defer if !succeeded && native.id != 0 {
		gl.impl_DeleteBuffers(1, &native.id)
	}
	if err := check_errors("generate buffer"); err != .None {
		return {}, err
	}
	if native.id == 0 {
		return {}, .Backend_Failed
	}
	gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, native.id)
	if err := check_errors("bind buffer"); err != .None {
		return {}, err
	}
	gl.impl_BufferData(gl.COPY_WRITE_BUFFER, int(desc.size), nil, gl.STATIC_DRAW)
	if err := check_errors("allocate buffer"); err != .None {
		log.errorf("Buffer allocation failed: %s (%d bytes)", desc.label, desc.size)
		return {}, err
	}
	if len(initial_data) != 0 {
		gl.impl_BufferSubData(gl.COPY_WRITE_BUFFER, 0, len(initial_data), raw_data(initial_data))
		if err := check_errors("upload buffer"); err != .None {
			return {}, err
		}
	}
	succeeded = true
	return native, .None
}

wait_idle :: proc() -> types.Error {
	if err := check_errors("before wait idle"); err != .None {
		return err
	}
	gl.impl_Finish()
	return check_errors("wait idle")
}

destroy_buffer :: proc(native: ^Buffer) -> types.Error {
	if err := check_errors("before buffer deletion"); err != .None {
		return err
	}
	gl.impl_DeleteBuffers(1, &native.id)
	if err := check_errors("delete buffer"); err != .None {
		return err
	}
	native^ = {}
	return .None
}

set_viewport :: proc(width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

clear :: proc(color: [4]f32, depth: f64) {
	gl.ClearColor(color[0], color[1], color[2], color[3])
	gl.ClearDepth(depth)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

create_shader :: proc(desc: types.Shader_Desc, allocator := context.allocator) -> (Shader, types.Error) {
	kind: u32
	switch desc.stage {
	case .Vertex:   kind = gl.VERTEX_SHADER
	case .Fragment: kind = gl.FRAGMENT_SHADER
	case: return {}, .Unsupported_Shader_Stage
	}
	if err := check_errors("before shader creation"); err != .None {
		return {}, err
	}
	native := Shader{id = gl.impl_CreateShader(kind)}
	succeeded := false
	defer if !succeeded && native.id != 0 {
		gl.impl_DeleteShader(native.id)
	}
	if err := check_errors("create shader"); err != .None {
		return {}, err
	}
	if native.id == 0 {
		return {}, .Backend_Failed
	}

	// Explicit length accepts Odin string slices without a trailing zero.
	source := cstring(raw_data(desc.source))
	length := i32(len(desc.source))
	gl.impl_ShaderSource(native.id, 1, &source, &length)
	if err := check_errors("set shader source"); err != .None {
		return {}, err
	}
	gl.impl_CompileShader(native.id)
	if err := check_errors("compile shader"); err != .None {
		return {}, err
	}
	compiled: i32
	gl.impl_GetShaderiv(native.id, gl.COMPILE_STATUS, &compiled)
	if err := check_errors("query shader compilation"); err != .None {
		return {}, err
	}
	if compiled == 0 {
		log.errorf("Shader compilation failed: %s (%v)", desc.label, desc.stage)
		log_length: i32
		gl.impl_GetShaderiv(native.id, gl.INFO_LOG_LENGTH, &log_length)
		if err := check_errors("query shader log size"); err != .None {
			return {}, err
		}
		if log_length > 1 {
			bytes, allocation_error := make([]u8, int(log_length), allocator)
			if allocation_error != .None {
				log.error("Could not allocate shader diagnostic storage")
				return {}, .Allocation_Failed
			}
			defer delete(bytes, allocator)
			written: i32
			gl.impl_GetShaderInfoLog(native.id, log_length, &written, raw_data(bytes))
			if err := check_errors("read shader log"); err != .None {
				return {}, err
			}
			log.error(string(bytes[:int(written)]))
		}
		return {}, .Shader_Compile_Failed
	}
	succeeded = true
	return native, .None
}

destroy_shader :: proc(native: ^Shader) -> types.Error {
	if err := check_errors("before shader deletion"); err != .None {
		return err
	}
	gl.impl_DeleteShader(native.id)
	if err := check_errors("delete shader"); err != .None {
		return err
	}
	native^ = {}
	return .None
}
