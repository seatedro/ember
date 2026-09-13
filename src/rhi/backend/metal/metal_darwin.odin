package metal

import platform_metal "../../../platform/metal_context"
import types "../../types"
import "core:log"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

Device_Context :: platform_metal.Context
SHADER_LANGUAGE :: types.Shader_Language.MSL

Device :: struct {
	surface:          Device_Context,
	gpu:              ^MTL.Device,
	queue:            ^MTL.CommandQueue,
	layer:            ^CA.MetalLayer,
	depth:            ^MTL.Texture,
	size:             [2]i32,
	frame_pool:       ^NS.AutoreleasePool,
	drawable:         ^CA.MetalDrawable,
	command:          ^MTL.CommandBuffer,
	encoder:          ^MTL.RenderCommandEncoder,
	pass_size:        [2]i32,
	pass_format:      int,
	submitted:        [3]^MTL.CommandBuffer,
	submission_index: int,
}

Buffer :: struct {
	object: ^MTL.Buffer,
}

Shader :: struct {
	function: ^MTL.Function,
}

Pipeline :: struct {
	states:                             [4]^MTL.RenderPipelineState,
	requirements:                       types.Pipeline_Requirements,
	vertex_bindings, fragment_bindings: Stage_Bindings,
	depth:                              ^MTL.DepthStencilState,
	settings:                           types.Pipeline_Settings,
}

// Indices are stored plus one so zero denotes an unused RHI binding.
Stage_Bindings :: struct {
	uniforms:           [types.MAX_UNIFORM_BINDINGS]u8,
	textures, samplers: [types.MAX_TEXTURE_BINDINGS]u8,
}

Texture :: struct {
	object:  ^MTL.Texture,
	sampler: ^MTL.SamplerState,
	format:  types.Texture_Format,
}

Render_Target :: struct {
	color: Texture,
	depth: ^MTL.Texture,
	size:  [2]i32,
}

create_device :: proc(surface: Device_Context) -> (Device, types.Error) {
	if surface.view == nil {
		return {}, .Wrong_Context
	}

	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	device := Device {
		surface = surface,
	}
	device.gpu = MTL.CreateSystemDefaultDevice()
	if device.gpu == nil {
		return {}, .Unsupported_Backend
	}

	device.queue = device.gpu->newCommandQueue()
	if device.queue == nil {
		device.gpu->release()
		return {}, .Allocation_Failed
	}

	device.layer = CA.MetalLayer.layer()
	device.layer->retain()
	device.layer->setDevice(device.gpu)
	device.layer->setPixelFormat(.BGRA8Unorm)
	device.layer->setFramebufferOnly(true)
	device.layer->setDisplaySyncEnabled(surface.vsync)
	surface.view->setWantsLayer(true)
	surface.view->setLayer(cast(^NS.Layer)device.layer)
	return device, .None
}

validate_context :: proc(device: ^Device) -> types.Error {
	if device.gpu == nil || device.surface.view == nil {
		return .Device_Not_Initialized
	}

	return .None
}

destroy_device :: proc(device: ^Device) -> types.Error {
	if device.frame_pool != nil {
		end_frame(device, false)
	}

	wait_idle(device)

	if device.depth != nil {
		device.depth->release()
	}

	device.surface.view->setLayer(nil)
	device.layer->release()
	device.queue->release()
	device.gpu->release()
	device^ = {}
	return .None
}

