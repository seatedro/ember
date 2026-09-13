package renderer

import "../camera"
import emath "../core/math"
import "../rhi"
import "core:math"
import "core:slice"

Draw_Order :: enum {
	Opaque,
	Transparent,
}

Draw_Item :: struct {
	pipeline:  Pipeline,
	mesh:      Mesh,
	material:  Material,
	transform: emath.Transform,
	order:     Draw_Order,
}

Draw_List :: struct {
	items:         [dynamic]Draw_Entry,
	visible:       [dynamic]Draw_Entry,
	instances:     [dynamic]Instance_Data,
	batches:       [dynamic]Draw_Batch,
	batch_indices: map[Batch_Key]int,
	stats:         Draw_Stats,
}

Draw_Stats :: struct {
	submitted, visible, draw_calls: int,
}

@(private)
Draw_Batch :: struct {
	item:         Draw_Item,
	first, count: int,
}

@(private)
Batch_Key :: struct {
	pipeline:          rhi.Pipeline_Handle,
	vertices, indices: rhi.Buffer_Handle,
	index_count:       u32,
	material:          Material,
}

@(private)
Draw_Entry :: struct {
	item:     Draw_Item,
	depth:    f32,
	sequence: int,
	batch:    int,
}

create_draw_list :: proc(allocator := context.allocator) -> Draw_List {
	return {
		items = make([dynamic]Draw_Entry, allocator),
		visible = make([dynamic]Draw_Entry, allocator),
		instances = make([dynamic]Instance_Data, allocator),
		batches = make([dynamic]Draw_Batch, allocator),
		batch_indices = make(map[Batch_Key]int, allocator),
	}
}

clear_draw_list :: proc(list: ^Draw_List) {
	clear(&list.items)
	clear(&list.visible)
	clear(&list.instances)
	clear(&list.batches)
	clear(&list.batch_indices)
	list.stats = {}
}

destroy_draw_list :: proc(list: ^Draw_List) {
	delete(list.items)
	delete(list.visible)
	delete(list.instances)
	delete(list.batches)
	delete(list.batch_indices)
	list^ = {}
}

// Entries borrow GPU resources; keep them alive until the list is drawn.
add_draw :: proc(list: ^Draw_List, item: Draw_Item) -> Error {
	if item.order < .Opaque || item.order > .Transparent {
		return .Invalid_Draw
	}

	for value in item.transform.position {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Draw
		}
	}

	if _, err := append(&list.items, Draw_Entry{item = item, sequence = len(list.items)});
	   err != .None {
		return .Allocation_Failed
	}

	return .None
}

sort_draw_list :: proc(list: ^Draw_List, view: camera.Camera) -> Error {
	view_matrix := camera.view_matrix(view)
	for &entry in list.items {
		p := entry.item.transform.position
		entry.depth = (view_matrix * emath.Vec4{p.x, p.y, p.z, 1}).z
		if math.is_nan(entry.depth) || math.is_inf(entry.depth) {
			return .Invalid_Draw
		}
	}

	slice.sort_by(list.items[:], proc(a, b: Draw_Entry) -> bool {
		if a.item.order != b.item.order {
			return a.item.order < b.item.order
		}

		if a.item.order == .Transparent && a.depth != b.depth {
			return a.depth < b.depth
		}

		return a.sequence < b.sequence
	})
	return .None
}

draw_list :: proc(
	renderer: ^Renderer,
	list: ^Draw_List,
	view: camera.Camera,
	projection: emath.Mat4,
	lighting: Lighting = {},
	batching := true,
) -> Error {
	list.stats = {
		submitted = len(list.items),
	}
	if err := rhi.validate_device(renderer.device); err != .None {
		return err
	}

	if !renderer.device.pass_active {
		return .Invalid_Pass
	}

	if err := sort_draw_list(list, view); err != .None {
		return err
	}

	clear(&list.visible)
	frustum := emath.frustum_from_matrix(projection * camera.view_matrix(view))
	for &entry in list.items {
		item := &entry.item
		bounds := emath.transform_sphere(item.mesh.bounds, item.transform)
		if !emath.sphere_in_frustum(frustum, bounds) {
			continue
		}

		if err := validate_draw(renderer.device, &item.pipeline, &item.mesh, &item.material);
		   err != .None {
			return err
		}

		if _, err := append(&list.visible, entry); err != .None {
			return .Allocation_Failed
		}
	}

	list.stats.visible = len(list.visible)
	if err := build_draw_batches(list, batching); err != .None {
		return err
	}

	if len(list.instances) == 0 {
		return .None
	}

	if err := set_view(renderer, view, projection, lighting); err != .None {
		return err
	}

	if err := upload_instances(renderer, list.instances[:]); err != .None {
		return err
	}

	for &batch in list.batches {
		item := &batch.item
		if err := draw_mesh_instances(
			renderer,
			&item.pipeline,
			&item.mesh,
			&item.material,
			renderer.instance_buffer,
			u64(batch.first) * size_of(Instance_Data),
			u32(batch.count),
		); err != .None {
			return err
		}

		list.stats.draw_calls += 1
	}

	return .None
}

@(private)
build_draw_batches :: proc(list: ^Draw_List, batching: bool) -> Error {
	clear(&list.batches)
	clear(&list.batch_indices)
	if u64(len(list.visible)) > u64(max(i32)) ||
	   len(list.visible) > max(int) / size_of(Instance_Data) {
		return .Invalid_Size
	}

	if err := resize(&list.instances, len(list.visible)); err != .None {
		return .Allocation_Failed
	}

	for &entry in list.visible {
		item := &entry.item
		key := Batch_Key {
			item.pipeline.handle,
			item.mesh.vertices,
			item.mesh.indices,
			item.mesh.index_count,
			item.material,
		}
		batch, found := list.batch_indices[key]
		group := batching && item.order == .Opaque
		if !group || !found {
			batch = len(list.batches)
			if _, err := append(&list.batches, Draw_Batch{item = item^}); err != .None {
				return .Allocation_Failed
			}

			if group && map_insert(&list.batch_indices, key, batch) == nil {
				return .Allocation_Failed
			}
		}

		entry.batch = batch
		list.batches[batch].count += 1
	}

	offset := 0
	for &batch in list.batches {
		batch.first = offset
		offset += batch.count
		batch.count = 0
	}

	for &entry in list.visible {
		batch := &list.batches[entry.batch]
		list.instances[batch.first + batch.count] = pack_instance(entry.item.transform)
		batch.count += 1
	}

	return .None
}
