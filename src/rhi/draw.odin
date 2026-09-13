package rhi

import "../core/pool"
import "backend"
import "types"

Index_Type :: types.Index_Type
Draw_Indexed_Desc :: types.Draw_Indexed_Desc

Bindings :: struct {
	pipeline:        Pipeline_Handle,
	vertex_buffer:   Buffer_Handle,
	vertex_offset:   u64,
	index_buffer:    Buffer_Handle,
	index_offset:    u64,
	index_type:      Index_Type,
	uniform_buffers: [MAX_UNIFORM_BINDINGS]Buffer_Handle,
	textures:        [MAX_TEXTURE_BINDINGS]Texture_Handle,
}

bind_texture :: proc(device: ^Device, binding: u32, handle: Texture_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if binding >= MAX_TEXTURE_BINDINGS {
		return .Invalid_Texture_Binding
	}

	if pool.get(&device.textures, handle) == nil {
		return .Invalid_Handle
	}

	device.bindings.textures[binding] = handle

	return .None
}

bind_uniform_buffer :: proc(device: ^Device, binding: u32, handle: Buffer_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if binding >= MAX_UNIFORM_BINDINGS {
		return .Invalid_Uniform_Binding
	}

	slot := pool.get(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if .Uniform not_in slot.usage {
		return .Invalid_Buffer_Binding
	}

	device.bindings.uniform_buffers[binding] = handle

	return .None
}

// Resolve handles again at draw time: a bound resource may have been destroyed.
bind_pipeline :: proc(device: ^Device, handle: Pipeline_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if pool.get(&device.pipelines, handle) == nil {
		return .Invalid_Handle
	}

	device.bindings.pipeline = handle

	return .None
}

bind_vertex_buffer :: proc(device: ^Device, handle: Buffer_Handle, offset: u64 = 0) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if .Vertex not_in slot.usage || offset >= slot.size || offset % 4 != 0 {
		return .Invalid_Buffer_Binding
	}

	device.bindings.vertex_buffer = handle
	device.bindings.vertex_offset = offset

	return .None
}

bind_index_buffer :: proc(
	device: ^Device,
	handle: Buffer_Handle,
	index_type: Index_Type,
	offset: u64 = 0,
) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if index_type != .U16 && index_type != .U32 {
		return .Invalid_Buffer_Binding
	}

	width := u64(2) if index_type == .U16 else u64(4)
	if .Index not_in slot.usage || offset >= slot.size || offset % width != 0 {
		return .Invalid_Buffer_Binding
	}

	device.bindings.index_buffer = handle
	device.bindings.index_offset = offset
	device.bindings.index_type = index_type

	return .None
}

validate_indexed_range :: proc(
	desc: Draw_Indexed_Desc,
	index_type: Index_Type,
	offset, size: u64,
) -> Error {
	if desc.index_count == 0 || desc.index_count > u32(max(i32)) {
		return .Invalid_Draw
	}

	if index_type != .U16 && index_type != .U32 {
		return .Invalid_Buffer_Binding
	}

	width := u64(2) if index_type == .U16 else u64(4)
	if offset > size || offset % width != 0 {
		return .Invalid_Draw
	}

	available := (size - offset) / width
	if u64(desc.first_index) > available ||
	   u64(desc.index_count) > available - u64(desc.first_index) {
		return .Invalid_Draw
	}

	return .None
}

// Index values must refer to initialized vertices in the bound stream. The RHI
// validates the index byte range; it does not read GPU indices back to the CPU.
draw_indexed :: proc(device: ^Device, desc: Draw_Indexed_Desc) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	bindings := device.bindings
	pipeline := pool.get(&device.pipelines, bindings.pipeline)
	vertex := pool.get(&device.buffers, bindings.vertex_buffer)
	index := pool.get(&device.buffers, bindings.index_buffer)
	if pipeline == nil || vertex == nil || index == nil {
		return .Invalid_Handle
	}

	if .Vertex not_in vertex.usage || .Index not_in index.usage {
		return .Invalid_Buffer_Binding
	}

	if bindings.vertex_offset > vertex.size ||
	   u64(pipeline.settings.layout.stride) > vertex.size - bindings.vertex_offset {
		return .Invalid_Buffer_Binding
	}

	if err := validate_indexed_range(desc, bindings.index_type, bindings.index_offset, index.size);
	   err != .None {
		return err
	}

	width := u64(2) if bindings.index_type == .U16 else u64(4)
	uniforms: [MAX_UNIFORM_BINDINGS]backend.Buffer

	for required_size, binding in pipeline.uniform_sizes {
		if required_size == 0 {
			continue
		}

		uniform := pool.get(&device.buffers, bindings.uniform_buffers[binding])
		if uniform == nil {
			return .Invalid_Handle
		}

		if .Uniform not_in uniform.usage || uniform.size < required_size {
			return .Invalid_Buffer_Binding
		}

		uniforms[binding] = uniform.native
	}

	textures: [MAX_TEXTURE_BINDINGS]backend.Texture

	for required, binding in pipeline.texture_bindings {
		if !required {
			continue
		}

		texture := pool.get(&device.textures, bindings.textures[binding])
		if texture == nil {
			return .Invalid_Handle
		}

		textures[binding] = texture.native
	}

	return backend.draw_indexed(
		pipeline.native,
		pipeline.settings,
		vertex.native,
		bindings.vertex_offset,
		index.native,
		bindings.index_type,
		bindings.index_offset + u64(desc.first_index) * width,
		desc.index_count,
		uniforms,
		textures,
	)
}
