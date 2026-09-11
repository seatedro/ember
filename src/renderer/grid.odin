package renderer

import emath "../core/math"
import "../rhi"
import "core:mem"

Grid :: struct {
	mesh:     Mesh,
	uniforms: rhi.Buffer_Handle,
	pipeline: rhi.Pipeline_Handle,
}

@(private)
Grid_Vertex :: struct {
	position: emath.Vec3,
	color:    emath.Vec3,
}

@(private)
GRID_EXTENT :: 10
@(private)
GRID_VERTEX_COUNT :: (2 * GRID_EXTENT + 1) * 4
@(private)
GRID_HEIGHT :: f32(-1.05)

create_grid :: proc(renderer: ^Renderer) -> (grid: Grid, err: Error) {
	err = init_grid(renderer.device, &grid)
	if err != .None {destroy_grid(renderer, &grid)}
	return
}

@(private)
init_grid :: proc(device: ^rhi.Device, grid: ^Grid) -> Error {
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


	err: Error
	grid.mesh, err = upload_mesh(device, vertices[:], indices[:])
	if err != .None {return err}
	grid.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(emath.Mat4), usage = {.Uniform}, label = "grid view projection"},
	)
	if err != .None {return err}
	vertex, vertex_error := rhi.create_shader(
		device,
		{stage = .Vertex, source = #load("shaders/grid.vert"), label = "grid vertex"},
	)
	if vertex_error != .None {return vertex_error}
	defer rhi.destroy_shader(device, vertex)
	fragment, fragment_error := rhi.create_shader(
		device,
		{stage = .Fragment, source = #load("shaders/grid.frag"), label = "grid fragment"},
	)
	if fragment_error != .None {return fragment_error}
	defer rhi.destroy_shader(device, fragment)
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
	return err
}

draw_grid :: proc(renderer: ^Renderer, grid: ^Grid) -> Error {
	device := renderer.device
	data := [1]emath.Mat4{renderer.view_projection}
	if err := rhi.update_buffer(device, grid.uniforms, 0, mem.slice_to_bytes(data[:]));
	   err != .None {return err}
	if err := rhi.bind_pipeline(device, grid.pipeline); err != .None {return err}
	if err := bind_mesh(device, &grid.mesh); err != .None {return err}
	if err := rhi.bind_uniform_buffer(device, 0, grid.uniforms); err != .None {return err}
	return rhi.draw_indexed(device, {index_count = grid.mesh.index_count})
}

destroy_grid :: proc(renderer: ^Renderer, grid: ^Grid) -> (result: Error) {
	if grid.pipeline.generation != 0 {
		result = rhi.destroy_pipeline(renderer.device, grid.pipeline)
		if result == .None {grid.pipeline = {}}
	}
	if grid.uniforms.generation != 0 {
		err := rhi.destroy_buffer(renderer.device, grid.uniforms)
		if err == .None {grid.uniforms = {}} else if result == .None {result = err}
	}
	if err := release_mesh(renderer.device, &grid.mesh); result == .None {result = err}
	if result == .None {grid^ = {}}
	return
}
