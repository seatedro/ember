package renderer

import "../camera"
import emath "../core/math"
import "../rhi"
import "core:mem"

Error :: rhi.Error

Renderer :: struct {
	device:            ^rhi.Device,
	view_uniforms:     rhi.Buffer_Handle,
	object_uniforms:   rhi.Buffer_Handle,
	lighting_uniforms: rhi.Buffer_Handle,
}

@(private)
VIEW_BINDING :: 0

@(private)
OBJECT_BINDING :: 1

@(private)
MATERIAL_BINDING :: 2

@(private)
LIGHTING_BINDING :: 3

@(private)
Per_View :: struct {
	view_projection: emath.Mat4,
}

@(private)
Per_Object :: struct {
	model, normals: emath.Mat4,
}

create :: proc(device: ^rhi.Device) -> (renderer: Renderer, err: Error) {
	renderer.device = device
	renderer.view_uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_View), usage = {.Uniform}, label = "view transforms"},
	)
	if err != .None {
		return {}, err
	}

	renderer.object_uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_Object), usage = {.Uniform}, label = "mesh transforms"},
	)
	if err != .None {
		destroy(&renderer)
		return
	}

	renderer.lighting_uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Lighting_Uniforms), usage = {.Uniform}, label = "lighting"},
	)
	if err != .None {
		destroy(&renderer)
		return
	}

	return
}

set_view :: proc(
	renderer: ^Renderer,
	view: camera.Camera,
	projection: emath.Mat4,
	lighting: Lighting = {},
) -> Error {
	if err := rhi.validate_device(renderer.device); err != .None {
		return err
	}

	packed_lighting, lighting_error := pack_lighting(lighting)
	if lighting_error != .None {
		return lighting_error
	}

	lighting_data := [1]Lighting_Uniforms{packed_lighting}
	if err := rhi.update_buffer(
		renderer.device,
		renderer.lighting_uniforms,
		0,
		mem.slice_to_bytes(lighting_data[:]),
	); err != .None {
		return err
	}

	data := [1]Per_View{{view_projection = projection * camera.view_matrix(view)}}
	if err := rhi.update_buffer(
		renderer.device,
		renderer.view_uniforms,
		0,
		mem.slice_to_bytes(data[:]),
	); err != .None {
		return err
	}

	return .None
}

draw_mesh :: proc(
	renderer: ^Renderer,
	pipeline: ^Pipeline,
	mesh: ^Mesh,
	material: ^Material,
	transform: emath.Transform,
) -> Error {
	device := renderer.device
	if err := rhi.validate_device(device); err != .None {
		return err
	}

	if !device.pass_active {
		return .Invalid_Pass
	}

	if err := bind_mesh(device, mesh); err != .None {
		return err
	}

	if err := validate_draw(device, pipeline, mesh, material); err != .None {
		return err
	}

	data := [1]Per_Object {
		{model = emath.transform_matrix(transform), normals = emath.normal_matrix(transform)},
	}

	if err := rhi.update_buffer(device, renderer.object_uniforms, 0, mem.slice_to_bytes(data[:]));
	   err != .None {
		return err
	}

	if err := rhi.bind_pipeline(device, pipeline.handle); err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, VIEW_BINDING, renderer.view_uniforms); err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, OBJECT_BINDING, renderer.object_uniforms);
	   err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, MATERIAL_BINDING, material.parameters);
	   err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, LIGHTING_BINDING, renderer.lighting_uniforms);
	   err != .None {
		return err
	}

	for texture, binding in material.textures {
		if texture.generation == 0 {
			continue
		}

		if err := rhi.bind_texture(device, u32(binding), texture); err != .None {
			return err
		}
	}

	return rhi.draw_indexed(device, {index_count = mesh.index_count})
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	for handle in ([3]^rhi.Buffer_Handle {
			&renderer.lighting_uniforms,
			&renderer.object_uniforms,
			&renderer.view_uniforms,
		}) {
		if handle.generation == 0 {
			continue
		}

		err := rhi.destroy_buffer(renderer.device, handle^)
		if err == .None {
			handle^ = {}
		} else if result == .None {
			result = err
		}
	}

	if result == .None {
		renderer^ = {}
	}

	return
}
