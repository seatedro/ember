package ember_math

import stdmath "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
test_quaternion_rotation_and_composition :: proc(t: ^testing.T) {
	v := Vec3{1, 2, 3}
	expect_vec3_approximately_equal(t, quat_rotate(1, v), v)
	yaw := quat_axis_angle(f32(stdmath.PI / 2), {0, 1, 0})
	expect_vec3_approximately_equal(t, quat_rotate(yaw, {0, 0, -1}), {-1, 0, 0})
	pitch := quat_axis_angle(f32(stdmath.PI / 3), {1, 0, 0})
	composed := quat_normalize(yaw * pitch)
	expect_vec3_approximately_equal(t, quat_rotate(conj(composed), quat_rotate(composed, v)), v)
	rotated := rotation_y(f32(stdmath.PI / 2)) * rotation_x(f32(stdmath.PI / 3)) * Vec4{1, 2, 3, 0}
	expect_vec3_approximately_equal(t, quat_rotate(composed, v), Vec3(rotated.xyz))
}

@(test)
test_quaternion_arbitrary_axis_matches_linalg :: proc(t: ^testing.T) {
	axis := Vec3{2, -3, 4}
	v := Vec3{-1, 5, 2}
	q := quat_axis_angle(1.2, axis)
	oracle := linalg.quaternion_angle_axis_f32(1.2, ([3]f32)(axis))
	expect_vec3_approximately_equal(
		t,
		quat_rotate(q, v),
		Vec3(linalg.quaternion_mul_vector3(oracle, ([3]f32)(v))),
	)
	expect_f32_approximately_equal(t, length(quat_rotate(q, v)), length(v))
	expect_vec3_approximately_equal(t, quat_rotate(-q, v), quat_rotate(q, v))
	expect_vec3_approximately_equal(t, quat_rotate(quat_normalize(3 * q), v), quat_rotate(q, v))
}
