package renderer

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
) -> (
	pipeline: Pipeline,
	err: Error,
) {
	pipeline.handle, err = rhi.create_pipeline(
		renderer.device,
		{
			vertex_shader = shader.vertex,
			fragment_shader = shader.fragment,
			settings = settings,
			uniform_blocks = {
				{name = "Per_Object", binding = 0},
				{name = "Material", binding = 1},
			},
			textures = textures,
			label = "mesh draw",
		},
	)
	if err != .None {
		return
	}

	slot := rhi.pipeline_pool_lookup(&renderer.device.pipelines, pipeline.handle)
	if slot.uniform_sizes[0] > size_of(Per_Object) {
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
	slot := rhi.pipeline_pool_lookup(&device.pipelines, pipeline.handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if slot.settings.layout != mesh.layout {
		return .Invalid_Vertex_Layout
	}

	if pipeline.shader != material.shader {
		return .Invalid_Pipeline_State
	}

	parameters := rhi.buffer_pool_lookup(&device.buffers, material.parameters)
	if parameters == nil {
		return .Invalid_Handle
	}

	if .Uniform not_in parameters.usage {
		return .Invalid_Buffer_Binding
	}

	if slot.uniform_sizes[1] > parameters.size {
		return .Invalid_Size
	}

	for required, binding in slot.texture_bindings {
		if !required {
			continue
		}

		if rhi.texture_pool_lookup(&device.textures, material.textures[binding]) == nil {
			return .Invalid_Handle
		}
	}

	return .None
}
