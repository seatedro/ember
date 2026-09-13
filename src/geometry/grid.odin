package geometry

import emath "../core/math"
import "core:math"
import "core:mem"

Grid_Mesh :: struct {
	vertices:  []Color_Vertex,
	indices:   []u32,
	bounds:    emath.Bounding_Sphere,
	allocator: mem.Allocator,
}

Grid_Error :: enum {
	None,
	Invalid_Size,
	Allocation_Failed,
}

create_grid :: proc(
	extent := 10,
	spacing: f32 = 1,
	major_every := 5,
	minor: [3]f32 = {0.22, 0.23, 0.25},
	major: [3]f32 = {0.32, 0.33, 0.35},
	x_axis: [3]f32 = {0.6, 0.22, 0.2},
	z_axis: [3]f32 = {0.2, 0.35, 0.65},
	allocator := context.allocator,
) -> (
	Grid_Mesh,
	Grid_Error,
) {
	if extent <= 0 ||
	   extent > (int(max(u32)) - 4) / 8 ||
	   extent > (max(int) / size_of(Color_Vertex) - 4) / 8 ||
	   major_every <= 0 ||
	   !(spacing > 0) ||
	   math.is_inf(spacing * f32(extent) * math.sqrt(f32(2))) {
		return {}, .Invalid_Size
	}

	count := (2 * extent + 1) * 4
	vertices, ve := make([]Color_Vertex, count, allocator)
	if ve != .None {
		return {}, .Allocation_Failed
	}

	indices, ie := make([]u32, count, allocator)
	if ie != .None {
		delete(vertices, allocator)
		return {}, .Allocation_Failed
	}

	half_size := f32(extent) * spacing
	for coordinate in -extent ..= extent {
		i := (coordinate + extent) * 4
		p := f32(coordinate) * spacing
		color := major if coordinate % major_every == 0 else minor
		x_color := x_axis if coordinate == 0 else color
		z_color := z_axis if coordinate == 0 else color
		vertices[i + 0] = {{-half_size, 0, p}, x_color}
		vertices[i + 1] = {{half_size, 0, p}, x_color}
		vertices[i + 2] = {{p, 0, -half_size}, z_color}
		vertices[i + 3] = {{p, 0, half_size}, z_color}
	}

	for &index, i in indices {
		index = u32(i)
	}

	return {
			vertices = vertices,
			indices = indices,
			bounds = {radius = half_size * math.sqrt(f32(2))},
			allocator = allocator,
		},
		.None
}

destroy_grid :: proc(mesh: ^Grid_Mesh) {
	delete(mesh.vertices, mesh.allocator)
	delete(mesh.indices, mesh.allocator)
	mesh^ = {}
}
