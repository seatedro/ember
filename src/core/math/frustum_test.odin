package ember_math

import "core:math"
import "core:testing"

@(test)
test_frustum_edges_and_camera_pose :: proc(t: ^testing.T) {
	projection := perspective(math.PI / 2, 1, 1, 10)
	radius: f32 = 0.25
	edge := 5 + math.sqrt(f32(2)) * radius
	tangencies := [6]Vec3 {
		{-edge, 0, -5},
		{edge, 0, -5},
		{0, -edge, -5},
		{0, edge, -5},
		{0, 0, -1 + radius},
		{0, 0, -10 - radius},
	}
	outward := [6]Vec3{{-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, 1}, {0, 0, -1}}
	for pose in ([2]Transform {
			{orientation = 1, scale = {1, 1, 1}},
			{
				position = {7, -2, 4},
				orientation = quaternion_angle_axis(math.PI / 2, {0, 1, 0}),
				scale = {1, 1, 1},
			},
		}) {
		forward := quaternion_rotate(pose.orientation, {0, 0, -1})
		view := look_at(pose.position, pose.position + forward, {0, 1, 0})
		frustum := frustum_from_matrix(projection * view)
		inside := transform_sphere({center = {0, 0, -5}, radius = radius}, pose)
		testing.expect(t, sphere_in_frustum(frustum, inside))
		behind := transform_sphere({center = {0, 0, 2}, radius = radius}, pose)
		testing.expect(t, !sphere_in_frustum(frustum, behind))

		for center, i in tangencies {
			tangent := transform_sphere({center = center, radius = radius}, pose)
			outside := transform_sphere(
				{center = center + outward[i] * 0.05, radius = radius},
				pose,
			)
			testing.expect(t, sphere_in_frustum(frustum, tangent))
			testing.expect(t, !sphere_in_frustum(frustum, outside))
		}
	}
}

@(test)
test_sphere_bounds_under_nonuniform_scale :: proc(t: ^testing.T) {
	local := Bounding_Sphere {
		center = {1, 2, 3},
		radius = 2,
	}
	pose := Transform {
		position    = {4, -3, 2},
		orientation = quaternion_angle_axis(math.PI / 2, {0, 0, 1}),
		scale       = {2, 3, 4},
	}
	world := transform_sphere(local, pose)
	expect_vec3_approximately_equal(t, world.center, {-2, -1, 14})
	expect_f32_approximately_equal(t, world.radius, 8)
	model := transform_matrix(pose)
	for direction in ([6]Vec3 {
			{-1, 0, 0},
			{1, 0, 0},
			{0, -1, 0},
			{0, 1, 0},
			{0, 0, -1},
			{0, 0, 1},
		}) {
		point := local.center + direction * local.radius
		transformed := model * Vec4{point.x, point.y, point.z, 1}
		testing.expect(t, length(Vec3(transformed.xyz) - world.center) <= world.radius + 0.00001)
	}
}
