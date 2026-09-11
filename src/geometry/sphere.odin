package geometry

import "core:math"
import "core:mem"

Sphere_Mesh :: struct {
	vertices:  []Vertex,
	indices:   []u32,
	allocator: mem.Allocator,
}

Sphere_Error :: enum {
	None,
	Invalid_Resolution,
	Invalid_Radius,
	Allocation_Failed,
}

// Latitude/longitude sphere with one vertex at each pole and no duplicated
// longitude seam. Triangles wind counterclockwise when viewed from outside.
create_sphere :: proc(
	segments := 48,
	stacks := 24,
	radius: f32 = 1,
	allocator := context.allocator,
) -> (
	Sphere_Mesh,
	Sphere_Error,
) {
	if !(radius > 0) || math.is_inf(radius) {
		return {}, .Invalid_Radius
	}
	if segments < 3 || stacks < 2 || u64(segments) > u64(max(u32)) || u64(stacks) > u64(max(u32)) {
		return {}, .Invalid_Resolution
	}

	ring_vertices := u64(segments) * u64(stacks - 1)
	if ring_vertices > u64(max(u32)) - 2 || ring_vertices + 2 > u64(max(int) / size_of(Vertex)) {
		return {}, .Invalid_Resolution
	}
	index_count := ring_vertices * 6
	if index_count > u64(max(int) / size_of(u32)) {
		return {}, .Invalid_Resolution
	}

	vertices, vertex_error := make([]Vertex, int(ring_vertices + 2), allocator)
	if vertex_error != .None {
		return {}, .Allocation_Failed
	}
	indices, index_error := make([]u32, int(index_count), allocator)
	if index_error != .None {
		delete(vertices, allocator)
		return {}, .Allocation_Failed
	}

	vertices[0] = {{0, radius, 0}, {0, 1, 0}}
	vertices[len(vertices) - 1] = {{0, -radius, 0}, {0, -1, 0}}

	for stack in 1 ..< stacks {
		theta := f32(math.PI) * f32(stack) / f32(stacks)
		y := math.cos(theta)
		ring_radius := math.sin(theta)
		for segment in 0 ..< segments {
			phi := f32(2 * math.PI) * f32(segment) / f32(segments)
			normal := [3]f32{ring_radius * math.cos(phi), y, ring_radius * math.sin(phi)}
			index := 1 + (stack - 1) * segments + segment
			vertices[index] = {
				position = normal * radius,
				normal   = normal,
			}
		}
	}

	cursor := 0
	for segment in 0 ..< segments {
		next := (segment + 1) % segments
		indices[cursor + 0] = 0
		indices[cursor + 1] = u32(1 + next)
		indices[cursor + 2] = u32(1 + segment)
		cursor += 3
	}

	for ring in 0 ..< stacks - 2 {
		for segment in 0 ..< segments {
			next := (segment + 1) % segments
			upper := u32(1 + ring * segments + segment)
			upper_next := u32(1 + ring * segments + next)
			lower := upper + u32(segments)
			lower_next := upper_next + u32(segments)
			indices[cursor + 0] = upper
			indices[cursor + 1] = upper_next
			indices[cursor + 2] = lower
			indices[cursor + 3] = upper_next
			indices[cursor + 4] = lower_next
			indices[cursor + 5] = lower
			cursor += 6
		}
	}

	last_ring := 1 + (stacks - 2) * segments
	for segment in 0 ..< segments {
		next := (segment + 1) % segments
		indices[cursor + 0] = u32(len(vertices) - 1)
		indices[cursor + 1] = u32(last_ring + segment)
		indices[cursor + 2] = u32(last_ring + next)
		cursor += 3
	}
	assert(cursor == len(indices))

	return Sphere_Mesh{vertices = vertices, indices = indices, allocator = allocator}, .None
}

destroy_sphere :: proc(mesh: ^Sphere_Mesh) {
	delete(mesh.vertices, mesh.allocator)
	delete(mesh.indices, mesh.allocator)
	mesh^ = {}
}
