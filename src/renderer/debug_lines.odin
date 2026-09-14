package renderer

import emath "../core/math"
import "../geometry"
import "../rhi"
import "../shaders"
import "core:math"
import "core:mem"

Debug_Lines :: struct {
	mesh:      Mesh,
	pipeline:  Pipeline,
	material:  Material,
	vertices:  []geometry.Color_Vertex,
	count:     int,
	allocator: mem.Allocator,
}

create_debug_lines :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
	capacity: int,
	depth_test := true,
	allocator := context.allocator,
) -> (
	lines: Debug_Lines,
	err: Error,
) {
	if capacity <= 0 ||
	   capacity > min(int(max(i32)) / 2, max(int) / size_of(geometry.Color_Vertex) / 2) {
		return {}, .Invalid_Capacity
	}
	lines.allocator = allocator
	defer {
		if err != .None {
			destroy_debug_lines(renderer, &lines)
		}
	}
	allocation_error: mem.Allocator_Error
	lines.vertices, allocation_error = make([]geometry.Color_Vertex, capacity * 2, allocator)
	if allocation_error != .None {
		return lines, .Allocation_Failed
	}
	indices, index_error := make([]u32, capacity * 2, allocator)
	if index_error != .None {
		return lines, .Allocation_Failed
	}
	defer delete(indices, allocator)
	for &index, i in indices {
		index = u32(i)
	}
	program, shader_error := load_builtin_shader(library, .Grid)
	if shader_error != .None {
		return lines, .Backend_Failed
	}
	lines.pipeline, err = create_pipeline(
		renderer,
		program,
		{
			layout = COLOR_VERTEX_LAYOUT,
			primitive = .Lines,
			depth = {test_enabled = depth_test, write_enabled = false, compare = .Less_Equal},
		},
	)
	if err != .None {
		return
	}
	lines.material, err = create_material(renderer, program, Tint_Parameters{tint = {1, 1, 1, 1}})
	if err != .None {
		return
	}
	lines.mesh, err = create_mesh(renderer, lines.vertices, indices, COLOR_VERTEX_LAYOUT, {})
	return
}

clear_debug_lines :: proc(lines: ^Debug_Lines) {
	lines.count = 0
}

add_debug_line :: proc(lines: ^Debug_Lines, a, b: emath.Vec3, color: [3]f32) -> Error {
	if lines.count + 2 > len(lines.vertices) {
		return .Invalid_Size
	}
	for values in ([3][3]f32{cast([3]f32)a, cast([3]f32)b, color}) {
		for value in values {
			if math.is_nan(value) || math.is_inf(value) {
				return .Invalid_Draw
			}
		}
	}
	lines.vertices[lines.count] = {
		position = cast([3]f32)a,
		color    = color,
	}
	lines.vertices[lines.count + 1] = {
		position = cast([3]f32)b,
		color    = color,
	}
	lines.count += 2
	return .None
}

draw_debug_lines :: proc(renderer: ^Renderer, lines: ^Debug_Lines) -> Error {
	if lines.count == 0 {
		return .None
	}
	if err := rhi.update_buffer(
		renderer.device,
		lines.mesh.vertices,
		0,
		mem.slice_to_bytes(lines.vertices[:lines.count]),
	); err != .None {
		return err
	}
	lines.mesh.index_count = u32(lines.count)
	return draw_mesh(
		renderer,
		&lines.pipeline,
		&lines.mesh,
		&lines.material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

destroy_debug_lines :: proc(renderer: ^Renderer, lines: ^Debug_Lines) -> (result: Error) {
	if err := destroy_mesh(renderer, &lines.mesh); err != .None {
		result = err
	}
	if err := destroy_material(renderer, &lines.material); err != .None {
		result = err
	}
	if err := destroy_pipeline(renderer, &lines.pipeline); err != .None {
		result = err
	}
	delete(lines.vertices, lines.allocator)
	lines.vertices = nil
	lines.count = 0
	return
}
