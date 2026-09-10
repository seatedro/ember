package ember_math

import stdmath "core:math"
import "core:testing"

@(test)
test_matrix_storage_and_composition :: proc(t: ^testing.T) {
	move := translation({2, 3, 4})
	packed := transmute([16]f32)move
	expect_f32_approximately_equal(t, packed[12], 2)
	expect_f32_approximately_equal(t, packed[13], 3)
	expect_f32_approximately_equal(t, packed[14], 4)

	point := move * Vec4{1, 0, 0, 1}
	direction := move * Vec4{1, 0, 0, 0}
	testing.expect_value(t, point, Vec4{3, 3, 4, 1})
	testing.expect_value(t, direction, Vec4{1, 0, 0, 0})

	rotated := rotation_y(f32(stdmath.PI / 2)) * Vec4{1, 0, 0, 1}
	expect_f32_approximately_equal(t, rotated[0], 0)
	expect_f32_approximately_equal(t, rotated[2], -1)
	combined := move * rotation_y(f32(stdmath.PI / 2)) * Vec4{1, 0, 0, 1}
	expect_f32_approximately_equal(t, combined[0], 2)
	expect_f32_approximately_equal(t, combined[2], 3)
}

@(test)
test_view_camera_axes :: proc(t: ^testing.T) {
	eye := Vec3{2, 1, 3}
	view := look_at(eye, {0, 0, 0}, {0, 1, 0})
	camera_origin := view * Vec4{eye[0], eye[1], eye[2], 1}
	for i in 0 ..< 3 {
		expect_f32_approximately_equal(t, camera_origin[i], 0)
	}
	center := view * Vec4{0, 0, 0, 1}
	expect_f32_approximately_equal(t, center[0], 0)
	expect_f32_approximately_equal(t, center[1], 0)
	expect_f32_approximately_equal(t, center[2], -length(eye))
}

@(test)
test_projection_depth_and_fov :: proc(t: ^testing.T) {
	fov := f32(stdmath.PI / 3)
	projection := perspective(fov, 2, 0.1, 100)
	near := projection * Vec4{0, 0, -0.1, 1}
	far := projection * Vec4{0, 0, -100, 1}
	expect_f32_approximately_equal(t, near[2] / near[3], -1)
	expect_f32_approximately_equal(t, far[2] / far[3], 1)

	top := projection * Vec4{0, 2 * stdmath.tan(fov / 2), -2, 1}
	right := projection * Vec4{4 * stdmath.tan(fov / 2), 0, -2, 1}
	expect_f32_approximately_equal(t, top[1] / top[3], 1)
	expect_f32_approximately_equal(t, right[0] / right[3], 1)
	testing.expect(t, near[3] > 0 && far[3] > 0)
}
