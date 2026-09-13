package renderer

import emath "../core/math"
import "../rhi"
import "core:math"
import "core:mem"

Vertex_Layout :: rhi.Vertex_Layout

Mesh :: struct {
	vertices:    rhi.Buffer_Handle,
	indices:     rhi.Buffer_Handle,
	index_count: u32,
	layout:      Vertex_Layout,
	bounds:      emath.Bounding_Sphere,
}

create_mesh :: proc(
	renderer: ^Renderer,
	vertices: []$Vertex,
	indices: []u32,
	layout: Vertex_Layout,
	bounds: emath.Bounding_Sphere,
) -> (
	mesh: Mesh,
	err: Error,
) {
	if !(bounds.radius >= 0) || math.is_inf(bounds.radius) {
		return {}, .Invalid_Draw
	}

	for value in bounds.center {
		if math.is_nan(value) || math.is_inf(value) {
			return {}, .Invalid_Draw
		}
	}

	if u64(layout.stride) != u64(size_of(Vertex)) {
		return {}, .Invalid_Vertex_Layout
	}

	if err = rhi.validate_vertex_layout(layout); err != .None {
		return
	}

	device := renderer.device
	if len(vertices) == 0 ||
	   size_of(Vertex) == 0 ||
	   len(indices) == 0 ||
	   u64(len(indices)) > u64(max(i32)) {
		return {}, .Invalid_Size
	}

	for index in indices {
		if u64(index) >= u64(len(vertices)) {
			return {}, .Invalid_Draw
		}
	}

	vertex_bytes := mem.slice_to_bytes(vertices)
	mesh.vertices, err = rhi.create_buffer(
		device,
		{size = u64(len(vertex_bytes)), usage = {.Vertex}, label = "mesh vertices"},
		vertex_bytes,
	)
	if err != .None {
		return
	}

	index_bytes := mem.slice_to_bytes(indices)
	mesh.indices, err = rhi.create_buffer(
		device,
		{size = u64(len(index_bytes)), usage = {.Index}, label = "mesh indices"},
		index_bytes,
	)
	if err != .None {
		// If cleanup fails, return the remaining handle so the caller can release it.
		release_mesh(device, &mesh)
		return
	}

	mesh.index_count = u32(len(indices))
	mesh.layout = layout
	mesh.bounds = bounds

	return
}

@(private)
bind_mesh :: proc(device: ^rhi.Device, mesh: ^Mesh) -> Error {
	if err := rhi.bind_vertex_buffer(device, mesh.vertices); err != .None {
		return err
	}

	return rhi.bind_index_buffer(device, mesh.indices, .U32)
}

destroy_mesh :: proc(renderer: ^Renderer, mesh: ^Mesh) -> Error {
	return release_mesh(renderer.device, mesh)
}

@(private)
release_mesh :: proc(device: ^rhi.Device, mesh: ^Mesh) -> (result: rhi.Error) {
	for handle in ([2]^rhi.Buffer_Handle{&mesh.indices, &mesh.vertices}) {
		if handle.generation == 0 {
			continue
		}

		err := rhi.destroy_buffer(device, handle^)
		if err == .None {
			handle^ = {}
		} else if result == .None {
			result = err
		}
	}

	if result == .None {
		mesh^ = {}
	}

	return
}
