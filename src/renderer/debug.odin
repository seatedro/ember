package renderer

import "../geometry"
import "../shaders"

Debug_Grid :: struct {
	mesh:     Mesh,
	pipeline: Pipeline,
	material: Material,
}

create_debug_grid :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
	extent := 10,
	spacing: f32 = 1,
) -> (
	grid: Debug_Grid,
	err: Error,
) {
	data, geometry_error := geometry.create_grid(extent = extent, spacing = spacing)
	if geometry_error != .None {
		return {}, .Allocation_Failed if geometry_error == .Allocation_Failed else .Invalid_Size
	}

	defer geometry.destroy_grid(&data)
	program, shader_error := load_builtin_shader(library, .Grid)
	if shader_error != .None {
		return {}, .Backend_Failed
	}

	grid.pipeline, err = create_pipeline(
		renderer,
		program,
		{
			layout = COLOR_VERTEX_LAYOUT,
			primitive = .Lines,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
		},
	)
	if err != .None {
		return
	}

	grid.material, err = create_material(renderer, program, Tint_Parameters{tint = {1, 1, 1, 1}})
	if err != .None {
		destroy_debug_grid(renderer, &grid)
		return
	}

	grid.mesh, err = create_mesh(
		renderer,
		data.vertices,
		data.indices,
		COLOR_VERTEX_LAYOUT,
		data.bounds,
	)
	if err != .None {
		destroy_debug_grid(renderer, &grid)
	}

	return
}

destroy_debug_grid :: proc(renderer: ^Renderer, grid: ^Debug_Grid) -> (result: Error) {
	if err := destroy_mesh(renderer, &grid.mesh); err != .None {
		result = err
	}

	if err := destroy_material(renderer, &grid.material); err != .None {
		result = err
	}

	if err := destroy_pipeline(renderer, &grid.pipeline); err != .None {
		result = err
	}

	return
}
