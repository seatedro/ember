package ember_math

import stdmath "core:math"

// Unit quaternions represent rotations. 1 is identity; a*b applies b, then a.
Quat :: quaternion128

quat_axis_angle :: proc(angle: f32, axis: Vec3) -> Quat {
	vector := normalize(axis) * stdmath.sin(angle / 2)
	return quaternion(x = vector.x, y = vector.y, z = vector.z, w = stdmath.cos(angle / 2))
}

quat_normalize :: proc(q: Quat) -> Quat {
	magnitude := abs(q)
	assert(magnitude > 0, "Cannot normalize zero quaternion")
	return q / Quat(magnitude)
}

// q must be unit length. A vector rotates as q * (v, 0) * conjugate(q).
quat_rotate :: proc(q: Quat, v: Vec3) -> Vec3 {
	rotated := q * quaternion(x = v.x, y = v.y, z = v.z, w = f32(0)) * conj(q)
	return Vec3(rotated.xyz)
}
