package renderer

import "../camera"
import emath "../core/math"
import "../geometry"
import "../rhi"
import "core:mem"

Error :: rhi.Error

Renderer :: struct {
	device:            ^rhi.Device,
	vertices, indices: rhi.Buffer_Handle,
	index_count:       u32,
	pipeline:          rhi.Pipeline_Handle,
	uniforms:          rhi.Buffer_Handle,
	view_projection:   emath.Mat4,
}

@(private)
Per_Object :: struct {
	mvp, normals: emath.Mat4,
}

create :: proc(
	device: ^rhi.Device,
	vertices: []geometry.Sphere_Vertex,
	indices: []u32,
) -> (
	renderer: Renderer,
	err: Error,
) {
	renderer.device = device
	err = init_renderer(&renderer, vertices, indices)
	if err != .None {destroy(&renderer)}
	return
}

@(private)
init_renderer :: proc(
	renderer: ^Renderer,
	vertices: []geometry.Sphere_Vertex,
	indices: []u32,
) -> Error {
	if len(vertices) == 0 ||
	   len(indices) == 0 ||
	   u64(len(indices)) > u64(max(i32)) {return .Invalid_Size}
	for index in indices {if u64(index) >= u64(len(vertices)) {return .Invalid_Draw}}
	device := renderer.device
	err: Error
	vertex_bytes := mem.slice_to_bytes(vertices)
	renderer.vertices, err = rhi.create_buffer(
		device,
		{size = u64(len(vertex_bytes)), usage = {.Vertex}, label = "vertices"},
		vertex_bytes,
	)
	if err != .None {return err}
	index_bytes := mem.slice_to_bytes(indices)
	renderer.indices, err = rhi.create_buffer(
		device,
		{size = u64(len(index_bytes)), usage = {.Index}, label = "indices"},
		index_bytes,
	)
	if err != .None {return err}
	renderer.index_count = u32(len(indices))
	vertex, vertex_error := rhi.create_shader(
		device,
		{stage = .Vertex, source = #load("shaders/sphere.vert"), label = "mesh vertex"},
	)
	if vertex_error != .None {return vertex_error}
	defer rhi.destroy_shader(device, vertex)
	fragment, fragment_error := rhi.create_shader(
		device,
		{stage = .Fragment, source = #load("shaders/sphere.frag"), label = "mesh fragment"},
	)
	if fragment_error != .None {return fragment_error}
	defer rhi.destroy_shader(device, fragment)
	renderer.pipeline, err = rhi.create_pipeline(
		device,
		{
			vertex_shader = vertex,
			fragment_shader = fragment,
			settings = {
				layout = {
					stride = size_of(geometry.Sphere_Vertex),
					attribute_count = 2,
					attributes = {
						0 = {
							location = 0,
							format = .F32x3,
							offset = u32(offset_of(geometry.Sphere_Vertex, position)),
						},
						1 = {
							location = 1,
							format = .F32x3,
							offset = u32(offset_of(geometry.Sphere_Vertex, normal)),
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
	if err != .None {return err}
	renderer.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_Object), usage = {.Uniform}, label = "mesh transforms"},
	)
	return err
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

draw :: proc(renderer: ^Renderer, transform: emath.Transform) -> Error {
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
	if err := rhi.bind_vertex_buffer(device, renderer.vertices); err != .None {return err}
	if err := rhi.bind_index_buffer(device, renderer.indices, .U32); err != .None {return err}
	return rhi.draw_indexed(device, {index_count = renderer.index_count})
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	if renderer.pipeline.generation != 0 {
		result = rhi.destroy_pipeline(renderer.device, renderer.pipeline)
		if result == .None {renderer.pipeline = {}}
	}
	for handle in ([3]^rhi.Buffer_Handle {
			&renderer.uniforms,
			&renderer.indices,
			&renderer.vertices,
		}) {
		if handle.generation == 0 {continue}
		err := rhi.destroy_buffer(renderer.device, handle^)
		if err == .None {handle^ = {}} else if result == .None {result = err}
	}
	if result == .None {renderer^ = {}}
	return
}
