package physics

import emath "../core/math"
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

// Capsules extend along local Y; half_height measures the segment between cap centers.
Shape :: union {
	Sphere,
	Box,
	Capsule,
}

AABB :: struct {
	min, max: emath.Vec3,
}

valid_shape :: proc(shape: Shape) -> bool {
	switch s in shape {
	case Sphere:
		return finite(s.radius) && s.radius > 0
	case Box:
		return(
			finite_vector(s.half_extent) &&
			min(s.half_extent.x, s.half_extent.y, s.half_extent.z) > 0 \
		)
	case Capsule:
		return(
			finite(s.radius) &&
			s.radius > 0 &&
			finite(s.half_height) &&
			s.half_height >= 0 &&
			finite(s.radius + s.half_height) \
		)
	}
	return false
}

shape_bounds :: proc(shape: Shape, pose: emath.Pose) -> (AABB, bool) {
	if !valid_shape(shape) || !valid_pose(pose) {
		return {}, false
	}
	q := emath.quaternion_normalize(pose.orientation)
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
	// Round outward so the broad phase cannot reject a grazing narrow-phase hit.
	for i in 0 ..< 3 {
		low, high := f64(pose.position[i]) - extent[i], f64(pose.position[i]) + extent[i]
		bounds.min[i], bounds.max[i] = f32(low), f32(high)
		if f64(bounds.min[i]) > low {
			bounds.min[i] = math.nextafter(bounds.min[i], -math.inf_f32(1))
		}
		if f64(bounds.max[i]) < high {
			bounds.max[i] = math.nextafter(bounds.max[i], math.inf_f32(1))
		}
	}
	return bounds, finite_vector(bounds.min) && finite_vector(bounds.max)
}

@(private)
combine_bounds :: proc(a, b: AABB) -> AABB {
	result: AABB
	for i in 0 ..< 3 {
		result.min[i] = min(a.min[i], b.min[i])
		result.max[i] = max(a.max[i], b.max[i])
	}
	return result
}

@(private)
bounds_overlap :: proc(a, b: AABB) -> bool {
	for i in 0 ..< 3 {
		if a.min[i] > b.max[i] || a.max[i] < b.min[i] {
			return false
		}
	}
	return true
}

@(private)
bounds_area :: proc(bounds: AABB) -> f64 {
	d := cast([3]f64)(bounds.max) - cast([3]f64)(bounds.min)
	return 2 * (d.x * d.y + d.y * d.z + d.z * d.x)
}

@(private)
compose_pose :: proc(parent, local: emath.Pose) -> emath.Pose {
	return {
		position = parent.position + emath.quaternion_rotate(parent.orientation, local.position),
		orientation = emath.quaternion_normalize(parent.orientation * local.orientation),
	}
}

@(private)
expanded_bounds :: proc(bounds: AABB, margin: f32) -> AABB {
	return {
		bounds.min - emath.Vec3{margin, margin, margin},
		bounds.max + emath.Vec3{margin, margin, margin},
	}
}

@(private)
ray_bounds :: proc(origin, displacement: emath.Vec3, bounds: AABB, limit: f32) -> bool {
	lo, hi := f64(0), f64(limit)
	for i in 0 ..< 3 {
		if displacement[i] == 0 {
			if origin[i] < bounds.min[i] || origin[i] > bounds.max[i] {
				return false
			}
			continue
		}
		a := (f64(bounds.min[i]) - f64(origin[i])) / f64(displacement[i])
		b := (f64(bounds.max[i]) - f64(origin[i])) / f64(displacement[i])
		lo, hi = max(lo, min(a, b)), min(hi, max(a, b))
		if lo > hi {
			return false
		}
	}
	return true
}

@(private)
length64 :: proc(v: [3]f64) -> f64 {
	return math.sqrt(dot64(v, v))
}

@(private)
dot64 :: proc(a, b: [3]f64) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}
