package ember_math

// Object-local coordinates to world coordinates. The identity pose is
// {orientation = 1, scale = {1, 1, 1}}; a zero-initialized Transform is invalid.
// Scale must be positive: collapsed axes and reflections are unsupported.
Transform :: struct {
	position:    Vec3,
	orientation: Quaternion,
	scale:       Vec3,
}

// Convert quaternion orientation into a matrix that rotates local axes.
rotation_matrix :: proc(orientation: Quaternion) -> Mat4 {
	q := quaternion_normalize(orientation)
	result := identity()

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

// T * R * S: scale locally, rotate, then translate into world space.
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

// For T*R*S, the inverse transpose of the linear part is R * inverse(S).
// Embed it in mat4 for uniform-block layout; transform normals with its mat3.
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
