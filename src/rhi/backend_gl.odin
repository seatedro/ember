package rhi

import "core:log"
import gl "vendor:OpenGL"
import platform_gl "../platform/gl_context"

Device_Context :: platform_gl.Context

Backend_Device :: struct {
	platform_context: Device_Context,
}

Backend_Buffer :: struct {
	id: u32,
}

// Use impl_* for operations with explicit error handling. The vendor's debug
// wrappers consume glGetError themselves, which would hide allocation failures.
backend_check_errors :: proc(operation: string) -> Error {
	result := Error.None
	for code := gl.impl_GetError(); code != gl.NO_ERROR; code = gl.impl_GetError() {
		log.errorf("OpenGL %s: error 0x%x", operation, code)
		result = .Backend_Failed
	}
	return result
}

backend_create_device :: proc(platform_context: Device_Context) -> (Backend_Device, Error) {
	backend := Backend_Device{platform_context = platform_context}
	if err := backend_validate_context(&backend); err != .None {
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
	   gl.impl_ClearColor == nil || gl.impl_ClearDepth == nil || gl.impl_Clear == nil {
		return {}, .Unsupported_Backend
	}
	if err := backend_check_errors("before device initialization"); err != .None {
		return {}, err
	}
	major, minor: i32
	gl.impl_GetIntegerv(gl.MAJOR_VERSION, &major)
	gl.impl_GetIntegerv(gl.MINOR_VERSION, &minor)
	if err := backend_check_errors("query version"); err != .None {
		return {}, err
	}
	if major < 4 || (major == 4 && minor < 1) {
		return {}, .Unsupported_Backend
	}
	gl.impl_Enable(gl.DEPTH_TEST)
	if err := backend_check_errors("enable depth test"); err != .None {
		return {}, err
	}
	return backend, .None
}

backend_validate_context :: proc(backend: ^Backend_Device) -> Error {
	platform_context := backend.platform_context
	if platform_context.id == nil || platform_context.is_current == nil ||
	   !platform_context.is_current(platform_context.id) {
		return .Wrong_Context
	}
	return .None
}

backend_create_buffer :: proc(desc: Buffer_Desc, initial_data: []u8) -> (Backend_Buffer, Error) {
	if err := backend_check_errors("before buffer creation"); err != .None {
		return {}, err
	}

	previous: i32
	gl.impl_GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &previous)
	if err := backend_check_errors("query buffer binding"); err != .None {
		return {}, err
	}
	// COPY_WRITE avoids changing vertex state or requiring a bound VAO for indices.
	defer gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, u32(previous))

	native: Backend_Buffer
	gl.impl_GenBuffers(1, &native.id)
	succeeded := false
	defer if !succeeded && native.id != 0 {
		gl.impl_DeleteBuffers(1, &native.id)
	}
	if err := backend_check_errors("generate buffer"); err != .None {
		return {}, err
	}
	if native.id == 0 {
		return {}, .Backend_Failed
	}
	gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, native.id)
	if err := backend_check_errors("bind buffer"); err != .None {
		return {}, err
	}
	gl.impl_BufferData(gl.COPY_WRITE_BUFFER, int(desc.size), nil, gl.STATIC_DRAW)
	if err := backend_check_errors("allocate buffer"); err != .None {
		log.errorf("Buffer allocation failed: %s (%d bytes)", desc.label, desc.size)
		return {}, err
	}
	if len(initial_data) != 0 {
		gl.impl_BufferSubData(gl.COPY_WRITE_BUFFER, 0, len(initial_data), raw_data(initial_data))
		if err := backend_check_errors("upload buffer"); err != .None {
			return {}, err
		}
	}
	succeeded = true
	return native, .None
}

backend_wait_idle :: proc() -> Error {
	if err := backend_check_errors("before wait idle"); err != .None {
		return err
	}
	gl.impl_Finish()
	return backend_check_errors("wait idle")
}

backend_destroy_buffer :: proc(native: ^Backend_Buffer) -> Error {
	if err := backend_check_errors("before buffer deletion"); err != .None {
		return err
	}
	gl.impl_DeleteBuffers(1, &native.id)
	if err := backend_check_errors("delete buffer"); err != .None {
		return err
	}
	native^ = {}
	return .None
}

backend_set_viewport :: proc(width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

backend_clear :: proc(color: [4]f32, depth: f64) {
	gl.ClearColor(color[0], color[1], color[2], color[3])
	gl.ClearDepth(depth)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}
