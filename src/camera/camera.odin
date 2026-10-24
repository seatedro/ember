package camera

import emath "../core/math"

Camera :: struct {
	position:    emath.Vec3d,
	orientation: emath.Quaternion,
}

// Undo the camera's pose: move by -position, then rotate by the transposed
// rotation.
view_matrix :: proc(camera: Camera) -> emath.Mat4 {
	result := view_rotation(camera)
	p := camera.position
	for row in 0 ..< 3 {
		result[row, 3] = f32(
			-(f64(result[row, 0]) * p[0] +
				f64(result[row, 1]) * p[1] +
				f64(result[row, 2]) * p[2]),
		)
	}

	return result
}

view_rotation :: proc(camera: Camera) -> emath.Mat4 {
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

	return result
}
