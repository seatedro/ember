package ember_math

// Maps object space to world space. Identity is {orientation = 1, scale = {1,
// 1, 1}}, so a zeroed Transform isn't valid. Scale must be positive; flat or
// mirrored axes aren't supported.
Transform :: struct {
	position:    Vec3,
	orientation: Quaternion,
	scale:       Vec3,
}

// Rotation matrix whose columns are the rotated local axes.
rotation_matrix3 :: proc(orientation: Quaternion) -> Mat3 {
	q := quaternion_normalize(orientation)
	result: Mat3

	for axis in 0 ..< 3 {
		basis: Vec3
		basis[axis] = 1
		column := quaternion_rotate(q, basis)

		for row in 0 ..< 3 {
			result[row, axis] = column[row]
		}
	}

	return result
}

rotation_matrix :: proc(orientation: Quaternion) -> Mat4 {
	rotation := rotation_matrix3(orientation)
	result := identity()

	for row in 0 ..< 3 {
		for column in 0 ..< 3 {
			result[row, column] = rotation[row, column]
		}
	}

	return result
}

// Translation times rotation, with no scale.
rigid_matrix :: proc(position: Vec3, orientation: Quaternion) -> Mat4 {
	result := rotation_matrix(orientation)

	for row in 0 ..< 3 {
		result[row, 3] = position[row]
	}

	return result
}

// Scale, then rotate, then translate.
transform_matrix :: proc(transform: Transform) -> Mat4 {
	result := rotation_matrix(transform.orientation)

	for column in 0 ..< 3 {
		assert(transform.scale[column] > 0)

		for row in 0 ..< 3 {
			result[row, column] *= transform.scale[column]
		}

		result[column, 3] = transform.position[column]
	}

	return result
}

// Normals need the inverse transpose, which for T*R*S is R * inverse(S). It
// comes back as a mat4 to fit uniform block layout; use its 3x3 part.
normal_matrix :: proc(transform: Transform) -> Mat4 {
	result := rotation_matrix(transform.orientation)

	for column in 0 ..< 3 {
		assert(transform.scale[column] > 0)

		for row in 0 ..< 3 {
			result[row, column] /= transform.scale[column]
		}
	}

	return result
}
