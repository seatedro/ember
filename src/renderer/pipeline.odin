package renderer

import "../geometry"
import "../rhi"
import "../shaders"

Pipeline :: struct {
	shader: shaders.Shader,
	handle: rhi.Pipeline_Handle,
}

@(private)
MESH_SETTINGS :: rhi.Pipeline_Settings {
	layout = {
		stride = size_of(geometry.Vertex),
		attribute_count = 2,
		attributes = {
			0 = {
				location = 0,
				format = .F32x3,
				offset = u32(offset_of(geometry.Vertex, position)),
			},
			1 = {location = 1, format = .F32x3, offset = u32(offset_of(geometry.Vertex, normal))},
		},
	},
	depth = {test_enabled = true, write_enabled = true, compare = .Less},
	raster = {cull = .Back, winding = .CCW},
}

create_pipeline :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
) -> (
	pipeline: Pipeline,
	err: Error,
) {
	pipeline.handle, err = rhi.create_pipeline(
		renderer.device,
		{
			vertex_shader = shader.vertex,
			fragment_shader = shader.fragment,
			settings = MESH_SETTINGS,
			uniform_blocks = {
				{name = "Per_Object", binding = 0},
				{name = "Material", binding = 1},
			},
			label = "mesh draw",
		},
	)
	if err != .None {return}
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
		if err := rhi.destroy_pipeline(renderer.device, pipeline.handle); err != .None {return err}
	}
	pipeline^ = {}
	return .None
}

@(private)
validate_material :: proc(device: ^rhi.Device, pipeline: ^Pipeline, material: ^Material) -> Error {
	slot := rhi.pipeline_pool_lookup(&device.pipelines, pipeline.handle)
	if slot == nil {return .Invalid_Handle}
	if pipeline.shader != material.shader {return .Invalid_Pipeline_State}
	parameters := rhi.buffer_pool_lookup(&device.buffers, material.parameters)
	if parameters == nil {return .Invalid_Handle}
	if .Uniform not_in parameters.usage {return .Invalid_Buffer_Binding}
	if slot.uniform_sizes[1] > parameters.size {return .Invalid_Size}
	return .None
}
