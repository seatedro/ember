package camera

import emath "../core/math"

Camera :: struct {
	position:    emath.Vec3,
	orientation: emath.Quat,
}

// Invert the camera pose: transpose its rotation and apply it to -position.
view :: proc(camera: Camera) -> emath.Mat4 {
	q := emath.quat_normalize(camera.orientation)
	right := emath.quat_rotate(q, {1, 0, 0})
	up := emath.quat_rotate(q, {0, 1, 0})
	back := emath.quat_rotate(q, {0, 0, 1})
	result := emath.identity()
	for i in 0 ..< 3 {
		result[0, i] = right[i]
		result[1, i] = up[i]
		result[2, i] = back[i]
	}
	result[0, 3] = -emath.dot(right, camera.position)
	result[1, 3] = -emath.dot(up, camera.position)
	result[2, 3] = -emath.dot(back, camera.position)
	return result
}
