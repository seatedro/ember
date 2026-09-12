package game

import "core:log"
import emath "ember:core/math"
import render "ember:renderer"
import shader "ember:shaders"

Grid_Vertex :: struct {
	position: emath.Vec3,
	color:    emath.Vec3,
}

GRID_EXTENT :: 10
GRID_VERTEX_COUNT :: (2 * GRID_EXTENT + 1) * 4
GRID_HEIGHT :: f32(-1.05)

GRID_LAYOUT :: render.Vertex_Layout {
	stride = size_of(Grid_Vertex),
	attribute_count = 2,
	attributes = {
		0 = {location = 0, format = .F32x3, offset = u32(offset_of(Grid_Vertex, position))},
		1 = {location = 1, format = .F32x3, offset = u32(offset_of(Grid_Vertex, color))},
	},
}

Grid_Parameters :: struct {
	tint: [4]f32,
}

init_grid :: proc(game: ^State) -> bool {
	program, shader_error := shader.load(&game.shaders, "game/assets/shaders/grid")
	if shader_error != .None {
		log.errorf("Load grid shader: %v", shader_error)
		return false
	}
	err: render.Error
	game.grid_pipeline, err = render.create_pipeline(
		&game.renderer,
		program,
		{
			layout = GRID_LAYOUT,
			primitive = .Lines,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = .None, winding = .CCW},
		},
	)
	if !check(err, "create grid pipeline") {return false}
	game.grid_material, err = render.create_material(
		&game.renderer,
		program,
		Grid_Parameters{tint = {1, 1, 1, 1}},
	)
	if !check(err, "create grid material") {return false}
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

	game.grid_mesh, err = render.create_mesh(&game.renderer, vertices[:], indices[:], GRID_LAYOUT)
	return check(err, "create grid mesh")
}
