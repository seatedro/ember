package ember_math

import stdmath "core:math"

// Unit quaternions are rotations. 1 is no rotation, and a*b applies b first,
// then a.
Quaternion :: quaternion128

// Rotation of angle_radians around axis. The axis doesn't need to be
// normalized.
quaternion_angle_axis :: proc(angle_radians: f32, axis: Vec3) -> Quaternion {
	vector := normalize(axis) * stdmath.sin(angle_radians / 2)

	return quaternion(x = vector.x, y = vector.y, z = vector.z, w = stdmath.cos(angle_radians / 2))
}

quaternion_normalize :: proc(orientation: Quaternion) -> Quaternion {
	magnitude := abs(orientation)
	assert(magnitude > 0, "Cannot normalize zero quaternion")

	return orientation / Quaternion(magnitude)
}

// Rotates vector by a unit-length orientation.
quaternion_rotate :: proc(orientation: Quaternion, vector: Vec3) -> Vec3 {
	rotated :=
		orientation *
		quaternion(x = vector.x, y = vector.y, z = vector.z, w = f32(0)) *
		conj(orientation)

	return Vec3(rotated.xyz)
}

// True if the orientation can be normalized, meaning it's finite and not zero.
valid_orientation :: proc(orientation: Quaternion) -> bool {
	magnitude := abs(orientation)
	return finite(magnitude) && magnitude > 0
}

// Rotate local by orientation, then move it by position.
transform_point :: proc(position: Vec3, orientation: Quaternion, local: Vec3) -> Vec3 {
	return position + quaternion_rotate(orientation, local)
}

inverse_transform_point :: proc(position: Vec3, orientation: Quaternion, world: Vec3) -> Vec3 {
	return quaternion_rotate(conj(orientation), world - position)
}

quaternion_slerp :: proc(from, to: Quaternion, alpha: f32) -> Quaternion {
	a := quaternion_normalize(from)
	b := quaternion_normalize(to)
	cosine := real(conj(a) * b)
	// q and -q are the same rotation, so flip one to take the short way around.
	if cosine < 0 {
		b = -b
		cosine = -cosine
	}
	if cosine > 0.9995 {
		return quaternion_normalize(a * Quaternion(1 - alpha) + b * Quaternion(alpha))
	}

	angle := stdmath.acos(clamp(cosine, 0, 1))
	return quaternion_normalize(
		(a * Quaternion(stdmath.sin((1 - alpha) * angle)) +
			b * Quaternion(stdmath.sin(alpha * angle))) /
		Quaternion(stdmath.sin(angle)),
	)
}