begin_frame :: proc(device: ^Device, size: [2]i32) -> types.Error {
	if err := finish_submission(&device.submitted[device.submission_index]); err != .None {
		return err
	}

	pool := NS.AutoreleasePool.alloc()->init()
	success := false
	defer {
		if !success {
			pool->drain()
		}
	}

	bounds := device.surface.view->bounds()
	device.layer->setFrame(bounds)
	device.layer->setDrawableSize({NS.Float(size.x), NS.Float(size.y)})
	if bounds.size.width > 0 {
		device.layer->setContentsScale(NS.Float(size.x) / bounds.size.width)
	}

	if device.depth == nil || device.size != size {
		desc := MTL.TextureDescriptor.alloc()->init()
		defer desc->release()
		desc->setTextureType(.Type2D)
		desc->setPixelFormat(.Depth32Float)
		desc->setWidth(NS.UInteger(size.x))
		desc->setHeight(NS.UInteger(size.y))
		desc->setStorageMode(.Private)
		desc->setUsage({.RenderTarget})
		depth := device.gpu->newTextureWithDescriptor(desc)
		if depth == nil {
			return .Allocation_Failed
		}

		if device.depth != nil {
			device.depth->release()
		}
		device.depth = depth
		device.size = size
	}

	drawable := device.layer->nextDrawable()
	if drawable == nil {
		return .Surface_Unavailable
	}

	command := device.queue->commandBuffer()
	if command == nil {
		return .Allocation_Failed
	}

	device.drawable = drawable
	device.command = command
	device.frame_pool = pool
	success = true
	return .None
}

// Keep up to three frames in flight. Metal retains encoded resources, including
// allocations replaced by later buffer updates or render-target resizes.
end_frame :: proc(device: ^Device, present: bool) -> types.Error {
	if device.encoder != nil {
		end_pass(device)
	}
	if present {
		device.command->presentDrawable(cast(^MTL.Drawable)device.drawable)
	}
	device.command->retain()
	device.command->commit()
	device.submitted[device.submission_index] = device.command
	device.submission_index = (device.submission_index + 1) % len(device.submitted)
	device.command = nil
	device.drawable = nil
	device.frame_pool->drain()
	device.frame_pool = nil
	return .None
}

@(private)
finish_submission :: proc(command: ^^MTL.CommandBuffer) -> types.Error {
	if command^ == nil {
		return .None
	}
	command^->waitUntilCompleted()
	failed := command^->status() == .Error
	if failed {
		report_error("execute frame", command^->error())
	}
	command^->release()
	command^ = nil
	return .Backend_Failed if failed else .None
}

wait_idle :: proc(device: ^Device) -> types.Error {
	result: types.Error
	for &command in device.submitted {
		if err := finish_submission(&command); err != .None {
			result = err
		}
	}
	// An open, unsubmitted command buffer also retains its encoded resources.
	return result
}

create_buffer :: proc(
	device: ^Device,
	desc: types.Buffer_Desc,
	data: []u8,
) -> (
	Buffer,
	types.Error,
) {
	if desc.size > u64(device.gpu->maxBufferLength()) {
		return {}, .Invalid_Size
	}

	object := device.gpu->newBufferWithLength(
		NS.UInteger(desc.size),
		MTL.ResourceStorageModeShared,
	)
	if object == nil {
		return {}, .Allocation_Failed
	}

	copy(object->contents(), data)
	return {object}, .None
}

update_buffer :: proc(device: ^Device, native: ^Buffer, offset: u64, data: []u8) -> types.Error {
	// Replacing the allocation preserves data referenced by earlier draws in an
	// open frame. Their command buffer retains the previous allocation.
	old := native.object
	replacement := device.gpu->newBufferWithLength(old->length(), MTL.ResourceStorageModeShared)
	if replacement == nil {
		return .Allocation_Failed
	}

	copy(replacement->contents(), old->contents())
	copy(replacement->contents()[int(offset):], data)
	native.object = replacement
	old->release()
	return .None
}

destroy_buffer :: proc(device: ^Device, native: ^Buffer) -> types.Error {
	native.object->release()
	native^ = {}
	return .None
}

create_shader :: proc(
	device: ^Device,
	desc: types.Shader_Desc,
	allocator := context.allocator,
) -> (
	Shader,
	types.Error,
) {
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	source := NS.String.alloc()->initWithOdinString(desc.source.code)
	defer source->release()
	library, error := device.gpu->newLibraryWithSource(source, nil)
	if library == nil {
		report_error(desc.label, error)
		return {}, .Shader_Compile_Failed
	}
	defer library->release()

	name := NS.String.alloc()->initWithOdinString(desc.source.entry_point)
	defer name->release()
	function := library->newFunctionWithName(name)
	if function == nil {
		log.errorf("Metal: %s: missing entry point %s", desc.label, desc.source.entry_point)
		return {}, .Invalid_Shader_Entry_Point
	}

	expected := MTL.FunctionType.Vertex if desc.stage == .Vertex else MTL.FunctionType.Fragment
	if function->functionType() != expected {
		function->release()
		return {}, .Unsupported_Shader_Stage
	}

	return {function}, .None
}

