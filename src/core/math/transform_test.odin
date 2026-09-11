package ember_math

import "core:math"
import "core:testing"

@(test)
test_transform_identity_and_order :: proc(t: ^testing.T) {
	pose := Transform {
		orientation = 1,
		scale       = {1, 1, 1},
	}
	testing.expect_value(t, transform_matrix(pose), identity())
	testing.expect_value(t, normal_matrix(pose), identity())
	pose = {
		position    = {4, -3, 2},
		orientation = quaternion_angle_axis(math.PI / 2, {0, 0, 1}),
		scale       = {2, 3, 4},
	}
	point := transform_matrix(pose) * Vec4{1, 2, 3, 1}
	// (1,2,3) -> scale (2,6,12) -> rotate (-6,2,12) -> translate.
	expect_vec3_approximately_equal(t, Vec3(point.xyz), {-2, -1, 14})
	expect_f32_approximately_equal(t, point.w, 1)
}

@(test)
test_transform_normals_stay_perpendicular :: proc(t: ^testing.T) {
	pose := Transform {
		position    = {4, -3, 2},
		orientation = quaternion_angle_axis(.7, normalize({1, 2, 3})),
		scale       = {2, 3, 4},
	}
	model := transform_matrix(pose)
	normals := normal_matrix(pose)
	tangent_a := model * Vec4{1, -1, 0, 0}
	tangent_b := model * Vec4{0, 1, -1, 0}
	normal := normals * Vec4{1, 1, 1, 0}
	expect_f32_approximately_equal(t, dot(Vec3(tangent_a.xyz), Vec3(normal.xyz)), 0)
	expect_f32_approximately_equal(t, dot(Vec3(tangent_b.xyz), Vec3(normal.xyz)), 0)
	// This is precisely the case an ordinary model matrix gets wrong.
	wrong_normal := model * Vec4{1, 1, 1, 0}
	testing.expect(t, abs(dot(Vec3(tangent_a.xyz), Vec3(wrong_normal.xyz))) > 1)
	pose.position = {-20, 8, 9}
	testing.expect_value(t, normal_matrix(pose), normals)
}
