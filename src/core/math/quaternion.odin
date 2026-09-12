package ember_math

import stdmath "core:math"

// Unit quaternions represent rotations. 1 is identity; a*b applies b, then a.
Quaternion :: quaternion128

// Build a rotation by angle_radians; this function normalizes the axis.
quaternion_angle_axis :: proc(angle_radians: f32, axis: Vec3) -> Quaternion {
	vector := normalize(axis) * stdmath.sin(angle_radians / 2)

	return quaternion(x = vector.x, y = vector.y, z = vector.z, w = stdmath.cos(angle_radians / 2))
}

quaternion_normalize :: proc(orientation: Quaternion) -> Quaternion {
	magnitude := abs(orientation)
	assert(magnitude > 0, "Cannot normalize zero quaternion")

	return orientation / Quaternion(magnitude)
}

// The orientation must have unit length.
// Apply it to a direction using the quaternion and its conjugate.
quaternion_rotate :: proc(orientation: Quaternion, vector: Vec3) -> Vec3 {
	rotated :=
		orientation *
		quaternion(x = vector.x, y = vector.y, z = vector.z, w = f32(0)) *
		conj(orientation)

	return Vec3(rotated.xyz)
}
