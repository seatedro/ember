package renderer

import "../rhi"
import "../shaders"
import "core:mem"

Material :: struct {
	shader:     shaders.Shader,
	parameters: rhi.Buffer_Handle,
	textures:   [rhi.MAX_TEXTURE_BINDINGS]rhi.Texture_Handle,
}

Texture_Binding :: struct {
	binding: u32,
	texture: Texture,
}

create_material :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
	parameters: $Parameters,
	textures: []Texture_Binding = nil,
) -> (
	material: Material,
	err: Error,
) {
	device := renderer.device
	if err = rhi.validate_device(device); err != .None {
		return
	}

	vertex := rhi.shader_pool_lookup(&device.shaders, shader.vertex)
	fragment := rhi.shader_pool_lookup(&device.shaders, shader.fragment)
	if vertex == nil || fragment == nil {
		return {}, .Invalid_Handle
	}

	if vertex.stage != .Vertex || fragment.stage != .Fragment {
		return {}, .Unsupported_Shader_Stage
	}

	if size_of(Parameters) == 0 {
		return {}, .Invalid_Size
	}

	if len(textures) > rhi.MAX_TEXTURE_BINDINGS {
		return {}, .Invalid_Texture_Binding
	}

	handles: [rhi.MAX_TEXTURE_BINDINGS]rhi.Texture_Handle

	for texture in textures {
		if texture.binding >= rhi.MAX_TEXTURE_BINDINGS {
			return {}, .Invalid_Texture_Binding
		}

		if handles[texture.binding].generation != 0 {
			return {}, .Invalid_Texture_Binding
		}

		if rhi.texture_pool_lookup(&device.textures, texture.texture.handle) == nil {
			return {}, .Invalid_Handle
		}

		handles[texture.binding] = texture.texture.handle
	}

	data := [1]Parameters{parameters}
	material.parameters, err = rhi.create_buffer(
		device,
		{size = size_of(Parameters), usage = {.Uniform}, label = "material parameters"},
		mem.slice_to_bytes(data[:]),
	)

	if err == .None {
		material.shader = shader
		material.textures = handles
	}

	return
}

destroy_material :: proc(renderer: ^Renderer, material: ^Material) -> Error {
	if material.parameters.generation != 0 {
		if err := rhi.destroy_buffer(renderer.device, material.parameters); err != .None {
			return err
		}
	}

	material^ = {}

	return .None
}
