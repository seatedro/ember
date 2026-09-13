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
	items: [dynamic]Draw_Entry,
}

@(private)
Draw_Entry :: struct {
	item:     Draw_Item,
	depth:    f32,
	sequence: int,
}

create_draw_list :: proc(allocator := context.allocator) -> Draw_List {
	return {items = make([dynamic]Draw_Entry, allocator)}
}

clear_draw_list :: proc(list: ^Draw_List) {
	clear(&list.items)
}

destroy_draw_list :: proc(list: ^Draw_List) {
	delete(list.items)
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
) -> Error {
	if err := rhi.validate_device(renderer.device); err != .None {
		return err
	}

	if !renderer.device.pass_active {
		return .Invalid_Pass
	}

	if err := sort_draw_list(list, view); err != .None {
		return err
	}

	if err := set_view(renderer, view, projection, lighting); err != .None {
		return err
	}

	for &entry in list.items {
		item := &entry.item
		if err := draw_mesh(renderer, &item.pipeline, &item.mesh, &item.material, item.transform);
		   err != .None {
			return err
		}
	}

	return .None
}
