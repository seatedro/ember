package renderer

import "../camera"
import emath "../core/math"
import "core:math"
import "core:testing"

@(test)
test_draw_order_and_camera_changes :: proc(t: ^testing.T) {
	list := create_draw_list()
	defer destroy_draw_list(&list)
	for z, i in ([5]f32{-1, -10, -3, -3, 0}) {
		item := Draw_Item {
			transform = emath.translation({0, 0, z}),
			order     = .Transparent,
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
	testing.expect(t, add_draw(&list, {transform = emath.translation({0, 0, 1})}) == .None)
	testing.expect(t, list.items[0].sequence == 0)
}

@(test)
test_draw_list_rejects_invalid_sort_values :: proc(t: ^testing.T) {
	list := create_draw_list()
	defer destroy_draw_list(&list)
	testing.expect(t, add_draw(&list, {order = cast(Draw_Order)99}) == .Invalid_Draw)
	testing.expect(
		t,
		add_draw(
			&list,
			{transform = emath.translation({(transmute(f32)u32(0x7f800000)), 0, 0})},
		) ==
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
			transform = emath.translation({f32(i), 0, -f32(i)}),
			order     = .Transparent if i >= 3 else .Opaque,
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

@(test)
test_far_items_draw_relative_to_the_camera :: proc(t: ^testing.T) {
	far := emath.Vec3d{4.5e12, -2.25e12, 1.5e12}
	list := create_draw_list()
	defer destroy_draw_list(&list)
	testing.expect(
		t,
		add_draw(&list, {transform = emath.translation({1.25, 0.5, 0}), origin = far}) == .None,
	)
	testing.expect(
		t,
		add_draw(
			&list,
			{transform = emath.translation({1.25, 0.5, -2}), origin = far, order = .Transparent},
		) ==
		.None,
	)

	view := camera.Camera {
		position    = far + {4.75, 0.5, 3},
		orientation = 1,
	}
	testing.expect(t, sort_draw_list(&list, view) == .None)
	expected := [2]emath.Vec3{{-3.5, 0, -3}, {-3.5, 0, -5}}
	for entry, i in list.items {
		moved := emath.Vec3{entry.transform[0, 3], entry.transform[1, 3], entry.transform[2, 3]}
		testing.expect_value(t, moved, expected[i])
		testing.expect_value(t, entry.depth, expected[i].z)
	}
}

@(test)
test_far_lights_and_shadows_follow_the_view_origin :: proc(t: ^testing.T) {
	far := emath.Vec3d{4.5e12, 0, 0}
	lights := [1]Point_Light {
		{position = {0.5, 2, 0}, origin = far, color = {1, 1, 1}, intensity = 1, range = 10},
	}
	shadow := Shadow_Map {
		view_projection = emath.identity(),
		origin          = far + {-1, 0, 0},
		ready           = true,
	}
	sun := [1]Directional_Light{{direction = {0, 1, 0}, color = {1, 1, 1}, intensity = 1}}
	data, err := pack_lighting(
		{
			point_lights = lights[:],
			directional_lights = sun[:],
			shadow = &shadow,
			shadow_settings = {enabled = true},
		},
		far + {2.5, 1, 0},
	)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, data.point_lights[0].position_range, [4]f32{-2, 1, 0, 10})

	surface_from_camera := emath.Vec4{-2.5, -1, 0, 1}
	from_shadow_origin := data.shadow_matrix * surface_from_camera
	testing.expect_value(t, from_shadow_origin, emath.Vec4{1, 0, 0, 1})
}