destroy_shader :: proc(device: ^Device, native: ^Shader) -> types.Error {
	native.function->release()
	native^ = {}
	return .None
}

create_pipeline :: proc(
	device: ^Device,
	vertex, fragment: Shader,
	settings: types.Pipeline_Settings,
	label: string,
	uniform_blocks: []types.Uniform_Block_Desc,
	textures: []types.Texture_Binding_Desc,
	allocator := context.allocator,
) -> (
	Pipeline,
	types.Error,
) {
	// Metal vertex strides are limited to 2048 bytes.
	if settings.layout.stride > 2048 || settings.instance_layout.stride > 2048 {
		return {}, .Invalid_Vertex_Layout
	}

	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	desc := MTL.RenderPipelineDescriptor.alloc()->init()
	defer desc->release()
	desc->setVertexFunction(vertex.function)
	desc->setFragmentFunction(fragment.function)
	desc->setDepthAttachmentPixelFormat(.Depth32Float)
	layout := MTL.VertexDescriptor.alloc()->init()
	defer layout->release()
	set_layout(layout, settings.layout, 0, .PerVertex)
	set_layout(layout, settings.instance_layout, 1, .PerInstance)
	desc->setVertexDescriptor(layout)

	color := desc->colorAttachments()->object(0)
	color->setPixelFormat(.BGRA8Unorm)
	color->setBlendingEnabled(settings.blend.enabled)
	color->setSourceRGBBlendFactor(BLEND_FACTORS[settings.blend.src_factor_rgb])
	color->setDestinationRGBBlendFactor(BLEND_FACTORS[settings.blend.dst_factor_rgb])
	color->setRgbBlendOperation(BLEND_OPS[settings.blend.op_rgb])
	color->setSourceAlphaBlendFactor(BLEND_FACTORS[settings.blend.src_factor_alpha])
	color->setDestinationAlphaBlendFactor(BLEND_FACTORS[settings.blend.dst_factor_alpha])
	color->setAlphaBlendOperation(BLEND_OPS[settings.blend.op_alpha])

	native := Pipeline {
		settings = settings,
	}
	success := false
	defer {
		if !success {
			destroy_pipeline(device, &native)
		}
	}

	// The RHI pipeline can be used on the window or any supported target format.
	// Build each state now so later draws cannot trigger shader compilation.
	for format, i in COLOR_FORMATS {
		color->setPixelFormat(format)
		reflection: MTL.AutoreleasedRenderPipelineReflection
		state, error := device.gpu->newRenderPipelineStateWithDescriptorWithReflection(
			desc,
			{.ArgumentInfo, .BufferTypeInfo},
			&reflection,
		)
		if state == nil {
			report_error(label, error)
			return {}, .Pipeline_Link_Failed
		}
		native.states[i] = state
		if i != 0 {
			continue
		}

		if reflection == nil ||
		   !NS.respondsToSelector(
				   cast(^NS.Object)reflection,
				   NS.sel_registerName("vertexBindings"),
			   ) {
			return {}, .Unsupported_Backend
		}

		if err := reflect_bindings(
			reflection->vertexBindings(),
			&native.vertex_bindings,
			&native.requirements,
			uniform_blocks,
			textures,
			true,
		); err != .None {
			return {}, err
		}
		if err := reflect_bindings(
			reflection->fragmentBindings(),
			&native.fragment_bindings,
			&native.requirements,
			uniform_blocks,
			textures,
			false,
		); err != .None {
			return {}, err
		}
		for block in uniform_blocks {
			if native.requirements.uniform_sizes[block.binding] == 0 {
				return {}, .Invalid_Uniform_Binding
			}
		}
		for texture in textures {
			if !native.requirements.texture_bindings[texture.binding] {
				return {}, .Invalid_Texture_Binding
			}
		}
	}

	depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
	defer depth_desc->release()
	depth_desc->setDepthCompareFunction(
		COMPARES[settings.depth.compare] if settings.depth.test_enabled else .Always,
	)
	depth_desc->setDepthWriteEnabled(settings.depth.test_enabled && settings.depth.write_enabled)
	depth := device.gpu->newDepthStencilState(depth_desc)
	if depth == nil {
		return {}, .Allocation_Failed
	}

	native.depth = depth
	success = true
	return native, .None
}

