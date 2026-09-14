package renderer

import "../camera"
import emath "../core/math"
import "../rhi"
import "core:mem"

Error :: rhi.Error

Renderer :: struct {
	white_texture:           Texture,
	flat_normal:             Texture,
	shadow_texture:          rhi.Texture_Handle,
	device:                  ^rhi.Device,
	view_uniforms:           rhi.Buffer_Handle,
	instance_buffer:         rhi.Buffer_Handle,
	pending_instance_buffer: rhi.Buffer_Handle,
	instance_capacity:       int,
	lighting_uniforms:       rhi.Buffer_Handle,
}

@(private)
SHADOW_TEXTURE_BINDING :: rhi.MAX_TEXTURE_BINDINGS - 1

@(private)
VIEW_BINDING :: 0

@(private)
MATERIAL_BINDING :: 2

@(private)
LIGHTING_BINDING :: 3

@(private)
Per_View :: struct {
	view_projection: emath.Mat4,
	camera_position: [4]f32,
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

	renderer.instance_buffer, err = rhi.create_buffer(
		device,
		{size = size_of(Instance_Data), usage = {.Vertex}, label = "mesh instances"},
	)
	if err != .None {
		destroy(&renderer)
		return
	}

	renderer.instance_capacity = 1
	renderer.lighting_uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Lighting_Uniforms), usage = {.Uniform}, label = "lighting"},
	)
	if err != .None {
		destroy(&renderer)
		return
	}

	flat_normal := [1][4]f16{{0.5, 0.5, 1, 1}}
	renderer.flat_normal, err = create_texture(
		&renderer,
		{width = 1, height = 1, format = .RGBA16F, label = "flat normal"},
		mem.slice_to_bytes(flat_normal[:]),
	)
	if err != .None {
		destroy(&renderer)
		return
	}

	renderer.white_texture, err = create_texture(
		&renderer,
		{width = 1, height = 1, format = .RGBA8, label = "white"},
		{255, 255, 255, 255},
	)
	if err != .None {
		destroy(&renderer)
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

	renderer.shadow_texture = {}
	if lighting.shadow != nil {
		depth, err := rhi.render_target_depth(renderer.device, lighting.shadow.target.handle)
		if err != .None {
			return err
		}
		renderer.shadow_texture = depth
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

	data := [1]Per_View {
		{
			view_projection = projection * camera.view_matrix(view),
			camera_position = {view.position.x, view.position.y, view.position.z, 1},
		},
	}
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
	if err := rhi.validate_device(renderer.device); err != .None {
		return err
	}

	if !renderer.device.pass_active {
		return .Invalid_Pass
	}

	data := [1]Instance_Data{pack_instance(transform)}
	if err := upload_instances(renderer, data[:]); err != .None {
		return err
	}

	return draw_mesh_instances(renderer, pipeline, mesh, material, renderer.instance_buffer, 0, 1)
}

draw_mesh_instances :: proc(
	renderer: ^Renderer,
	pipeline: ^Pipeline,
	mesh: ^Mesh,
	material: ^Material,
	instances: rhi.Buffer_Handle,
	instance_offset: u64,
	instance_count: u32,
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

	if err := rhi.bind_instance_buffer(device, instances, instance_offset); err != .None {
		return err
	}

	if err := rhi.bind_pipeline(device, pipeline.handle); err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, VIEW_BINDING, renderer.view_uniforms); err != .None {
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

	if pipeline.shadows {
		if err := rhi.bind_texture(device, SHADOW_TEXTURE_BINDING, renderer.shadow_texture);
		   err != .None {
			return err
		}
	}

	return rhi.draw_indexed(
		device,
		{index_count = mesh.index_count, instance_count = instance_count},
	)
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	if err := destroy_texture(renderer, &renderer.white_texture); err != .None {
		result = err
	}

	if err := destroy_texture(renderer, &renderer.flat_normal); err != .None {
		result = err
	}

	for handle in ([4]^rhi.Buffer_Handle {
			&renderer.pending_instance_buffer,
			&renderer.lighting_uniforms,
			&renderer.instance_buffer,
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
