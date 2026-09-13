package geometry

import emath "../core/math"
import "core:math"
import "core:mem"

Sphere_Mesh :: struct {
	vertices:  []Vertex,
	indices:   []u32,
	bounds:    emath.Bounding_Sphere,
	allocator: mem.Allocator,
}

Sphere_Error :: enum {
	None,
	Invalid_Resolution,
	Invalid_Radius,
	Allocation_Failed,
}

// Seam vertices share positions but carry U=0 and U=1. Each pole triangle
// has its own pole vertex so its U stays within that longitude slice.
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

	ring_vertices := (u64(segments) + 1) * u64(stacks - 1)
	vertex_count := ring_vertices + 2 * u64(segments)
	if vertex_count > u64(max(u32)) || vertex_count > u64(max(int) / size_of(Vertex)) {
		return {}, .Invalid_Resolution
	}

	index_count := u64(segments) * u64(stacks - 1) * 6
	if index_count > u64(max(int) / size_of(u32)) {
		return {}, .Invalid_Resolution
	}

	vertices, vertex_error := make([]Vertex, int(vertex_count), allocator)
	if vertex_error != .None {
		return {}, .Allocation_Failed
	}

	indices, index_error := make([]u32, int(index_count), allocator)
	if index_error != .None {
		delete(vertices, allocator)
		return {}, .Allocation_Failed
	}

	south_pole := segments + int(ring_vertices)
	for segment in 0 ..< segments {
		u := (f32(segment) + 0.5) / f32(segments)
		vertices[segment] = {{0, radius, 0}, {0, 1, 0}, {u, 0}}
		vertices[south_pole + segment] = {{0, -radius, 0}, {0, -1, 0}, {u, 1}}
	}

	ring_stride := segments + 1

	for stack in 1 ..< stacks {
		v := f32(stack) / f32(stacks)
		theta := f32(math.PI) * v
		y := math.cos(theta)
		ring_radius := math.sin(theta)

		for segment in 0 ..< segments {
			u := f32(segment) / f32(segments)
			phi := f32(2 * math.PI) * (u - 0.5)
			normal := [3]f32{ring_radius * math.cos(phi), y, ring_radius * math.sin(phi)}
			index := segments + (stack - 1) * ring_stride + segment
			vertices[index] = {
				position = normal * radius,
				normal   = normal,
				uv       = {u, v},
			}
		}

		first := segments + (stack - 1) * ring_stride
		vertices[first + segments] = vertices[first]
		vertices[first + segments].uv.x = 1
	}

	cursor := 0

	for segment in 0 ..< segments {
		next := segment + 1
		indices[cursor + 0] = u32(segment)
		indices[cursor + 1] = u32(segments + next)
		indices[cursor + 2] = u32(segments + segment)
		cursor += 3
	}

	for ring in 0 ..< stacks - 2 {
		for segment in 0 ..< segments {
			next := segment + 1
			upper := u32(segments + ring * ring_stride + segment)
			upper_next := u32(segments + ring * ring_stride + next)
			lower := upper + u32(ring_stride)
			lower_next := upper_next + u32(ring_stride)
			indices[cursor + 0] = upper
			indices[cursor + 1] = upper_next
			indices[cursor + 2] = lower
			indices[cursor + 3] = upper_next
			indices[cursor + 4] = lower_next
			indices[cursor + 5] = lower
			cursor += 6
		}
	}

	last_ring := segments + (stacks - 2) * ring_stride

	for segment in 0 ..< segments {
		next := segment + 1
		indices[cursor + 0] = u32(south_pole + segment)
		indices[cursor + 1] = u32(last_ring + segment)
		indices[cursor + 2] = u32(last_ring + next)
		cursor += 3
	}

	assert(cursor == len(indices))

	return Sphere_Mesh {
			vertices = vertices,
			indices = indices,
			bounds = {radius = radius},
			allocator = allocator,
		},
		.None
}

destroy_sphere :: proc(mesh: ^Sphere_Mesh) {
	delete(mesh.vertices, mesh.allocator)
	delete(mesh.indices, mesh.allocator)
	mesh^ = {}
}