@(private)
set_layout :: proc(
	desc: ^MTL.VertexDescriptor,
	layout: types.Vertex_Layout,
	index: NS.UInteger,
	step: MTL.VertexStepFunction,
) {
	if layout.attribute_count == 0 {
		return
	}

	buffer := desc->layouts()->object(index)
	buffer->setStride(NS.UInteger(layout.stride))
	buffer->setStepFunction(step)
	buffer->setStepRate(1)
	for i in 0 ..< layout.attribute_count {
		attribute := layout.attributes[i]
		native := desc->attributes()->object(NS.UInteger(attribute.location))
		native->setFormat(VERTEX_FORMATS[attribute.format])
		native->setOffset(NS.UInteger(attribute.offset))
		native->setBufferIndex(index)
	}
}

@(private)
reflect_bindings :: proc(
	arguments: ^NS.Array,
	stage: ^Stage_Bindings,
	requirements: ^types.Pipeline_Requirements,
	blocks: []types.Uniform_Block_Desc,
	textures: []types.Texture_Binding_Desc,
	vertex: bool,
) -> types.Error {
	for i in 0 ..< arguments->count() {
		argument := cast(^MTL.Binding)arguments->object(i)
		if !argument->isUsed() {
			continue
		}

		index := argument->index()
		if !argument->isArgument() {
			if !vertex || argument->type() != .Buffer || index > 1 {
				return .Invalid_Buffer_Binding
			}
			continue
		}

		name := argument->name()->odinString()
		found := false
		#partial switch argument->type() {
		case .Buffer:
			if index >= 31 || (vertex && index < 2) || argument->access() != .ReadOnly {
				return .Invalid_Uniform_Binding
			}

			buffer := cast(^MTL.BufferBinding)argument
			size := u64(buffer->bufferDataSize())
			if size == 0 || buffer->bufferDataType() != .Struct {
				return .Invalid_Uniform_Binding
			}

			for block in blocks {
				if block.name == name {
					stage.uniforms[block.binding] = u8(index + 1)
					requirements.uniform_sizes[block.binding] = max(
						requirements.uniform_sizes[block.binding],
						size,
					)
					found = true
					break
				}
			}

			if !found {
				log.errorf("Metal: undeclared uniform block %s", name)
				return .Invalid_Uniform_Binding
			}
		case .Texture:
			texture := cast(^MTL.TextureBinding)argument
			if index >= 128 ||
			   texture->textureType() != .Type2D ||
			   texture->arrayLength() > 1 ||
			   texture->isDepthTexture() ||
			   texture->textureDataType() != .Float ||
			   argument->access() != .ReadOnly {
				return .Invalid_Texture_Binding
			}

			for binding in textures {
				if binding.name == name {
					stage.textures[binding.binding] = u8(index + 1)
					requirements.texture_bindings[binding.binding] = true
					found = true
					break
				}
			}

			if !found {
				return .Invalid_Texture_Binding
			}
		case .Sampler:
			if index >= 16 {
				return .Invalid_Texture_Binding
			}

			// MSL samplers use the texture argument name followed by _sampler.
			for binding in textures {
				if strings.has_suffix(name, "_sampler") && name[:len(name) - 8] == binding.name {
					stage.samplers[binding.binding] = u8(index + 1)
					found = true
					break
				}
			}

			if !found {
				return .Invalid_Texture_Binding
			}
		case:
			return .Unsupported_Usage
		}
	}
	return .None
}

