package ember_math

import stdmath "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
test_quaternion_rotation_and_composition :: proc(t: ^testing.T) {
	v := Vec3{1, 2, 3}
	expect_vec3_approximately_equal(t, quaternion_rotate(1, v), v)
	yaw := quaternion_angle_axis(f32(stdmath.PI / 2), {0, 1, 0})
	expect_vec3_approximately_equal(t, quaternion_rotate(yaw, {0, 0, -1}), {-1, 0, 0})
	pitch := quaternion_angle_axis(f32(stdmath.PI / 3), {1, 0, 0})
	composed := quaternion_normalize(yaw * pitch)
	expect_vec3_approximately_equal(
		t,
		quaternion_rotate(conj(composed), quaternion_rotate(composed, v)),
		v,
	)
	rotated := rotation_y(f32(stdmath.PI / 2)) * rotation_x(f32(stdmath.PI / 3)) * Vec4{1, 2, 3, 0}
	expect_vec3_approximately_equal(t, quaternion_rotate(composed, v), Vec3(rotated.xyz))
}

@(test)
test_quaternion_arbitrary_axis_matches_linalg :: proc(t: ^testing.T) {
	axis := Vec3{2, -3, 4}
	v := Vec3{-1, 5, 2}
	q := quaternion_angle_axis(1.2, axis)
	oracle := linalg.quaternion_angle_axis_f32(1.2, ([3]f32)(axis))
	expect_vec3_approximately_equal(
		t,
		quaternion_rotate(q, v),
		Vec3(linalg.quaternion_mul_vector3(oracle, ([3]f32)(v))),
	)
	expect_f32_approximately_equal(t, length(quaternion_rotate(q, v)), length(v))
	expect_vec3_approximately_equal(t, quaternion_rotate(-q, v), quaternion_rotate(q, v))
	expect_vec3_approximately_equal(
		t,
		quaternion_rotate(quaternion_normalize(3 * q), v),
		quaternion_rotate(q, v),
	)
}
