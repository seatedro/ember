package ember_math

Frustum :: struct {
	planes: [6]Vec4,
}

frustum_from_matrix :: proc(view_projection: Mat4) -> Frustum {
	result: Frustum
	for axis in 0 ..< 3 {
		for side in 0 ..< 2 {
			plane := &result.planes[axis * 2 + side]
			sign: f32 = 1 if side == 0 else -1
			// Clip coordinates satisfy -w <= x,y,z <= w. Adding/subtracting
			// matrix rows expresses those six inequalities in world space.
			for column in 0 ..< 4 {
				plane[column] = view_projection[3, column] + sign * view_projection[axis, column]
			}

			normal_length := length({plane.x, plane.y, plane.z})
			assert(normal_length > 0)
			plane^ /= normal_length
		}
	}

	return result
}

sphere_in_frustum :: proc(frustum: Frustum, sphere: Bounding_Sphere) -> bool {
	assert(sphere.radius >= 0)
	for plane in frustum.planes {
		terms := Vec3{plane.x, plane.y, plane.z} * sphere.center
		distance := terms.x + terms.y + terms.z + plane.w
		// Keep tangency despite rounding in plane extraction and the dot product.
		tolerance :=
			0.000001 *
			max(1, abs(terms.x) + abs(terms.y) + abs(terms.z) + abs(plane.w) + sphere.radius)
		if distance < -sphere.radius - tolerance {
			return false
		}
	}

	return true
}