destroy_pipeline :: proc(device: ^Device, native: ^Pipeline) -> types.Error {
	for state in native.states {
		if state != nil {
			state->release()
		}
	}
	if native.depth != nil {
		native.depth->release()
	}
	native^ = {}
	return .None
}

pipeline_requirements :: proc(pipeline: Pipeline) -> types.Pipeline_Requirements {
	return pipeline.requirements
}

begin_pass :: proc(
	device: ^Device,
	target: Render_Target,
	viewport: types.Viewport,
	color_load, depth_load: types.Load_Op,
	color: [4]f32,
	depth: f64,
) -> types.Error {
	desc := MTL.RenderPassDescriptor.renderPassDescriptor()
	attachment := desc->colorAttachments()->object(0)
	color_texture := device.drawable->texture()
	depth_texture := device.depth
	device.pass_size = device.size
	device.pass_format = 0
	if target.color.object != nil {
		color_texture = target.color.object
		depth_texture = target.depth
		device.pass_size = target.size
		device.pass_format = int(target.color.format) + 1
	}
	attachment->setTexture(color_texture)
	attachment->setLoadAction(.Clear if color_load == .Clear else .Load)
	attachment->setStoreAction(.Store)
	attachment->setClearColor({f64(color.r), f64(color.g), f64(color.b), f64(color.a)})
	depth_attachment := desc->depthAttachment()
	depth_attachment->setTexture(depth_texture)
	depth_attachment->setLoadAction(.Clear if depth_load == .Clear else .Load)
	depth_attachment->setStoreAction(.Store)
	depth_attachment->setClearDepth(depth)
	device.encoder = device.command->renderCommandEncoderWithDescriptor(desc)
	if device.encoder == nil {
		return .Backend_Failed
	}

	device.encoder->setViewport(
		{
			f64(viewport.x),
			f64(device.pass_size.y - viewport.y - viewport.height),
			f64(viewport.width),
			f64(viewport.height),
			0,
			1,
		},
	)
	return .None
}

end_pass :: proc(device: ^Device) -> types.Error {
	device.encoder->endEncoding()
	device.encoder = nil
	return .None
}

draw_indexed :: proc(
	device: ^Device,
	pipeline: Pipeline,
	vertex: Buffer,
	vertex_offset: u64,
	instance: Buffer,
	instance_offset: u64,
	index: Buffer,
	index_type: types.Index_Type,
	index_offset: u64,
	index_count, instance_count: u32,
	scissor: types.Scissor,
	uniforms: [types.MAX_UNIFORM_BINDINGS]Buffer,
	textures: [types.MAX_TEXTURE_BINDINGS]Texture,
) -> types.Error {
	x, y: i64
	width, height := i64(device.pass_size.x), i64(device.pass_size.y)
	if scissor.enabled {
		x = max(i64(scissor.x), 0)
		y = max(i64(scissor.y), 0)
		width = min(i64(scissor.x) + i64(scissor.width), width) - x
		height = min(i64(scissor.y) + i64(scissor.height), height) - y
		if width <= 0 || height <= 0 {
			return .None
		}
	}

	encoder := device.encoder
	encoder->setScissorRect(
		{
			NS.Integer(x),
			NS.Integer(i64(device.pass_size.y) - y - height),
			NS.Integer(width),
			NS.Integer(height),
		},
	)
	encoder->setRenderPipelineState(pipeline.states[device.pass_format])
	encoder->setDepthStencilState(pipeline.depth)
	encoder->setCullMode(CULL_MODES[pipeline.settings.raster.cull])
	encoder->setFrontFacingWinding(
		.CounterClockwise if pipeline.settings.raster.winding == .CCW else .Clockwise,
	)
	encoder->setTriangleFillMode(.Lines if pipeline.settings.raster.wireframe else .Fill)
	encoder->setVertexBuffer(vertex.object, NS.UInteger(vertex_offset), 0)
	if pipeline.settings.instance_layout.attribute_count != 0 {
		encoder->setVertexBuffer(instance.object, NS.UInteger(instance_offset), 1)
	}
	bind_resources(encoder, pipeline.vertex_bindings, uniforms, textures, true)
	bind_resources(encoder, pipeline.fragment_bindings, uniforms, textures, false)
	encoder->drawIndexedPrimitivesWithInstanceCount(
		PRIMITIVES[pipeline.settings.primitive],
		NS.UInteger(index_count),
		.UInt16 if index_type == .U16 else .UInt32,
		index.object,
		NS.UInteger(index_offset),
		NS.UInteger(instance_count),
	)
	return .None
}

