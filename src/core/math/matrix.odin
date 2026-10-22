package ember_math

import stdmath "core:math"

// Column-major, column vectors, indexed m[row, column]. +Y is up, the camera
// looks down -Z (right-handed), and depth is reversed: 1 at the near plane and 0
// at the far plane.
Mat4 :: matrix[4, 4]f32
Mat3 :: matrix[3, 3]f32
Vec4 :: [4]f32

identity :: proc() -> Mat4 {
	result: Mat4
	for i in 0 ..< 4 {
		result[i, i] = 1
	}
	return result
}

translation :: proc(position: Vec3) -> Mat4 {
	result := identity()
	for i in 0 ..< 3 {
		result[i, 3] = position[i]
	}
	return result
}

rotation_x :: proc(angle: f32) -> Mat4 {
	c, s := stdmath.cos(angle), stdmath.sin(angle)
	result := identity()
	result[1, 1], result[1, 2] = c, -s
	result[2, 1], result[2, 2] = s, c
	return result
}

rotation_y :: proc(angle: f32) -> Mat4 {
	c, s := stdmath.cos(angle), stdmath.sin(angle)
	result := identity()
	result[0, 0], result[0, 2] = c, s
	result[2, 0], result[2, 2] = -s, c
	return result
}

perspective :: proc(fov_y, aspect, near, far: f32) -> Mat4 {
	assert(far > near)
	result := perspective_infinite(fov_y, aspect, near)
	// Clip z = A * view_z + B, where A is result[2, 2] and B is result[2, 3].
	// A point at distance d in front of the camera has view z = -d and
	// clip w = d, so depth = z / w = B / d - A.
	// Depth is reversed, so we want 1 at d = near and 0 at d = far:
	//   B / near - A = 1
	//   B / far - A = 0, so A = B / far
	// Substituting gives B = far * near / (far - near) and
	// A = near / (far - near).
	result[2, 2] = near / (far - near)
	result[2, 3] = far * near / (far - near)
	return result
}

// The same projection with the far plane pushed to infinity. As far grows,
// A = near / (far - near) goes to 0 and B = far * near / (far - near) goes to
// near, so depth = near / d: exactly 1 at the near plane, approaching 0 with
// distance, and never reaching it. Floats keep their relative precision near
// 0, so distant depths stay distinguishable.
perspective_infinite :: proc(fov_y, aspect, near: f32) -> Mat4 {
	assert(fov_y > 0 && fov_y < stdmath.PI)
	assert(aspect > 0 && near > 0)

	// f is the cotangent of half the vertical field of view. A point at the
	// top edge of the view has y / d = tan(fov_y / 2), so scaling y by f
	// puts it at clip y = w. Dividing by aspect does the same horizontally.
	f := 1 / stdmath.tan(fov_y / 2)
	result: Mat4
	result[0, 0] = f / aspect
	result[1, 1] = f
	// Clip z is the constant near for every point, so depth = near / d.
	result[2, 3] = near
	// Clip w = -view z = d, the distance in front of the camera. The GPU
	// divides x, y, and z by it, which is what makes far things smaller.
	result[3, 2] = -1
	return result
}

look_at :: proc(eye, target, up: Vec3) -> Mat4 {
	forward := normalize(target - eye)
	right := normalize(cross(forward, up))
	camera_up := cross(right, forward)

	result := identity()
	for i in 0 ..< 3 {
		result[0, i] = right[i]
		result[1, i] = camera_up[i]
		result[2, i] = -forward[i]
	}
	result[0, 3] = -dot(right, eye)
	result[1, 3] = -dot(camera_up, eye)
	result[2, 3] = dot(forward, eye)
	return result
}
