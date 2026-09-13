package camera

import emath "../core/math"
import "core:math"

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

rotate_orbit :: proc(orbit: ^Orbit, radians: [2]f32, pitch_limit: f32) -> bool {
	if !(pitch_limit > 0 && pitch_limit < math.PI / 2) ||
	   math.is_nan(radians.x) ||
	   math.is_nan(radians.y) ||
	   math.is_inf(radians.x) ||
	   math.is_inf(radians.y) {
		return false
	}

	orbit.yaw = math.mod(orbit.yaw - radians.x, f32(2 * math.PI))
	orbit.pitch = clamp(orbit.pitch + radians.y, -pitch_limit, pitch_limit)
	return true
}

zoom_orbit :: proc(orbit: ^Orbit, amount: f64, min_distance, max_distance: f32) -> bool {
	if !(min_distance > 0 && max_distance >= min_distance && orbit.distance > 0) ||
	   math.is_inf(max_distance) ||
	   math.is_inf(orbit.distance) ||
	   math.is_nan(amount) ||
	   math.is_inf(amount) {
		return false
	}

	// Clamp in log space so a large scroll cannot overflow exp.
	distance := clamp(
		math.ln(f64(orbit.distance)) - amount,
		math.ln(f64(min_distance)),
		math.ln(f64(max_distance)),
	)
	orbit.distance = clamp(f32(math.exp(distance)), min_distance, max_distance)
	return true
}