@(private)
bind_resources :: proc(
	encoder: ^MTL.RenderCommandEncoder,
	bindings: Stage_Bindings,
	uniforms: [types.MAX_UNIFORM_BINDINGS]Buffer,
	textures: [types.MAX_TEXTURE_BINDINGS]Texture,
	vertex: bool,
) {
	for index, binding in bindings.uniforms {
		if index == 0 {
			continue
		}
		if vertex {
			encoder->setVertexBuffer(uniforms[binding].object, 0, NS.UInteger(index - 1))
		} else {
			encoder->setFragmentBuffer(uniforms[binding].object, 0, NS.UInteger(index - 1))
		}
	}
	for texture, binding in textures {
		index := bindings.textures[binding]
		if index != 0 {
			if vertex {
				encoder->setVertexTexture(texture.object, NS.UInteger(index - 1))
			} else {
				encoder->setFragmentTexture(texture.object, NS.UInteger(index - 1))
			}
		}
		sampler := bindings.samplers[binding]
		if sampler != 0 {
			if vertex {
				encoder->setVertexSamplerState(texture.sampler, NS.UInteger(sampler - 1))
			} else {
				encoder->setFragmentSamplerState(texture.sampler, NS.UInteger(sampler - 1))
			}
		}
	}
}

create_texture :: proc(
	device: ^Device,
	desc: types.Texture_Desc,
	pixels: []u8,
) -> (
	Texture,
	types.Error,
) {
	if desc.width > 16384 || desc.height > 16384 {
		return {}, .Invalid_Size
	}

	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	descriptor := MTL.TextureDescriptor.alloc()->init()
	defer descriptor->release()
	descriptor->setTextureType(.Type2D)
	descriptor->setWidth(NS.UInteger(desc.width))
	descriptor->setHeight(NS.UInteger(desc.height))
	descriptor->setPixelFormat(COLOR_FORMATS[int(desc.format) + 1])
	descriptor->setUsage({.ShaderRead, .RenderTarget} if len(pixels) == 0 else {.ShaderRead})
	descriptor->setStorageMode(
		.Private if len(pixels) == 0 else (.Shared if device.gpu->hasUnifiedMemory() else .Managed),
	)
	object := device.gpu->newTextureWithDescriptor(descriptor)
	if object == nil {
		return {}, .Allocation_Failed
	}
	success := false
	defer {
		if !success {
			object->release()
		}
	}
	if len(pixels) != 0 {
		// Keep uploaded images and render targets in the same orientation. MSL
		// samples with (u, 1-v) to preserve the RHI's bottom-left texture origin.
		flipped, error := make([]u8, len(pixels))
		if error != .None {
			return {}, .Allocation_Failed
		}
		defer delete(flipped)
		stride := int(desc.width) * (8 if desc.format == .RGBA16F else 4)
		for y in 0 ..< int(desc.height) {
			copy(
				flipped[y * stride:(y + 1) * stride],
				pixels[(int(desc.height) - 1 - y) * stride:(int(desc.height) - y) * stride],
			)
		}
		object->replaceRegion(
			{size = {NS.Integer(desc.width), NS.Integer(desc.height), 1}},
			0,
			raw_data(flipped),
			NS.UInteger(stride),
		)
	}
	sampler_desc := MTL.SamplerDescriptor.alloc()->init()
	defer sampler_desc->release()
	sampler_desc->setMinFilter(.Linear if desc.filter == .Linear else .Nearest)
	sampler_desc->setMagFilter(.Linear if desc.filter == .Linear else .Nearest)
	sampler_desc->setSAddressMode(.Repeat if desc.wrap_u == .Repeat else .ClampToEdge)
	sampler_desc->setTAddressMode(.Repeat if desc.wrap_v == .Repeat else .ClampToEdge)
	sampler_desc->setNormalizedCoordinates(true)
	sampler_desc->setLodMaxClamp(0)
	sampler := device.gpu->newSamplerState(sampler_desc)
	if sampler == nil {
		return {}, .Allocation_Failed
	}
	success = true
	return {object = object, sampler = sampler, format = desc.format}, .None
}

