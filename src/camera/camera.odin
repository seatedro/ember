package camera

import emath "../core/math"

Camera :: struct {
	position:    emath.Vec3,
	orientation: emath.Quaternion,
}

// Invert the camera pose: transpose its rotation and apply it to -position.
view_matrix :: proc(camera: Camera) -> emath.Mat4 {
	q := emath.quaternion_normalize(camera.orientation)
	right := emath.quaternion_rotate(q, {1, 0, 0})
	up := emath.quaternion_rotate(q, {0, 1, 0})
	back := emath.quaternion_rotate(q, {0, 0, 1})
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
