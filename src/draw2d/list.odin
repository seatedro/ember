package draw2d

import "../rhi"
import "core:math"
import "core:mem"

Error :: rhi.Error

Rect :: struct {
	position, size: [2]f32,
}

Vertex :: struct {
	position, uv:   [2]f32,
	color:          [4]f32,
	distance_range: f32,
}

Batch :: struct {
	texture:                  rhi.Texture_Handle,
	clip:                     Rect,
	first_index, index_count: u32,
}

List :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
	batches:  [dynamic]Batch,
	clips:    [dynamic]Rect,
	size:     [2]f32,
}

create_list :: proc(allocator := context.allocator) -> List {
	return {
		vertices = make([dynamic]Vertex, allocator),
		indices = make([dynamic]u32, allocator),
		batches = make([dynamic]Batch, allocator),
		clips = make([dynamic]Rect, allocator),
	}
}

reset :: proc(list: ^List, size: [2]f32) -> Error {
	clear(&list.vertices)
	clear(&list.indices)
	clear(&list.batches)
	clear(&list.clips)
	list.size = {}
	if !valid_rect({size = size}) || size.x <= 0 || size.y <= 0 {
		return .Invalid_Size
	}

	if _, err := append(&list.clips, Rect{size = size}); err != nil {
		return .Allocation_Failed
	}

	list.size = size
	return .None
}

push_clip :: proc(list: ^List, rect: Rect) -> Error {
	if len(list.clips) == 0 || !valid_rect(rect) {
		return .Invalid_Draw
	}

	clip := intersect(list.clips[len(list.clips) - 1], rect)
	if _, err := append(&list.clips, clip); err != nil {
		return .Allocation_Failed
	}

	return .None
}

pop_clip :: proc(list: ^List) -> Error {
	if len(list.clips) <= 1 {
		return .Invalid_Draw
	}

	pop(&list.clips)
	return .None
}

rectangle :: proc(list: ^List, rect: Rect, color: [4]f32) -> Error {
	return quad(list, rect, {}, color)
}

quad :: proc(
	list: ^List,
	rect: Rect,
	texture: rhi.Texture_Handle,
	color: [4]f32 = {1, 1, 1, 1},
	uv_min: [2]f32 = {0, 0},
	uv_max: [2]f32 = {1, 1},
) -> Error {
	return append_quad(list, rect, texture, color, uv_min, uv_max, 0)
}

@(private)
append_quad :: proc(
	list: ^List,
	rect: Rect,
	texture: rhi.Texture_Handle,
	color: [4]f32,
	uv_min, uv_max: [2]f32,
	distance_range: f32,
) -> Error {
	if len(list.clips) == 0 || !valid_rect(rect) || !finite(distance_range) || distance_range < 0 {
		return .Invalid_Draw
	}

	for value in color {
		if !finite(value) {
			return .Invalid_Draw
		}
	}

	for i in 0 ..< 2 {
		if !finite(uv_min[i]) || !finite(uv_max[i]) {
			return .Invalid_Draw
		}
	}

	clip := list.clips[len(list.clips) - 1]
	visible := intersect(clip, rect)
	if visible.size.x == 0 || visible.size.y == 0 {
		return .None
	}

	if len(list.indices) > int(max(i32)) - 6 || len(list.vertices) > int(max(u32)) - 4 {
		return .Invalid_Size
	}

	batch := Batch {
		texture     = texture,
		clip        = clip,
		first_index = u32(len(list.indices)),
	}
	merge :=
		len(list.batches) > 0 &&
		list.batches[len(list.batches) - 1].texture == texture &&
		list.batches[len(list.batches) - 1].clip == clip
	if ensure_capacity(&list.vertices, len(list.vertices) + 4) != nil ||
	   ensure_capacity(&list.indices, len(list.indices) + 6) != nil ||
	   (!merge && ensure_capacity(&list.batches, len(list.batches) + 1) != nil) {
		return .Allocation_Failed
	}

	p := rect.position
	q := p + rect.size
	base := u32(len(list.vertices))
	append(
		&list.vertices,
		Vertex{p, uv_min, color, distance_range},
		Vertex{{q.x, p.y}, {uv_max.x, uv_min.y}, color, distance_range},
		Vertex{q, uv_max, color, distance_range},
		Vertex{{p.x, q.y}, {uv_min.x, uv_max.y}, color, distance_range},
	)
	append(&list.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	if !merge {
		append(&list.batches, batch)
	}

	list.batches[len(list.batches) - 1].index_count += 6
	return .None
}

destroy_list :: proc(list: ^List) {
	delete(list.vertices)
	delete(list.indices)
	delete(list.batches)
	delete(list.clips)
	list^ = {}
}

@(private)
finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

@(private)
valid_rect :: proc(rect: Rect) -> bool {
	for i in 0 ..< 2 {
		if !finite(rect.position[i]) ||
		   !finite(rect.size[i]) ||
		   rect.size[i] < 0 ||
		   !finite(rect.position[i] + rect.size[i]) {
			return false
		}
	}

	return true
}

@(private)
intersect :: proc(a, b: Rect) -> Rect {
	p := [2]f32{max(a.position.x, b.position.x), max(a.position.y, b.position.y)}
	q := [2]f32 {
		min(a.position.x + a.size.x, b.position.x + b.size.x),
		min(a.position.y + a.size.y, b.position.y + b.size.y),
	}
	return {position = p, size = {max(q.x - p.x, 0), max(q.y - p.y, 0)}}
}

@(private)
ensure_capacity :: proc(array: ^[dynamic]$T, count: int) -> mem.Allocator_Error {
	if count <= cap(array^) {
		return nil
	}

	return reserve(array, max(count, min(cap(array^), max(int) / 2) * 2))
}

append_list :: proc(destination, source: ^List) -> Error {
	if destination == source ||
	   destination.size != source.size ||
	   len(destination.clips) != 1 ||
	   len(source.clips) != 1 {
		return .Invalid_Draw
	}

	if len(source.indices) > int(max(i32)) - len(destination.indices) ||
	   len(source.vertices) > int(max(u32)) - len(destination.vertices) {
		return .Invalid_Size
	}

	if ensure_capacity(&destination.vertices, len(destination.vertices) + len(source.vertices)) !=
		   nil ||
	   ensure_capacity(&destination.indices, len(destination.indices) + len(source.indices)) !=
		   nil ||
	   ensure_capacity(&destination.batches, len(destination.batches) + len(source.batches)) !=
		   nil {
		return .Allocation_Failed
	}

	vertex_offset := u32(len(destination.vertices))
	index_offset := u32(len(destination.indices))
	append(&destination.vertices, ..source.vertices[:])
	for index in source.indices {
		append(&destination.indices, index + vertex_offset)
	}

	for source_batch in source.batches {
		batch := source_batch
		batch.first_index += index_offset
		append(&destination.batches, batch)
	}

	return .None
}
