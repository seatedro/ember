package renderer

import emath "../core/math"
import "core:math"
import "core:testing"

@(test)
test_draw_order_and_camera_changes :: proc(t: ^testing.T) {
	list := create_draw_list()
	defer destroy_draw_list(&list)
	for z, i in ([5]f32{-1, -10, -3, -3, 0}) {
		item := Draw_Item {
			transform = {position = {0, 0, z}},
			order = .Transparent,
		}
		if i == 1 || i == 4 {
			item.order = .Opaque
		}
		testing.expect(t, add_draw(&list, item) == .None)
	}
	testing.expect(t, sort_draw_list(&list, {orientation = 1}) == .None)
	for expected, i in ([5]int{1, 4, 2, 3, 0}) {
		testing.expect(t, list.items[i].sequence == expected)
	}
	testing.expect(
		t,
		sort_draw_list(
			&list,
			{orientation = emath.quaternion_angle_axis(f32(math.PI), {0, 1, 0})},
		) ==
		.None,
	)
	for expected, i in ([5]int{1, 4, 0, 2, 3}) {
		testing.expect(t, list.items[i].sequence == expected)
	}
	testing.expect(t, sort_draw_list(&list, {orientation = 1}) == .None)
	for expected, i in ([5]int{1, 4, 2, 3, 0}) {
		testing.expect(t, list.items[i].sequence == expected)
	}
	capacity := cap(list.items)
	clear_draw_list(&list)
	testing.expect(t, len(list.items) == 0 && cap(list.items) == capacity)
	testing.expect(t, add_draw(&list, {transform = {position = {0, 0, 1}}}) == .None)
	testing.expect(t, list.items[0].sequence == 0)
}

@(test)
test_draw_list_rejects_invalid_sort_values :: proc(t: ^testing.T) {
	list := create_draw_list()
	defer destroy_draw_list(&list)
	testing.expect(t, add_draw(&list, {order = cast(Draw_Order)99}) == .Invalid_Draw)
	testing.expect(
		t,
		add_draw(&list, {transform = {position = {(transmute(f32)u32(0x7f800000)), 0, 0}}}) ==
		.Invalid_Draw,
	)
	testing.expect(t, len(list.items) == 0)
}

@(test)
test_batches_preserve_materials_and_transparency :: proc(t: ^testing.T) {
	list := create_draw_list()
	defer destroy_draw_list(&list)
	for i in 0 ..< 5 {
		item := Draw_Item {
			transform = {position = {f32(i), 0, -f32(i)}, orientation = 1, scale = {1, 1, 1}},
			order = .Transparent if i >= 3 else .Opaque,
		}
		if i == 1 {
			item.material.textures[0] = {
				index      = 1,
				generation = 1,
			}
		}

		testing.expect(t, add_draw(&list, item) == .None)
	}

	testing.expect(t, sort_draw_list(&list, {orientation = 1}) == .None)
	for entry in list.items {
		append(&list.visible, entry)
	}

	testing.expect(t, build_draw_batches(&list, true) == .None)
	testing.expect_value(t, len(list.batches), 4)
	for count, i in ([4]int{2, 1, 1, 1}) {
		testing.expect_value(t, list.batches[i].count, count)
	}

	for x, i in ([5]f32{0, 2, 1, 4, 3}) {
		testing.expect_value(t, list.instances[i].rows[0][3], x)
	}

	testing.expect(t, build_draw_batches(&list, false) == .None)
	testing.expect_value(t, len(list.batches), 5)
	for x, i in ([5]f32{0, 1, 2, 4, 3}) {
		testing.expect_value(t, list.instances[i].rows[0][3], x)
		testing.expect_value(t, list.batches[i].first, i)
		testing.expect_value(t, list.batches[i].count, 1)
	}
}
