package ember_math

Frustum :: struct {
	planes: [6]Vec4,
}

frustum_from_matrix :: proc(view_projection: Mat4) -> Frustum {
	rows: [4]Vec4
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			rows[row][column] = view_projection[row, column]
		}
	}

	// A point is inside when -w <= x, y <= w and 0 <= z <= w in clip space.
	// Each clip component is one matrix row dotted with the world point, so
	// x = rows[0]·p, y = rows[1]·p, z = rows[2]·p, and w = rows[3]·p.
	// Moving everything to one side turns each check into
	// (some combination of rows)·p >= 0, and that 4-vector is a world-space
	// plane: xyz is its normal, pointing into the frustum, and w its offset.
	result := Frustum {
		planes = {
			// Left: -w <= x, so w + x >= 0.
			rows[3] + rows[0],
			// Right: x <= w, so w - x >= 0.
			rows[3] - rows[0],
			// Bottom: -w <= y, so w + y >= 0.
			rows[3] + rows[1],
			// Top: y <= w, so w - y >= 0.
			rows[3] - rows[1],
			// Near: depth is reversed, so the near plane is where z reaches w.
			// z <= w, so w - z >= 0.
			rows[3] - rows[2],
			// Far: the far plane is where z reaches 0, so z >= 0.
			rows[2],
		},
	}
	for &plane in result.planes {
		normal_length := length(plane.xyz)
		// An infinite projection gives every point the same clip z, so the
		// far plane comes out as (0, 0, 0, near). Every point passes it and
		// it has no normal to normalize, so replace it with a plane that
		// reports a distance of 1 everywhere and never culls.
		if normal_length == 0 {
			plane = {0, 0, 0, 1}
			continue
		}
		// With a unit normal, dot(normal, p) + w is the signed distance from
		// the plane, which sphere_in_frustum compares against the radius.
		plane /= normal_length
	}

	return result
}

sphere_in_frustum :: proc(frustum: Frustum, sphere: Bounding_Sphere) -> bool {
	assert(sphere.radius >= 0)
	for plane in frustum.planes {
		terms := Vec3{plane.x, plane.y, plane.z} * sphere.center
		distance := terms.x + terms.y + terms.z + plane.w
		// Allow a little slack so a sphere that just touches a plane isn't
		// culled by rounding.
		tolerance :=
			0.000001 *
			max(1, abs(terms.x) + abs(terms.y) + abs(terms.z) + abs(plane.w) + sphere.radius)
		if distance < -sphere.radius - tolerance {
			return false
		}
	}

	return true
}
