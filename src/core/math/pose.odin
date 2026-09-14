package ember_math

import "core:math"

Pose :: struct {
	position:    Vec3,
	orientation: Quaternion,
}

pose_matrix :: proc(pose: Pose) -> Mat4 {
	return transform_matrix(
		{position = pose.position, orientation = pose.orientation, scale = {1, 1, 1}},
	)
}

interpolate_pose :: proc(previous, current: Pose, alpha: f32) -> Pose {
	return {
		position = math.lerp(previous.position, current.position, alpha),
		orientation = quaternion_slerp(previous.orientation, current.orientation, alpha),
	}
}

quaternion_slerp :: proc(from, to: Quaternion, alpha: f32) -> Quaternion {
	a := quaternion_normalize(from)
	b := quaternion_normalize(to)
	cosine := real(conj(a) * b)
	// q and -q describe the same rotation; choose the shorter arc.
	if cosine < 0 {
		b = -b
		cosine = -cosine
	}
	if cosine > 0.9995 {
		return quaternion_normalize(a * Quaternion(1 - alpha) + b * Quaternion(alpha))
	}

	angle := math.acos(clamp(cosine, 0, 1))
	return quaternion_normalize(
		(a * Quaternion(math.sin((1 - alpha) * angle)) + b * Quaternion(math.sin(alpha * angle))) /
		Quaternion(math.sin(angle)),
	)
}
