package camera

import emath "../core/math"

Orbit :: struct {
	target:   emath.Vec3,
	yaw:      f32,
	pitch:    f32,
	distance: f32,
}

from_orbit :: proc(orbit: Orbit) -> Camera {
	assert(orbit.distance > 0)
	yaw := emath.quaternion_angle_axis(orbit.yaw, {0, 1, 0})
	pitch := emath.quaternion_angle_axis(-orbit.pitch, {1, 0, 0})
	orientation := emath.quaternion_normalize(yaw * pitch)
	return Camera {
		position = orbit.target + emath.quaternion_rotate(orientation, {0, 0, orbit.distance}),
		orientation = orientation,
	}
}