destroy_texture :: proc(device: ^Device, native: ^Texture) -> types.Error {
	if native.object != nil {
		native.object->release()
	}

	if native.sampler != nil {
		native.sampler->release()
	}
	native^ = {}
	return .None
}

create_render_target :: proc(
	device: ^Device,
	desc: types.Render_Target_Desc,
	color: Texture,
) -> (
	Render_Target,
	types.Error,
) {
	descriptor := MTL.TextureDescriptor.alloc()->init()
	defer descriptor->release()
	descriptor->setTextureType(.Type2D)
	descriptor->setWidth(NS.UInteger(desc.width))
	descriptor->setHeight(NS.UInteger(desc.height))
	descriptor->setPixelFormat(.Depth32Float)
	descriptor->setUsage({.RenderTarget})
	descriptor->setStorageMode(.Private)
	depth := device.gpu->newTextureWithDescriptor(descriptor)
	if depth == nil {
		return {}, .Allocation_Failed
	}
	return {color = color, depth = depth, size = {desc.width, desc.height}}, .None
}

destroy_render_target :: proc(device: ^Device, native: ^Render_Target) -> types.Error {
	if native.depth != nil {
		native.depth->release()
	}

	// The RHI owns and releases the color texture separately.
	native^ = {}
	return .None
}

@(private)
COLOR_FORMATS := [4]MTL.PixelFormat{.BGRA8Unorm, .RGBA8Unorm, .RGBA8Unorm_sRGB, .RGBA16Float}

@(private)
report_error :: proc(operation: string, error: ^NS.Error) {
	if error != nil {
		log.errorf("Metal: %s: %s", operation, error->localizedDescription()->odinString())
	} else {
		log.errorf("Metal: %s failed", operation)
	}
}

@(private)
VERTEX_FORMATS := [types.Vertex_Format]MTL.VertexFormat {
	.F32   = .Float,
	.F32x2 = .Float2,
	.F32x3 = .Float3,
	.F32x4 = .Float4,
}

@(private)
COMPARES := [types.Compare]MTL.CompareFunction {
	.Less          = .Less,
	.Less_Equal    = .LessEqual,
	.Equal         = .Equal,
	.Greater       = .Greater,
	.Greater_Equal = .GreaterEqual,
	.Not_Equal     = .NotEqual,
	.Never         = .Never,
	.Always        = .Always,
}

@(private)
CULL_MODES := [types.Cull_Mode]MTL.CullMode {
	.None  = .None,
	.Back  = .Back,
	.Front = .Front,
}

@(private)
PRIMITIVES := [types.Primitive]MTL.PrimitiveType {
	.Triangles = .Triangle,
	.Lines     = .Line,
	.Points    = .Point,
}

@(private)
BLEND_FACTORS := [types.Blend_Factor]MTL.BlendFactor {
	.Zero                = .Zero,
	.One                 = .One,
	.Src_Color           = .SourceColor,
	.One_Minus_Src_Color = .OneMinusSourceColor,
	.Dst_Color           = .DestinationColor,
	.One_Minus_Dst_Color = .OneMinusDestinationColor,
	.Src_Alpha           = .SourceAlpha,
	.One_Minus_Src_Alpha = .OneMinusSourceAlpha,
	.Dst_Alpha           = .DestinationAlpha,
	.One_Minus_Dst_Alpha = .OneMinusDestinationAlpha,
}

@(private)
BLEND_OPS := [types.Blend_Op]MTL.BlendOperation {
	.Add              = .Add,
	.Subtract         = .Subtract,
	.Reverse_Subtract = .ReverseSubtract,
	.Min              = .Min,
	.Max              = .Max,
}
