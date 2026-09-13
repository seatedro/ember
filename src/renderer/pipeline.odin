package renderer

import "../core/pool"
import "../rhi"
import "../shaders"

Pipeline :: struct {
	shader: shaders.Shader,
	handle: rhi.Pipeline_Handle,
}

Pipeline_Settings :: rhi.Pipeline_Settings
Texture_Binding_Desc :: rhi.Texture_Binding_Desc

create_pipeline :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
	settings: Pipeline_Settings,
	textures: []Texture_Binding_Desc = nil,
	lighting: bool = false,
) -> (
	pipeline: Pipeline,
	err: Error,
) {
	mesh_settings := settings
	if settings.instance_layout != (Vertex_Layout{}) &&
	   settings.instance_layout != INSTANCE_LAYOUT {
		return {}, .Invalid_Vertex_Layout
	}

	mesh_settings.instance_layout = INSTANCE_LAYOUT
	blocks := [3]rhi.Uniform_Block_Desc {
		{name = "Per_View", binding = VIEW_BINDING},
		{name = "Material", binding = MATERIAL_BINDING},
		{name = "Lighting_Uniforms", binding = LIGHTING_BINDING},
	}

	block_count := 2
	if lighting {
		block_count = 3
	}

	pipeline.handle, err = rhi.create_pipeline(
		renderer.device,
		{
			vertex_shader = shader.vertex,
			fragment_shader = shader.fragment,
			settings = mesh_settings,
			uniform_blocks = blocks[:block_count],
			textures = textures,
			label = "mesh draw",
		},
	)
	if err != .None {
		return
	}

	slot := pool.get(&renderer.device.pipelines, pipeline.handle)
	if slot.requirements.uniform_sizes[VIEW_BINDING] > size_of(Per_View) ||
	   slot.requirements.uniform_sizes[LIGHTING_BINDING] > size_of(Lighting_Uniforms) {
		destroy_pipeline(renderer, &pipeline)
		return pipeline, .Invalid_Size
	}

	pipeline.shader = shader

	return
}

destroy_pipeline :: proc(renderer: ^Renderer, pipeline: ^Pipeline) -> Error {
	if pipeline.handle.generation != 0 {
		if err := rhi.destroy_pipeline(renderer.device, pipeline.handle); err != .None {
			return err
		}
	}

	pipeline^ = {}

	return .None
}

@(private)
validate_draw :: proc(
	device: ^rhi.Device,
	pipeline: ^Pipeline,
	mesh: ^Mesh,
	material: ^Material,
) -> Error {
	slot := pool.get(&device.pipelines, pipeline.handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if slot.settings.layout != mesh.layout {
		return .Invalid_Vertex_Layout
	}

	if pipeline.shader != material.shader {
		return .Invalid_Pipeline_State
	}

	parameters := pool.get(&device.buffers, material.parameters)
	if parameters == nil {
		return .Invalid_Handle
	}

	if .Uniform not_in parameters.usage {
		return .Invalid_Buffer_Binding
	}

	if slot.requirements.uniform_sizes[MATERIAL_BINDING] > parameters.size {
		return .Invalid_Size
	}

	for required, binding in slot.requirements.texture_bindings {
		if !required {
			continue
		}

		if pool.get(&device.textures, material.textures[binding]) == nil {
			return .Invalid_Handle
		}
	}

	return .None
}
