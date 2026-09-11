package renderer

import "../camera"
import emath "../core/math"
import "../rhi"
import "core:mem"

Error :: rhi.Error

Renderer :: struct {
	device:          ^rhi.Device,
	uniforms:        rhi.Buffer_Handle,
	view_projection: emath.Mat4,
}

@(private)
Per_Object :: struct {
	mvp, normals: emath.Mat4,
}

create :: proc(device: ^rhi.Device) -> (renderer: Renderer, err: Error) {
	renderer.device = device
	renderer.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_Object), usage = {.Uniform}, label = "mesh transforms"},
	)
	if err != .None {return {}, err}
	return
}

begin_frame :: proc(
	renderer: ^Renderer,
	view: camera.Camera,
	projection: emath.Mat4,
	clear_color: [4]f32 = {0.1, 0.1, 0.1, 1},
) -> Error {
	if err := rhi.validate_device(renderer.device); err != .None {return err}
	renderer.view_projection = projection * camera.view_matrix(view)
	rhi.clear(renderer.device, clear_color, 1)
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
	if err := rhi.validate_device(device); err != .None {return err}
	if err := bind_mesh(device, mesh); err != .None {return err}
	if err := validate_material(device, pipeline, material); err != .None {return err}
	data := [1]Per_Object {
		{
			mvp = renderer.view_projection * emath.transform_matrix(transform),
			normals = emath.normal_matrix(transform),
		},
	}
	if err := rhi.update_buffer(device, renderer.uniforms, 0, mem.slice_to_bytes(data[:]));
	   err != .None {return err}
	if err := rhi.bind_pipeline(device, pipeline.handle); err != .None {return err}
	if err := rhi.bind_uniform_buffer(device, 0, renderer.uniforms); err != .None {return err}
	if err := rhi.bind_uniform_buffer(device, 1, material.parameters); err != .None {return err}
	return rhi.draw_indexed(device, {index_count = mesh.index_count})
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	if renderer.uniforms.generation != 0 {
		err := rhi.destroy_buffer(renderer.device, renderer.uniforms)
		if err == .None {renderer.uniforms = {}} else if result == .None {result = err}
	}
	if result == .None {renderer^ = {}}
	return
}
