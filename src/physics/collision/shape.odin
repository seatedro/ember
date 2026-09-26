package collision

import emath "../../core/math"
import "core:math"

Sphere :: struct {
	radius: f32,
}

Box :: struct {
	half_extent: emath.Vec3,
}

Capsule :: struct {
	radius, half_height: f32,
}

// Capsules run along local Y. half_height is half the distance between the two
// cap centers.
Shape :: union {
	Sphere,
	Box,
	Capsule,
}

AABB :: struct {
	min, max: emath.Vec3,
}

Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
	Did_Not_Converge,
}

valid_shape :: proc(shape: Shape) -> bool {
	switch s in shape {
	case Sphere:
		return emath.finite(s.radius) && s.radius > 0
	case Box:
		return(
			emath.finite_vector(s.half_extent) &&
			min(s.half_extent.x, s.half_extent.y, s.half_extent.z) > 0 \
		)
	case Capsule:
		return(
			emath.finite(s.radius) &&
			s.radius > 0 &&
			emath.finite(s.half_height) &&
			s.half_height >= 0 &&
			emath.finite(s.radius + s.half_height) \
		)
	}
	return false
}

shape_bounds :: proc(
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
) -> (
	AABB,
	bool,
) {
	if !valid_shape(shape) ||
	   !emath.finite_vector(position) ||
	   !emath.valid_orientation(orientation) {
		return {}, false
	}
	q := emath.quaternion_normalize(orientation)
	extent: [3]f64
	switch s in shape {
	case Sphere:
		extent = {f64(s.radius), f64(s.radius), f64(s.radius)}
	case Box:
		for axis in 0 ..< 3 {
			direction: emath.Vec3
			direction[axis] = 1
			rotated := emath.quaternion_rotate(q, direction)
			for i in 0 ..< 3 {
				extent[i] += abs(f64(rotated[i])) * f64(s.half_extent[axis])
			}
		}
	case Capsule:
		up := emath.quaternion_rotate(q, {0, 1, 0})
		for i in 0 ..< 3 {
			extent[i] = f64(s.radius) + abs(f64(up[i])) * f64(s.half_height)
		}
	}
	bounds: AABB
	// Round outward so the broadphase never skips a hit that just grazes.
	for i in 0 ..< 3 {
		low, high := f64(position[i]) - extent[i], f64(position[i]) + extent[i]
		bounds.min[i], bounds.max[i] = f32(low), f32(high)
		if f64(bounds.min[i]) > low {
			bounds.min[i] = math.nextafter(bounds.min[i], -math.inf_f32(1))
		}
		if f64(bounds.max[i]) < high {
			bounds.max[i] = math.nextafter(bounds.max[i], math.inf_f32(1))
		}
	}
	return bounds, emath.finite_vector(bounds.min) && emath.finite_vector(bounds.max)
}

combine_bounds :: proc(a, b: AABB) -> AABB {
	result: AABB
	for i in 0 ..< 3 {
		result.min[i] = min(a.min[i], b.min[i])
		result.max[i] = max(a.max[i], b.max[i])
	}
	return result
}

bounds_overlap :: proc(a, b: AABB) -> bool {
	for i in 0 ..< 3 {
		if a.min[i] > b.max[i] || a.max[i] < b.min[i] {
			return false
		}
	}
	return true
}

expanded_bounds :: proc(bounds: AABB, margin: f32) -> AABB {
	return {
		bounds.min - emath.Vec3{margin, margin, margin},
		bounds.max + emath.Vec3{margin, margin, margin},
	}
}
