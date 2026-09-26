package collision

import emath "../../core/math"
import "core:math"

// Where a ray or moving shape first touches the target. fraction runs along the
// displacement, so 1 is the end. normal is the target's surface normal at
// position. A cast that starts inside reports fraction 0 and a zero normal.
Cast_Hit :: struct {
	fraction:            f32,
	position, normal:    emath.Vec3,
	started_overlapping: bool,
}

// Exact ray test against one shape. Only hits within the displacement count.
raycast :: proc(
	origin, displacement: emath.Vec3,
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
) -> (
	Cast_Hit,
	bool,
) {
	basis := convex(shape, position, orientation, origin)
	local, delta: [3]f64
	for i in 0 ..< 3 {
		local[i] = dot64(-basis.center, basis.axes[i])
		delta[i] = dot64(cast([3]f64)(displacement), basis.axes[i])
	}
	fraction := f64(2)
	normal: [3]f64
	inside := false
	switch s in shape {
	case Sphere:
		inside = dot64(local, local) <= f64(s.radius) * f64(s.radius)
		fraction = ray_sphere(local, delta, f64(s.radius))
		if fraction <= 1 {
			normal = local + delta * fraction
		}
	case Box:
		inside = true
		lo, hi := f64(0), f64(1)
		for i in 0 ..< 3 {
			half := f64(s.half_extent[i])
			inside = inside && abs(local[i]) <= half
			if delta[i] == 0 {
				if abs(local[i]) > half {
					return {}, false
				}
				continue
			}
			a, b := (-half - local[i]) / delta[i], (half - local[i]) / delta[i]
			entry, exit := min(a, b), max(a, b)
			if entry >= lo {
				lo = entry
				normal = {}
				normal[i] = -1 if delta[i] > 0 else 1
			}
			hi = min(hi, exit)
			if lo > hi {
				return {}, false
			}
		}
		fraction = lo
	case Capsule:
		half, radius := f64(s.half_height), f64(s.radius)
		nearest := local - [3]f64{0, clamp(local.y, -half, half), 0}
		inside = dot64(nearest, nearest) <= radius * radius
		// A capsule is a cylinder with a sphere on each end.
		flat, flat_delta := local, delta
		flat.y, flat_delta.y = 0, 0
		cylinder := ray_sphere(flat, flat_delta, radius)
		if cylinder <= 1 && abs(local.y + delta.y * cylinder) <= half {
			fraction = cylinder
			normal = flat + flat_delta * cylinder
		}
		for sign in ([2]f64{-1, 1}) {
			offset := local - [3]f64{0, sign * half, 0}
			cap := ray_sphere(offset, delta, radius)
			if cap < fraction {
				fraction = cap
				normal = offset + delta * cap
			}
		}
	}
	if inside {
		return {position = origin, started_overlapping = true}, true
	}
	if fraction > 1 {
		return {}, false
	}
	world_normal: [3]f64
	for i in 0 ..< 3 {
		world_normal += basis.axes[i] * normal[i]
	}
	magnitude := length64(world_normal)
	if magnitude > 0 {
		world_normal /= magnitude
	}
	return {
			fraction = f32(fraction),
			position = origin + displacement * f32(fraction),
			normal = emath.Vec3(world_normal),
		},
		true
}

@(private)
ray_sphere :: proc(origin, delta: [3]f64, radius: f64) -> f64 {
	a := dot64(delta, delta)
	b := dot64(origin, delta)
	c := dot64(origin, origin) - radius * radius
	if a == 0 || b > 0 {
		return 2
	}
	discriminant := b * b - a * c
	if discriminant < 0 {
		return 2
	}
	// Writing the entry root as c / (-b + sqrt(D)) avoids subtracting two
	// nearly equal numbers.
	denominator := -b + math.sqrt(discriminant)
	if denominator == 0 {
		return 0
	}
	fraction := c / denominator
	return fraction if fraction >= 0 else 2
}
