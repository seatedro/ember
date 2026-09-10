package ember_math

import stdmath "core:math"

// Column-major storage, column vectors, m[row, column] indexing. World/view use
// +Y up and a right-handed camera looking down -Z. Projection depth is [-1, 1].
Mat4 :: matrix[4, 4]f32
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
	assert(fov_y > 0 && fov_y < stdmath.PI)
	assert(aspect > 0 && near > 0 && far > near)

	f := 1 / stdmath.tan(fov_y / 2)
	result: Mat4
	result[0, 0] = f / aspect
	result[1, 1] = f
	result[2, 2] = (far + near) / (near - far)
	result[2, 3] = (2 * far * near) / (near - far)
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
