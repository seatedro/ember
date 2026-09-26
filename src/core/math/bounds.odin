package ember_math

Bounding_Sphere :: struct {
	center: Vec3,
	radius: f32,
}

transform_sphere :: proc(sphere: Bounding_Sphere, transform: Transform) -> Bounding_Sphere {
	assert(sphere.radius >= 0)
	for scale in transform.scale {
		assert(scale > 0)
	}

	return {
		center = transform.position + quaternion_rotate(quaternion_normalize(transform.orientation), sphere.center * transform.scale),
		// The largest scale is the most any direction can stretch.
		radius = sphere.radius * max(transform.scale.x, transform.scale.y, transform.scale.z),
	}
}
