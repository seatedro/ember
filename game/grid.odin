package game

import "core:mem"
import emath "ember:core/math"
import "ember:rhi"

Grid :: struct {
	vertices: rhi.Buffer_Handle,
	indices:  rhi.Buffer_Handle,
	uniforms: rhi.Buffer_Handle,
	pipeline: rhi.Pipeline_Handle,
}

Grid_Vertex :: struct {
	position: emath.Vec3,
	color:    emath.Vec3,
}

GRID_EXTENT :: 10
GRID_VERTEX_COUNT :: (2 * GRID_EXTENT + 1) * 4
GRID_HEIGHT :: f32(-1.05)

create_grid :: proc(grid: ^Grid, device: ^rhi.Device) -> bool {
	vertices: [GRID_VERTEX_COUNT]Grid_Vertex
	indices: [GRID_VERTEX_COUNT]u32
	for coordinate in -GRID_EXTENT ..= GRID_EXTENT {
		i := (coordinate + GRID_EXTENT) * 4
		p := f32(coordinate)
		color := emath.Vec3{0.22, 0.23, 0.25}
		if coordinate % 5 == 0 {
			color = {0.32, 0.33, 0.35}
		}
		x_color, z_color := color, color
		if coordinate == 0 {
			x_color = {0.6, 0.22, 0.2}
			z_color = {0.2, 0.35, 0.65}
		}
		vertices[i + 0] = {{-GRID_EXTENT, GRID_HEIGHT, p}, x_color}
		vertices[i + 1] = {{GRID_EXTENT, GRID_HEIGHT, p}, x_color}
		vertices[i + 2] = {{p, GRID_HEIGHT, -GRID_EXTENT}, z_color}
		vertices[i + 3] = {{p, GRID_HEIGHT, GRID_EXTENT}, z_color}
	}
	for &index, i in indices {
		index = u32(i)
	}

	err: rhi.Error
	grid.vertices, err = rhi.create_buffer(
		device,
		{size = size_of(vertices), usage = {.Vertex}, label = "grid vertices"},
		mem.slice_to_bytes(vertices[:]),
	)
	if !check(err, "create grid vertices") {return false}
	grid.indices, err = rhi.create_buffer(
		device,
		{size = size_of(indices), usage = {.Index}, label = "grid indices"},
		mem.slice_to_bytes(indices[:]),
	)
	if !check(err, "create grid indices") {return false}
	grid.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(emath.Mat4), usage = {.Uniform}, label = "grid view projection"},
	)
	if !check(err, "create grid uniforms") {return false}

	vertex, vertex_error := rhi.create_shader(
		device,
		{stage = .Vertex, source = #load("../shaders/grid.vert"), label = "grid vertex"},
	)
	if !check(vertex_error, "compile grid vertex shader") {return false}
	defer check(rhi.destroy_shader(device, vertex), "destroy grid vertex shader")
	fragment, fragment_error := rhi.create_shader(
		device,
		{stage = .Fragment, source = #load("../shaders/grid.frag"), label = "grid fragment"},
	)
	if !check(fragment_error, "compile grid fragment shader") {return false}
	defer check(rhi.destroy_shader(device, fragment), "destroy grid fragment shader")

	grid.pipeline, err = rhi.create_pipeline(
		device,
		{
			vertex_shader = vertex,
			fragment_shader = fragment,
			settings = {
				layout = {
					stride = size_of(Grid_Vertex),
					attribute_count = 2,
					attributes = {
						0 = {
							location = 0,
							format = .F32x3,
							offset = u32(offset_of(Grid_Vertex, position)),
						},
						1 = {
							location = 1,
							format = .F32x3,
							offset = u32(offset_of(Grid_Vertex, color)),
						},
					},
				},
				primitive = .Lines,
				depth = {test_enabled = true, write_enabled = true, compare = .Less},
			},
			uniform_blocks = {{name = "Grid_View", binding = 0}},
			label = "ground grid",
		},
	)
	return check(err, "create grid pipeline")
}

draw_grid :: proc(grid: ^Grid, device: ^rhi.Device, view_projection: emath.Mat4) -> bool {
	data := [1]emath.Mat4{view_projection}
	if !check(
		rhi.update_buffer(device, grid.uniforms, 0, mem.slice_to_bytes(data[:])),
		"update grid view",
	) {
		return false
	}
	if !check(rhi.bind_pipeline(device, grid.pipeline), "bind grid pipeline") {return false}
	if !check(rhi.bind_vertex_buffer(device, grid.vertices), "bind grid vertices") {return false}
	if !check(
		rhi.bind_index_buffer(device, grid.indices, .U32),
		"bind grid indices",
	) {return false}
	if !check(
		rhi.bind_uniform_buffer(device, 0, grid.uniforms),
		"bind grid uniforms",
	) {return false}
	return check(rhi.draw_indexed(device, {index_count = GRID_VERTEX_COUNT}), "draw grid")
}

destroy_grid :: proc(grid: ^Grid, device: ^rhi.Device) {
	if grid.pipeline.generation != 0 {
		check(rhi.destroy_pipeline(device, grid.pipeline), "destroy grid pipeline")
	}
	for buffer in ([3]rhi.Buffer_Handle{grid.vertices, grid.indices, grid.uniforms}) {
		if buffer.generation != 0 {
			check(rhi.destroy_buffer(device, buffer), "destroy grid buffer")
		}
	}
	grid^ = {}
}
