package backend

import platform_gl "../../platform/gl_context"
import "../types"
import "core:log"
import "core:strings"
import gl "vendor:OpenGL"

Device_Context :: platform_gl.Context

Device :: struct {
	platform_context: Device_Context,
}

Buffer :: struct {
	id: u32,
}

Texture :: struct {
	id, sampler: u32,
}

Shader :: struct {
	id: u32,
}

Pipeline :: struct {
	program:          u32,
	vao:              u32,
	uniform_sizes:    [types.MAX_UNIFORM_BINDINGS]u64,
	texture_bindings: [types.MAX_TEXTURE_BINDINGS]bool,
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
	backend := Device {
		platform_context = platform_context,
	}

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
	if gl.impl_GetError == nil ||
	   gl.impl_GetIntegerv == nil ||
	   gl.impl_GenBuffers == nil ||
	   gl.impl_BindBuffer == nil ||
	   gl.impl_BufferData == nil ||
	   gl.impl_BufferSubData == nil ||
	   gl.impl_DeleteBuffers == nil ||
	   gl.impl_Finish == nil ||
	   gl.impl_Enable == nil ||
	   gl.impl_Viewport == nil ||
	   gl.impl_ClearColor == nil ||
	   gl.impl_ClearDepth == nil ||
	   gl.impl_Clear == nil ||
	   gl.impl_CreateShader == nil ||
	   gl.impl_ShaderSource == nil ||
	   gl.impl_CompileShader == nil ||
	   gl.impl_GetShaderiv == nil ||
	   gl.impl_GetShaderInfoLog == nil ||
	   gl.impl_DeleteShader == nil ||
	   gl.impl_CreateProgram == nil ||
	   gl.impl_DeleteProgram == nil ||
	   gl.impl_AttachShader == nil ||
	   gl.impl_DetachShader == nil ||
	   gl.impl_LinkProgram == nil ||
	   gl.impl_GetProgramiv == nil ||
	   gl.impl_GetProgramInfoLog == nil ||
	   gl.impl_UseProgram == nil ||
	   gl.impl_GenVertexArrays == nil ||
	   gl.impl_DeleteVertexArrays == nil ||
	   gl.impl_BindVertexArray == nil ||
	   gl.impl_VertexAttribPointer == nil ||
	   gl.impl_EnableVertexAttribArray == nil ||
	   gl.impl_DrawElements == nil ||
	   gl.impl_Disable == nil ||
	   gl.impl_DepthMask == nil ||
	   gl.impl_DepthFunc == nil ||
	   gl.impl_CullFace == nil ||
	   gl.impl_FrontFace == nil ||
	   gl.impl_PolygonMode == nil ||
	   gl.impl_ColorMask == nil ||
	   gl.impl_GetUniformBlockIndex == nil ||
	   gl.impl_UniformBlockBinding == nil ||
	   gl.impl_GetActiveUniformBlockiv == nil ||
	   gl.impl_BindBufferBase == nil ||
	   gl.impl_GetIntegeri_v == nil ||
	   gl.impl_GenTextures == nil ||
	   gl.impl_DeleteTextures == nil ||
	   gl.impl_BindTexture == nil ||
	   gl.impl_ActiveTexture == nil ||
	   gl.impl_TexImage2D == nil ||
	   gl.impl_TexParameteri == nil ||
	   gl.impl_PixelStorei == nil ||
	   gl.impl_GenSamplers == nil ||
	   gl.impl_DeleteSamplers == nil ||
	   gl.impl_SamplerParameteri == nil ||
	   gl.impl_BindSampler == nil ||
	   gl.impl_GetActiveUniform == nil ||
	   gl.impl_GetUniformLocation == nil ||
	   gl.impl_Uniform1i == nil {
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
	if platform_context.id == nil ||
	   platform_context.is_current == nil ||
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

	hint: u32 = gl.DYNAMIC_DRAW if .Uniform in desc.usage else gl.STATIC_DRAW
	gl.impl_BufferData(gl.COPY_WRITE_BUFFER, int(desc.size), nil, hint)
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
	// A previous pipeline may have disabled depth writes. Clears still initialize
	// the complete target; the next draw reapplies its pipeline's write state.
	gl.DepthMask(true)
	gl.ColorMask(true, true, true, true)
	gl.ClearColor(color[0], color[1], color[2], color[3])
	gl.ClearDepth(depth)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

create_shader :: proc(
	desc: types.Shader_Desc,
	allocator := context.allocator,
) -> (
	Shader,
	types.Error,
) {
	kind: u32
	switch desc.stage {
	case .Vertex:
		kind = gl.VERTEX_SHADER
	case .Fragment:
		kind = gl.FRAGMENT_SHADER
	case:
		return {}, .Unsupported_Shader_Stage
	}

	if err := check_errors("before shader creation"); err != .None {
		return {}, err
	}

	native := Shader {
		id = gl.impl_CreateShader(kind),
	}

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

create_pipeline :: proc(
	vertex, fragment: Shader,
	label: string,
	uniform_blocks: []types.Uniform_Block_Desc,
	textures: []types.Texture_Binding_Desc,
	allocator := context.allocator,
) -> (
	Pipeline,
	types.Error,
) {
	if err := check_errors("before pipeline creation"); err != .None {
		return {}, err
	}

	native := Pipeline {
		program = gl.impl_CreateProgram(),
	}

	succeeded := false
	defer if !succeeded {
		if native.vao != 0 {
			gl.impl_DeleteVertexArrays(1, &native.vao)
		}

		if native.program != 0 {
			gl.impl_DeleteProgram(native.program)
		}
	}

	if err := check_errors("create program"); err != .None {
		return {}, err
	}

	if native.program == 0 {
		return {}, .Backend_Failed
	}

	gl.impl_AttachShader(native.program, vertex.id)
	if err := check_errors("attach vertex shader"); err != .None {
		return {}, err
	}

	defer gl.impl_DetachShader(native.program, vertex.id)
	gl.impl_AttachShader(native.program, fragment.id)
	if err := check_errors("attach fragment shader"); err != .None {
		return {}, err
	}

	defer gl.impl_DetachShader(native.program, fragment.id)
	gl.impl_LinkProgram(native.program)
	if err := check_errors("link program"); err != .None {
		return {}, err
	}

	linked: i32
	gl.impl_GetProgramiv(native.program, gl.LINK_STATUS, &linked)
	if err := check_errors("query program link"); err != .None {
		return {}, err
	}

	if linked == 0 {
		log.errorf("Pipeline link failed: %s", label)
		log_length: i32
		gl.impl_GetProgramiv(native.program, gl.INFO_LOG_LENGTH, &log_length)
		if err := check_errors("query program log size"); err != .None {
			return {}, err
		}

		if log_length > 1 {
			bytes, allocation_error := make([]u8, int(log_length), allocator)
			if allocation_error != .None {
				return {}, .Allocation_Failed
			}

			defer delete(bytes, allocator)
			written: i32
			gl.impl_GetProgramInfoLog(native.program, log_length, &written, raw_data(bytes))
			if err := check_errors("read program log"); err != .None {
				return {}, err
			}

			log.error(string(bytes[:int(written)]))
		}

		return {}, .Pipeline_Link_Failed
	}

	if err := configure_uniform_blocks(&native, uniform_blocks, allocator); err != .None {
		return {}, err
	}

	if err := configure_textures(&native, textures, allocator); err != .None {
		return {}, err
	}

	previous_vao: i32
	gl.impl_GetIntegerv(gl.VERTEX_ARRAY_BINDING, &previous_vao)
	if err := check_errors("query vertex array binding"); err != .None {
		return {}, err
	}

	defer gl.impl_BindVertexArray(u32(previous_vao))
	gl.impl_GenVertexArrays(1, &native.vao)
	if err := check_errors("create vertex array"); err != .None {
		return {}, err
	}

	if native.vao == 0 {
		return {}, .Backend_Failed
	}

	gl.impl_BindVertexArray(native.vao)
	if err := check_errors("initialize vertex array"); err != .None {
		return {}, err
	}

	succeeded = true

	return native, .None
}

destroy_pipeline :: proc(native: ^Pipeline) -> types.Error {
	if err := check_errors("before pipeline deletion"); err != .None {
		return err
	}

	gl.impl_DeleteVertexArrays(1, &native.vao)
	if err := check_errors("delete vertex array"); err != .None {
		return err
	}

	native.vao = 0
	gl.impl_DeleteProgram(native.program)
	if err := check_errors("delete program"); err != .None {
		return err
	}

	native.program = 0

	return .None
}

draw_indexed :: proc(
	pipeline: Pipeline,
	settings: types.Pipeline_Settings,
	vertex: Buffer,
	vertex_offset: u64,
	index: Buffer,
	index_type: types.Index_Type,
	index_offset: u64,
	index_count: u32,
	uniforms: [types.MAX_UNIFORM_BINDINGS]Buffer,
	textures: [types.MAX_TEXTURE_BINDINGS]Texture,
) -> types.Error {
	if err := check_errors("before indexed draw"); err != .None {
		return err
	}

	previous_vao, previous_array, previous_program: i32
	gl.impl_GetIntegerv(gl.VERTEX_ARRAY_BINDING, &previous_vao)
	gl.impl_GetIntegerv(gl.ARRAY_BUFFER_BINDING, &previous_array)
	gl.impl_GetIntegerv(gl.CURRENT_PROGRAM, &previous_program)
	previous_uniform: i32
	previous_uniforms: [types.MAX_UNIFORM_BINDINGS]i32
	gl.impl_GetIntegerv(gl.UNIFORM_BUFFER_BINDING, &previous_uniform)

	for size, binding in pipeline.uniform_sizes {
		if size != 0 {
			gl.impl_GetIntegeri_v(
				gl.UNIFORM_BUFFER_BINDING,
				u32(binding),
				&previous_uniforms[binding],
			)
		}
	}

	if err := check_errors("query draw bindings"); err != .None {
		return err
	}

	previous_active: i32
	previous_textures, previous_samplers: [types.MAX_TEXTURE_BINDINGS]i32
	gl.impl_GetIntegerv(gl.ACTIVE_TEXTURE, &previous_active)
	if err := check_errors("query active texture"); err != .None {
		return err
	}

	defer gl.impl_ActiveTexture(u32(previous_active))

	for required, binding in pipeline.texture_bindings {
		if !required {
			continue
		}

		gl.impl_ActiveTexture(gl.TEXTURE0 + u32(binding))
		gl.impl_GetIntegerv(gl.TEXTURE_BINDING_2D, &previous_textures[binding])
		gl.impl_GetIntegerv(gl.SAMPLER_BINDING, &previous_samplers[binding])
	}

	if err := check_errors("query texture bindings"); err != .None {
		return err
	}

	defer {
		for required, binding in pipeline.texture_bindings {
			if !required {
				continue
			}

			gl.impl_ActiveTexture(gl.TEXTURE0 + u32(binding))
			gl.impl_BindTexture(gl.TEXTURE_2D, u32(previous_textures[binding]))
			gl.impl_BindSampler(u32(binding), u32(previous_samplers[binding]))
		}

		for size, binding in pipeline.uniform_sizes {
			if size != 0 {
				gl.impl_BindBufferBase(
					gl.UNIFORM_BUFFER,
					u32(binding),
					u32(previous_uniforms[binding]),
				)
			}
		}

		gl.impl_BindBuffer(gl.UNIFORM_BUFFER, u32(previous_uniform))
		gl.impl_BindVertexArray(u32(previous_vao))
		gl.impl_BindBuffer(gl.ARRAY_BUFFER, u32(previous_array))
		gl.impl_UseProgram(u32(previous_program))
	}

	gl.impl_UseProgram(pipeline.program)
	gl.impl_BindVertexArray(pipeline.vao)
	gl.impl_BindBuffer(gl.ARRAY_BUFFER, vertex.id)

	for i in 0 ..< settings.layout.attribute_count {
		attribute := settings.layout.attributes[i]
		gl.impl_EnableVertexAttribArray(attribute.location)
		gl.impl_VertexAttribPointer(
			attribute.location,
			i32(attribute.format) + 1,
			gl.FLOAT,
			false,
			i32(settings.layout.stride),
			uintptr(vertex_offset + u64(attribute.offset)),
		)
	}

	gl.impl_BindBuffer(gl.ELEMENT_ARRAY_BUFFER, index.id)
	if err := bind_uniforms(pipeline, uniforms); err != .None {
		return err
	}

	for required, binding in pipeline.texture_bindings {
		if !required {
			continue
		}

		gl.impl_ActiveTexture(gl.TEXTURE0 + u32(binding))
		gl.impl_BindTexture(gl.TEXTURE_2D, textures[binding].id)
		gl.impl_BindSampler(u32(binding), textures[binding].sampler)
	}

	if settings.depth.test_enabled {
		gl.impl_Enable(gl.DEPTH_TEST)
	} else {
		gl.impl_Disable(gl.DEPTH_TEST)
	}

	gl.impl_DepthMask(settings.depth.write_enabled)
	comparisons := [types.Compare]u32 {
		.Less          = gl.LESS,
		.Less_Equal    = gl.LEQUAL,
		.Equal         = gl.EQUAL,
		.Greater       = gl.GREATER,
		.Greater_Equal = gl.GEQUAL,
		.Not_Equal     = gl.NOTEQUAL,
		.Never         = gl.NEVER,
		.Always        = gl.ALWAYS,
	}

	gl.impl_DepthFunc(comparisons[settings.depth.compare])
	if settings.raster.cull == .None {
		gl.impl_Disable(gl.CULL_FACE)
	} else {
		gl.impl_Enable(gl.CULL_FACE)
		gl.impl_CullFace(gl.BACK if settings.raster.cull == .Back else gl.FRONT)
	}

	gl.impl_FrontFace(gl.CCW if settings.raster.winding == .CCW else gl.CW)
	gl.impl_PolygonMode(gl.FRONT_AND_BACK, gl.LINE if settings.raster.wireframe else gl.FILL)
	gl.impl_Disable(gl.BLEND)
	gl.impl_ColorMask(true, true, true, true)
	if err := check_errors("apply draw state"); err != .None {
		return err
	}

	primitives := [types.Primitive]u32 {
		.Triangles = gl.TRIANGLES,
		.Lines     = gl.LINES,
		.Points    = gl.POINTS,
	}

	gl.impl_DrawElements(
		primitives[settings.primitive],
		i32(index_count),
		gl.UNSIGNED_SHORT if index_type == .U16 else gl.UNSIGNED_INT,
		rawptr(uintptr(index_offset)),
	)

	return check_errors("draw indexed")
}

update_buffer :: proc(native: Buffer, offset: u64, data: []u8) -> types.Error {
	if err := check_errors("before buffer update"); err != .None {
		return err
	}

	previous: i32
	gl.impl_GetIntegerv(gl.COPY_WRITE_BUFFER_BINDING, &previous)
	if err := check_errors("query update binding"); err != .None {
		return err
	}

	defer gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, u32(previous))

	gl.impl_BindBuffer(gl.COPY_WRITE_BUFFER, native.id)
	if err := check_errors("bind update buffer"); err != .None {
		return err
	}

	// BufferSubData copies the bytes and synchronizes earlier uses implicitly.
	gl.impl_BufferSubData(gl.COPY_WRITE_BUFFER, int(offset), len(data), raw_data(data))

	return check_errors("update buffer")
}

configure_uniform_blocks :: proc(
	pipeline: ^Pipeline,
	blocks: []types.Uniform_Block_Desc,
	allocator := context.allocator,
) -> types.Error {
	active_count: i32
	gl.impl_GetProgramiv(pipeline.program, gl.ACTIVE_UNIFORM_BLOCKS, &active_count)
	if err := check_errors("query uniform blocks"); err != .None {
		return err
	}

	if int(active_count) != len(blocks) {
		log.errorf(
			"Pipeline declares %d uniform blocks, shader uses %d",
			len(blocks),
			active_count,
		)
		return .Invalid_Uniform_Binding
	}

	for block in blocks {
		name, allocation_error := strings.clone_to_cstring(block.name, allocator)
		if allocation_error != .None {
			return .Allocation_Failed
		}

		defer delete(name, allocator)

		index := gl.impl_GetUniformBlockIndex(pipeline.program, name)
		if err := check_errors("find uniform block"); err != .None {
			return err
		}

		if index == gl.INVALID_INDEX {
			log.errorf("Shader uniform block not found: %s", block.name)
			return .Invalid_Uniform_Binding
		}

		size: i32
		gl.impl_GetActiveUniformBlockiv(pipeline.program, index, gl.UNIFORM_BLOCK_DATA_SIZE, &size)
		gl.impl_UniformBlockBinding(pipeline.program, index, block.binding)
		if err := check_errors("configure uniform block"); err != .None {
			return err
		}

		if size <= 0 {
			return .Invalid_Uniform_Binding
		}

		pipeline.uniform_sizes[block.binding] = u64(size)
	}

	return .None
}

pipeline_uniform_sizes :: proc(pipeline: Pipeline) -> [types.MAX_UNIFORM_BINDINGS]u64 {
	return pipeline.uniform_sizes
}

bind_uniforms :: proc(
	pipeline: Pipeline,
	uniforms: [types.MAX_UNIFORM_BINDINGS]Buffer,
) -> types.Error {
	for size, binding in pipeline.uniform_sizes {
		if size != 0 {
			gl.impl_BindBufferBase(gl.UNIFORM_BUFFER, u32(binding), uniforms[binding].id)
		}
	}

	return check_errors("bind uniform buffers")
}

create_texture :: proc(desc: types.Texture_Desc, pixels: []u8) -> (Texture, types.Error) {
	if err := check_errors("before texture creation"); err != .None {
		return {}, err
	}

	previous, unpack_buffer, alignment, row_length, skip_rows, skip_pixels, maximum: i32
	gl.impl_GetIntegerv(gl.TEXTURE_BINDING_2D, &previous)
	gl.impl_GetIntegerv(gl.PIXEL_UNPACK_BUFFER_BINDING, &unpack_buffer)
	gl.impl_GetIntegerv(gl.UNPACK_ALIGNMENT, &alignment)
	gl.impl_GetIntegerv(gl.UNPACK_ROW_LENGTH, &row_length)
	gl.impl_GetIntegerv(gl.UNPACK_SKIP_ROWS, &skip_rows)
	gl.impl_GetIntegerv(gl.UNPACK_SKIP_PIXELS, &skip_pixels)
	gl.impl_GetIntegerv(gl.MAX_TEXTURE_SIZE, &maximum)
	if err := check_errors("query texture upload state"); err != .None {
		return {}, err
	}

	if desc.width > maximum || desc.height > maximum {
		return {}, .Invalid_Size
	}

	defer {
		gl.impl_BindTexture(gl.TEXTURE_2D, u32(previous))
		gl.impl_BindBuffer(gl.PIXEL_UNPACK_BUFFER, u32(unpack_buffer))
		gl.impl_PixelStorei(gl.UNPACK_ALIGNMENT, alignment)
		gl.impl_PixelStorei(gl.UNPACK_ROW_LENGTH, row_length)
		gl.impl_PixelStorei(gl.UNPACK_SKIP_ROWS, skip_rows)
		gl.impl_PixelStorei(gl.UNPACK_SKIP_PIXELS, skip_pixels)
	}

	native: Texture
	succeeded := false
	defer if !succeeded {
		if native.id != 0 {
			gl.impl_DeleteTextures(1, &native.id)
		}

		if native.sampler != 0 {
			gl.impl_DeleteSamplers(1, &native.sampler)
		}
	}

	gl.impl_GenTextures(1, &native.id)
	gl.impl_GenSamplers(1, &native.sampler)
	if err := check_errors("create texture and sampler"); err != .None {
		return {}, err
	}

	if native.id == 0 || native.sampler == 0 {
		return {}, .Backend_Failed
	}

	gl.impl_BindTexture(gl.TEXTURE_2D, native.id)
	gl.impl_BindBuffer(gl.PIXEL_UNPACK_BUFFER, 0)
	gl.impl_PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.impl_PixelStorei(gl.UNPACK_ROW_LENGTH, 0)
	gl.impl_PixelStorei(gl.UNPACK_SKIP_ROWS, 0)
	gl.impl_PixelStorei(gl.UNPACK_SKIP_PIXELS, 0)
	gl.impl_TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)
	gl.impl_TexImage2D(
		gl.TEXTURE_2D,
		0,
		i32(gl.SRGB8_ALPHA8 if desc.format == .RGBA8_SRGB else gl.RGBA8),
		desc.width,
		desc.height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		raw_data(pixels),
	)

	filter := i32(gl.LINEAR if desc.filter == .Linear else gl.NEAREST)
	gl.impl_SamplerParameteri(native.sampler, gl.TEXTURE_MIN_FILTER, filter)
	gl.impl_SamplerParameteri(native.sampler, gl.TEXTURE_MAG_FILTER, filter)
	gl.impl_SamplerParameteri(
		native.sampler,
		gl.TEXTURE_WRAP_S,
		i32(gl.REPEAT if desc.wrap_u == .Repeat else gl.CLAMP_TO_EDGE),
	)
	gl.impl_SamplerParameteri(
		native.sampler,
		gl.TEXTURE_WRAP_T,
		i32(gl.REPEAT if desc.wrap_v == .Repeat else gl.CLAMP_TO_EDGE),
	)
	if err := check_errors("upload and configure texture"); err != .None {
		log.errorf("Texture creation failed: %s (%d x %d)", desc.label, desc.width, desc.height)
		return {}, err
	}

	succeeded = true

	return native, .None
}

destroy_texture :: proc(native: ^Texture) -> types.Error {
	if err := check_errors("before texture deletion"); err != .None {
		return err
	}

	if native.id != 0 {
		gl.impl_DeleteTextures(1, &native.id)
		if err := check_errors("delete texture"); err != .None {
			return err
		}

		native.id = 0
	}

	if native.sampler != 0 {
		gl.impl_DeleteSamplers(1, &native.sampler)
		if err := check_errors("delete texture sampler"); err != .None {
			return err
		}

		native.sampler = 0
	}

	return .None
}

configure_textures :: proc(
	pipeline: ^Pipeline,
	bindings: []types.Texture_Binding_Desc,
	allocator := context.allocator,
) -> types.Error {
	previous, active, max_name: i32
	gl.impl_GetIntegerv(gl.CURRENT_PROGRAM, &previous)
	gl.impl_GetProgramiv(pipeline.program, gl.ACTIVE_UNIFORMS, &active)
	gl.impl_GetProgramiv(pipeline.program, gl.ACTIVE_UNIFORM_MAX_LENGTH, &max_name)
	if err := check_errors("query texture uniforms"); err != .None {
		return err
	}

	name, allocation_error := make([]u8, max(1, int(max_name)), allocator)
	if allocation_error != .None {
		return .Allocation_Failed
	}

	defer delete(name, allocator)
	gl.impl_UseProgram(pipeline.program)
	defer gl.impl_UseProgram(u32(previous))
	count := 0

	for index in 0 ..< active {
		length, size: i32
		kind: u32
		gl.impl_GetActiveUniform(
			pipeline.program,
			u32(index),
			i32(len(name)),
			&length,
			&size,
			&kind,
			raw_data(name),
		)
		if err := check_errors("read texture uniform"); err != .None {
			return err
		}

		if !is_sampler_uniform(kind) {
			continue
		}

		uniform_name := string(name[:length])
		if kind != gl.SAMPLER_2D || size != 1 || strings.contains(uniform_name, "[") {
			log.errorf("Only scalar sampler2D is supported: %s", uniform_name)
			return .Invalid_Texture_Binding
		}

		found := false

		for binding in bindings {
			if binding.name != uniform_name {
				continue
			}

			location := gl.impl_GetUniformLocation(pipeline.program, cstring(raw_data(name)))
			if location < 0 {
				return .Invalid_Texture_Binding
			}

			gl.impl_Uniform1i(location, i32(binding.binding))
			pipeline.texture_bindings[binding.binding] = true
			found = true
			break
		}

		if !found {
			log.errorf("Shader texture is not declared: %s", uniform_name)
			return .Invalid_Texture_Binding
		}

		count += 1
	}

	if count != len(bindings) {
		return .Invalid_Texture_Binding
	}

	return check_errors("configure texture bindings")
}

// Recognize unsupported sampler types too, so they cannot bypass declaration checks.
is_sampler_uniform :: proc(kind: u32) -> bool {
	switch kind {
	case gl.SAMPLER_1D,
	     gl.SAMPLER_2D,
	     gl.SAMPLER_3D,
	     gl.SAMPLER_CUBE,
	     gl.SAMPLER_1D_SHADOW,
	     gl.SAMPLER_2D_SHADOW,
	     gl.SAMPLER_CUBE_SHADOW,
	     gl.SAMPLER_1D_ARRAY,
	     gl.SAMPLER_2D_ARRAY,
	     gl.SAMPLER_1D_ARRAY_SHADOW,
	     gl.SAMPLER_2D_ARRAY_SHADOW,
	     gl.SAMPLER_2D_RECT,
	     gl.SAMPLER_2D_RECT_SHADOW,
	     gl.SAMPLER_BUFFER,
	     gl.SAMPLER_2D_MULTISAMPLE,
	     gl.SAMPLER_2D_MULTISAMPLE_ARRAY,
	     gl.SAMPLER_CUBE_MAP_ARRAY,
	     gl.SAMPLER_CUBE_MAP_ARRAY_SHADOW,
	     gl.INT_SAMPLER_1D,
	     gl.INT_SAMPLER_2D,
	     gl.INT_SAMPLER_3D,
	     gl.INT_SAMPLER_CUBE,
	     gl.INT_SAMPLER_1D_ARRAY,
	     gl.INT_SAMPLER_2D_ARRAY,
	     gl.INT_SAMPLER_2D_RECT,
	     gl.INT_SAMPLER_BUFFER,
	     gl.INT_SAMPLER_2D_MULTISAMPLE,
	     gl.INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
	     gl.INT_SAMPLER_CUBE_MAP_ARRAY,
	     gl.UNSIGNED_INT_SAMPLER_1D,
	     gl.UNSIGNED_INT_SAMPLER_2D,
	     gl.UNSIGNED_INT_SAMPLER_3D,
	     gl.UNSIGNED_INT_SAMPLER_CUBE,
	     gl.UNSIGNED_INT_SAMPLER_1D_ARRAY,
	     gl.UNSIGNED_INT_SAMPLER_2D_ARRAY,
	     gl.UNSIGNED_INT_SAMPLER_2D_RECT,
	     gl.UNSIGNED_INT_SAMPLER_BUFFER,
	     gl.UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE,
	     gl.UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
	     gl.UNSIGNED_INT_SAMPLER_CUBE_MAP_ARRAY:
		return true
	}

	return false
}
