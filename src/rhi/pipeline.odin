package rhi

import "../core/pool"
import "backend"
import "core:strings"
import "types"

Pipeline_Handle :: struct {
	index:      u32,
	generation: u32,
}

MAX_VERTEX_ATTRIBUTES :: types.MAX_VERTEX_ATTRIBUTES
Vertex_Format :: types.Vertex_Format
Vertex_Attribute :: types.Vertex_Attribute
Vertex_Layout :: types.Vertex_Layout
Compare :: types.Compare
Cull_Mode :: types.Cull_Mode
Winding :: types.Winding
Primitive :: types.Primitive
Depth_State :: types.Depth_State
Raster_State :: types.Raster_State
Blend_Factor :: types.Blend_Factor
Blend_Op :: types.Blend_Op
Blend_State :: types.Blend_State
Pipeline_Settings :: types.Pipeline_Settings
Pipeline_Desc :: types.Pipeline_Desc
Uniform_Block_Desc :: types.Uniform_Block_Desc
MAX_UNIFORM_BINDINGS :: types.MAX_UNIFORM_BINDINGS
MAX_TEXTURE_BINDINGS :: types.MAX_TEXTURE_BINDINGS
Texture_Binding_Desc :: types.Texture_Binding_Desc

Pipeline_Resource :: struct {
	settings:         Pipeline_Settings,
	uniform_sizes:    [MAX_UNIFORM_BINDINGS]u64,
	texture_bindings: [MAX_TEXTURE_BINDINGS]bool,
	native:           backend.Pipeline,
}

validate_vertex_layout :: proc(layout: Vertex_Layout) -> Error {
	if layout.attribute_count == 0 ||
	   layout.attribute_count > MAX_VERTEX_ATTRIBUTES ||
	   layout.stride == 0 ||
	   layout.stride > u32(max(i32)) ||
	   layout.stride % 4 != 0 {
		return .Invalid_Vertex_Layout
	}

	locations: u32

	for i in 0 ..< layout.attribute_count {
		attribute := layout.attributes[i]
		if attribute.location >= MAX_VERTEX_ATTRIBUTES ||
		   attribute.format < .F32 ||
		   attribute.format > .F32x4 ||
		   attribute.offset % 4 != 0 {
			return .Invalid_Vertex_Layout
		}

		width := (u32(attribute.format) + 1) * 4
		if attribute.offset > layout.stride || width > layout.stride - attribute.offset {
			return .Invalid_Vertex_Layout
		}

		bit := u32(1) << attribute.location
		if locations & bit != 0 {
			return .Invalid_Vertex_Layout
		}

		locations |= bit
	}

	return .None
}

validate_pipeline_settings :: proc(settings: Pipeline_Settings) -> Error {
	if err := validate_vertex_layout(settings.layout); err != .None {
		return err
	}

	if settings.depth.compare < .Less ||
	   settings.depth.compare > .Always ||
	   settings.raster.cull < .None ||
	   settings.raster.cull > .Front ||
	   settings.raster.winding < .CCW ||
	   settings.raster.winding > .CW ||
	   settings.primitive < .Triangles ||
	   settings.primitive > .Points {
		return .Invalid_Pipeline_State
	}

	for factor in ([4]Blend_Factor {
			settings.blend.src_factor_rgb,
			settings.blend.dst_factor_rgb,
			settings.blend.src_factor_alpha,
			settings.blend.dst_factor_alpha,
		}) {
		if factor < .Zero || factor > .One_Minus_Dst_Alpha {
			return .Invalid_Pipeline_State
		}
	}

	if settings.blend.op_rgb < .Add ||
	   settings.blend.op_rgb > .Max ||
	   settings.blend.op_alpha < .Add ||
	   settings.blend.op_alpha > .Max {
		return .Invalid_Pipeline_State
	}

	return .None
}

// Linking finishes here; the linked pipeline survives destruction of its shader stages.
create_pipeline :: proc(device: ^Device, desc: Pipeline_Desc) -> (Pipeline_Handle, Error) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	if err := validate_pipeline_settings(desc.settings); err != .None {
		return {}, err
	}

	if err := validate_uniform_blocks(desc.uniform_blocks); err != .None {
		return {}, err
	}

	if err := validate_texture_bindings(desc.textures); err != .None {
		return {}, err
	}

	vertex := pool.get(&device.shaders, desc.vertex_shader)
	fragment := pool.get(&device.shaders, desc.fragment_shader)
	if vertex == nil || fragment == nil {
		return {}, .Invalid_Handle
	}

	if vertex.stage != .Vertex || fragment.stage != .Fragment {
		return {}, .Unsupported_Shader_Stage
	}

	handle, slot := pool.alloc(&device.pipelines)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	native, err := backend.create_pipeline(
		vertex.native,
		fragment.native,
		desc.label,
		desc.uniform_blocks,
		desc.textures,
		device.pipelines.allocator,
	)
	if err != .None {
		pool.free(&device.pipelines, handle)
		return {}, err
	}

	slot.native = native
	slot.settings = desc.settings
	slot.uniform_sizes = backend.pipeline_uniform_sizes(native)
	slot.texture_bindings = native.texture_bindings

	return handle, .None
}

validate_uniform_blocks :: proc(blocks: []Uniform_Block_Desc) -> Error {
	if len(blocks) > MAX_UNIFORM_BINDINGS {
		return .Invalid_Uniform_Binding
	}

	for block, i in blocks {
		if block.binding >= MAX_UNIFORM_BINDINGS ||
		   len(block.name) == 0 ||
		   strings.contains(block.name, "\x00") {
			return .Invalid_Uniform_Binding
		}

		for previous in blocks[:i] {
			if previous.binding == block.binding || previous.name == block.name {
				return .Invalid_Uniform_Binding
			}
		}
	}

	return .None
}

validate_texture_bindings :: proc(bindings: []Texture_Binding_Desc) -> Error {
	if len(bindings) > MAX_TEXTURE_BINDINGS {
		return .Invalid_Texture_Binding
	}

	for binding, i in bindings {
		if binding.binding >= MAX_TEXTURE_BINDINGS ||
		   len(binding.name) == 0 ||
		   strings.contains(binding.name, "\x00") {
			return .Invalid_Texture_Binding
		}

		for previous in bindings[:i] {
			if previous.binding == binding.binding || previous.name == binding.name {
				return .Invalid_Texture_Binding
			}
		}
	}

	return .None
}

destroy_pipeline :: proc(device: ^Device, handle: Pipeline_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.pipelines, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := backend.wait_idle(); err != .None {
		return err
	}

	if err := backend.destroy_pipeline(&slot.native); err != .None {
		return err
	}

	pool.free(&device.pipelines, handle)

	return .None
}
