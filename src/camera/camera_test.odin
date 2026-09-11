package camera

import emath "../core/math"
import "core:math"
import "core:testing"

expect_point :: proc(t: ^testing.T, actual, expected: emath.Vec4) {
	for i in 0 ..< 4 {
		testing.expectf(
			t,
			abs(actual[i] - expected[i]) < 0.0001,
			"component %d: %v != %v",
			i,
			actual[i],
			expected[i],
		)
	}
}

@(test)
test_view_inverts_camera_pose_with_roll :: proc(t: ^testing.T) {
	camera := Camera {
		position    = {3, -2, 5},
		orientation = emath.quaternion_angle_axis(
			0.6,
			{0, 1, 0},
		) * emath.quaternion_angle_axis(0.9, {0, 0, 1}),
	}
	local := emath.Vec3{2, 1, -4}
	world := camera.position + emath.quaternion_rotate(camera.orientation, local)
	expect_point(
		t,
		view_matrix(camera) * emath.Vec4{world.x, world.y, world.z, 1},
		{local.x, local.y, local.z, 1},
	)
	expect_point(
		t,
		view_matrix(camera) *
		emath.Vec4{camera.position.x, camera.position.y, camera.position.z, 1},
		{0, 0, 0, 1},
	)
	expect_point(t, view_matrix({orientation = 1}) * emath.Vec4{2, 3, 4, 1}, {2, 3, 4, 1})
}

@(test)
test_orbit_distance_center_and_projection :: proc(t: ^testing.T) {
	for yaw in ([4]f32{0, math.PI / 2, math.PI, -0.7}) {
		for pitch in ([3]f32{-1.48, 0, 1.48}) {
			orbit := Orbit {
				target   = {3, 2, -5},
				yaw      = yaw,
				pitch    = pitch,
				distance = 7,
			}
			camera := from_orbit(orbit)
			testing.expect(
				t,
				abs(emath.length(camera.position - orbit.target) - orbit.distance) < 0.0001,
			)
			center :=
				view_matrix(camera) * emath.Vec4{orbit.target.x, orbit.target.y, orbit.target.z, 1}
			expect_point(t, center, {0, 0, -orbit.distance, 1})
			for aspect in ([3]f32{0.5, 1, 2}) {
				clip := emath.perspective(1, aspect, 0.1, 100) * center
				testing.expect(t, abs(clip.x / clip.w) < 0.0001 && abs(clip.y / clip.w) < 0.0001)
			}
		}
	}
	yaw_camera := from_orbit({yaw = math.PI / 2, distance = 2})
	expect_point(
		t,
		emath.Vec4{yaw_camera.position.x, yaw_camera.position.y, yaw_camera.position.z, 1},
		{2, 0, 0, 1},
	)
}
