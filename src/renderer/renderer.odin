package renderer

import "../camera"
import emath "../core/math"
import "../geometry"
import "../rhi"
import "../shaders"
import "core:mem"

Error :: rhi.Error

Renderer :: struct {
	device:          ^rhi.Device,
	pipeline:        rhi.Pipeline_Handle,
	uniforms:        rhi.Buffer_Handle,
	view_projection: emath.Mat4,
}

@(private)
Per_Object :: struct {
	mvp, normals: emath.Mat4,
}

create :: proc(device: ^rhi.Device, shader: shaders.Shader) -> (renderer: Renderer, err: Error) {
	renderer.device = device
	renderer.pipeline, err = rhi.create_pipeline(
		device,
		{
			vertex_shader = shader.vertex,
			fragment_shader = shader.fragment,
			settings = {
				layout = {
					stride = size_of(geometry.Vertex),
					attribute_count = 2,
					attributes = {
						0 = {
							location = 0,
							format = .F32x3,
							offset = u32(offset_of(geometry.Vertex, position)),
						},
						1 = {
							location = 1,
							format = .F32x3,
							offset = u32(offset_of(geometry.Vertex, normal)),
						},
					},
				},
				depth = {test_enabled = true, write_enabled = true, compare = .Less},
				raster = {cull = .Back, winding = .CCW},
			},
			uniform_blocks = {{name = "Per_Object", binding = 0}},
			label = "mesh",
		},
	)
	if err != .None {return {}, err}
	renderer.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_Object), usage = {.Uniform}, label = "mesh transforms"},
	)
	if err != .None {destroy(&renderer)}
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

draw_mesh :: proc(renderer: ^Renderer, mesh: ^Mesh, transform: emath.Transform) -> Error {
	data := [1]Per_Object {
		{
			mvp = renderer.view_projection * emath.transform_matrix(transform),
			normals = emath.normal_matrix(transform),
		},
	}
	device := renderer.device
	if err := rhi.update_buffer(device, renderer.uniforms, 0, mem.slice_to_bytes(data[:]));
	   err != .None {return err}
	if err := rhi.bind_pipeline(device, renderer.pipeline); err != .None {return err}
	if err := rhi.bind_uniform_buffer(device, 0, renderer.uniforms); err != .None {return err}
	if err := bind_mesh(device, mesh); err != .None {return err}
	return rhi.draw_indexed(device, {index_count = mesh.index_count})
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	if renderer.pipeline.generation != 0 {
		result = rhi.destroy_pipeline(renderer.device, renderer.pipeline)
		if result == .None {renderer.pipeline = {}}
	}
	if renderer.uniforms.generation != 0 {
		err := rhi.destroy_buffer(renderer.device, renderer.uniforms)
		if err == .None {renderer.uniforms = {}} else if result == .None {result = err}
	}
	if result == .None {renderer^ = {}}
	return
}
