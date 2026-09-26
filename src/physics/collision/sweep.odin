package collision

import emath "../../core/math"

// Slides shape along displacement, without rotating, until it's within
// tolerance of target. Each iteration moves up to the plane between the closest
// points, which is always safe and can't skip over thin objects.
sweep :: proc(
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	displacement: emath.Vec3,
	target: Shape,
	target_position: emath.Vec3,
	target_orientation: emath.Quaternion,
	tolerance: f32,
) -> (
	Cast_Hit,
	bool,
	Error,
) {
	origin := position
	moving := convex(shape, position, orientation, origin)
	fixed := convex(target, target_position, target_orientation, origin)
	start := moving.center
	fraction := f64(0)
	delta := cast([3]f64)(displacement)
	normal: [3]f64
	for _ in 0 ..< 128 {
		moving.center = start + delta * fraction
		distance, err := convex_distance(moving, fixed, f64(tolerance) * 0.05)
		if err != .None {
			return {}, false, err
		}
		if distance.distance <= f64(tolerance) {
			return {
					fraction = f32(fraction),
					position = origin + emath.Vec3(distance.b),
					normal = -emath.Vec3(normal),
					started_overlapping = fraction == 0,
				},
				true,
				.None
		}
		normal = distance.normal
		closing := dot64(normal, delta)
		if closing <= 0 {
			return {}, false, .None
		}
		advance := (distance.distance - f64(tolerance) * 0.25) / closing
		if fraction + advance > 1 {
			return {}, false, .None
		}
		if fraction + advance <= fraction {
			return {}, false, .Did_Not_Converge
		}
		fraction += advance
	}
	return {}, false, .Did_Not_Converge
}
