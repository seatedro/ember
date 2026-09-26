package collision

import emath "../../core/math"
import "core:math"

// Closest points between two shapes. The normal points from A to B, and is zero
// when they're within tolerance.
Distance :: struct {
	distance:     f32,
	a, b, normal: emath.Vec3,
}

distance :: proc(
	shape_a: Shape,
	position_a: emath.Vec3,
	orientation_a: emath.Quaternion,
	shape_b: Shape,
	position_b: emath.Vec3,
	orientation_b: emath.Quaternion,
	tolerance: f32,
) -> (
	Distance,
	Error,
) {
	origin := position_a
	result, err := convex_distance(
		convex(shape_a, position_a, orientation_a, origin),
		convex(shape_b, position_b, orientation_b, origin),
		f64(tolerance),
	)
	if err != .None {
		return {}, err
	}
	return {
			distance = f32(result.distance),
			a = origin + emath.Vec3(result.a),
			b = origin + emath.Vec3(result.b),
			normal = emath.Vec3(result.normal),
		},
		.None
}

// A shape placed relative to an origin near the query, in f64, so the simplex
// math keeps the small differences it depends on.
@(private)
Convex :: struct {
	shape:  Shape,
	center: [3]f64,
	axes:   [3][3]f64,
}

@(private)
Support_Point :: struct {
	point, a, b: [3]f64,
}

@(private)
Distance_Result :: struct {
	distance:     f64,
	a, b, normal: [3]f64,
}

@(private)
Simplex :: struct {
	points: [4]Support_Point,
	count:  int,
}

@(private)
convex :: proc(
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	origin: emath.Vec3,
) -> Convex {
	result := Convex {
		shape  = shape,
		center = cast([3]f64)(position) - cast([3]f64)(origin),
	}
	q := emath.quaternion_normalize(orientation)
	for i in 0 ..< 3 {
		axis: emath.Vec3
		axis[i] = 1
		result.axes[i] = cast([3]f64)(emath.quaternion_rotate(q, axis))
	}
	return result
}

@(private)
support :: proc(shape: Convex, direction: [3]f64) -> [3]f64 {
	point := shape.center
	switch s in shape.shape {
	case Sphere:
		magnitude := length64(direction)
		if magnitude > 0 {
			point += direction * (f64(s.radius) / magnitude)
		}
	case Box:
		for i in 0 ..< 3 {
			sign := f64(1) if dot64(direction, shape.axes[i]) >= 0 else -1
			point += shape.axes[i] * (f64(s.half_extent[i]) * sign)
		}
	case Capsule:
		sign := f64(1) if dot64(direction, shape.axes[1]) >= 0 else -1
		point += shape.axes[1] * (f64(s.half_height) * sign)
		magnitude := length64(direction)
		if magnitude > 0 {
			point += direction * (f64(s.radius) / magnitude)
		}
	}
	return point
}

@(private)
minkowski_support :: proc(a, b: Convex, direction: [3]f64) -> Support_Point {
	pa, pb := support(a, direction), support(b, -direction)
	return {point = pa - pb, a = pa, b = pb}
}

@(private)
convex_distance :: proc(a, b: Convex, tolerance: f64) -> (Distance_Result, Error) {
	result, _, err := gjk(a, b, tolerance)
	return result, err
}

// GJK finds the point on A - B closest to the origin. We keep each shape's
// support points so the simplex weights give us the closest points on both.
// When the distance is within tolerance, the simplex contains the origin and
// seeds EPA.
@(private)
gjk :: proc(a, b: Convex, tolerance: f64) -> (Distance_Result, Simplex, Error) {
	direction := b.center - a.center
	if dot64(direction, direction) == 0 {
		direction = {1, 0, 0}
	}
	simplex: Simplex
	simplex.points[0] = minkowski_support(a, b, direction)
	simplex.count = 1
	for _ in 0 ..< 128 {
		weights, closest := closest_simplex(simplex.points[:simplex.count])
		result: Distance_Result
		for i in 0 ..< simplex.count {
			result.a += simplex.points[i].a * weights[i]
			result.b += simplex.points[i].b * weights[i]
		}
		result.distance = length64(closest)
		if result.distance <= tolerance {
			return result, simplex, .None
		}
		result.normal = -closest / result.distance
		next := minkowski_support(a, b, -closest)
		gap := dot64(closest, closest - next.point)
		if gap <= tolerance * result.distance {
			return result, simplex, .None
		}

		kept := 0
		for i in 0 ..< simplex.count {
			if weights[i] > 0 {
				simplex.points[kept] = simplex.points[i]
				kept += 1
			}
		}
		if kept == 4 {
			return {}, {}, .Did_Not_Converge
		}
		simplex.points[kept] = next
		simplex.count = kept + 1
	}
	return {}, {}, .Did_Not_Converge
}

// A simplex has at most 15 faces. Project onto each one, keep the weights that
// aren't negative, and fall back to edges when a face is degenerate.
@(private)
closest_simplex :: proc(points: []Support_Point) -> ([4]f64, [3]f64) {
	best := f64(1e300)
	best_weights: [4]f64
	closest: [3]f64
	for mask in 1 ..< (1 << uint(len(points))) {
		indices: [4]int
		count := 0
		for i in 0 ..< len(points) {
			if mask & (1 << uint(i)) != 0 {
				indices[count] = i
				count += 1
			}
		}
		weights: [4]f64
		weights[indices[0]] = 1
		base := points[indices[0]].point
		if count > 1 {
			edges: [3][3]f64
			for i in 0 ..< count - 1 {
				edges[i] = points[indices[i + 1]].point - base
			}
			system: [3][4]f64
			for i in 0 ..< count - 1 {
				for j in 0 ..< count - 1 {
					system[i][j] = dot64(edges[i], edges[j])
				}
				system[i][count - 1] = -dot64(edges[i], base)
			}
			solution, valid := solve_projection(system, count - 1)
			if !valid {
				continue
			}
			for i in 0 ..< count - 1 {
				weights[indices[i + 1]] = solution[i]
				weights[indices[0]] -= solution[i]
			}
		}
		valid := true
		for weight in weights {
			valid = valid && weight >= 0
		}
		if !valid {
			continue
		}
		point: [3]f64
		for p, i in points {
			point += p.point * weights[i]
		}
		distance_squared := dot64(point, point)
		if distance_squared < best {
			best, closest, best_weights = distance_squared, point, weights
		}
	}
	return best_weights, closest
}

@(private)
solve_projection :: proc(input: [3][4]f64, n: int) -> ([3]f64, bool) {
	a := input
	scale: f64
	for i in 0 ..< n {
		scale = max(scale, abs(a[i][i]))
	}
	for column in 0 ..< n {
		pivot := column
		for row in column + 1 ..< n {
			if abs(a[row][column]) > abs(a[pivot][column]) {
				pivot = row
			}
		}
		if abs(a[pivot][column]) <= scale * 1e-14 {
			return {}, false
		}
		a[column], a[pivot] = a[pivot], a[column]
		divisor := a[column][column]
		for j in column ..= n {
			a[column][j] /= divisor
		}
		for row in 0 ..< n {
			if row == column {
				continue
			}
			factor := a[row][column]
			for j in column ..= n {
				a[row][j] -= factor * a[column][j]
			}
		}
	}
	result: [3]f64
	for i in 0 ..< n {
		result[i] = a[i][n]
	}
	return result, true
}

@(private)
length64 :: proc(v: [3]f64) -> f64 {
	return math.sqrt(dot64(v, v))
}

@(private)
dot64 :: proc(a, b: [3]f64) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}
