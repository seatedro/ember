package collision

import emath "../../core/math"

MANIFOLD_CAPACITY :: 4

@(private)
COLLISION_TOLERANCE :: 0.0001

// A supporting face has at most four corners, and clipping one quad against
// another adds at most one vertex per clip plane.
@(private)
POLYGON_CAPACITY :: 8

// The contact point on each shape, in world space.
Manifold_Point :: struct {
	a, b:       emath.Vec3,
	separation: f32,
}

// The normal points from A to B. Separation is negative while they overlap. No
// points means the shapes are farther apart than max_separation.
Manifold :: struct {
	normal: emath.Vec3,
	points: [MANIFOLD_CAPACITY]Manifold_Point,
	count:  int,
}

@(private)
Polygon :: struct {
	points: [POLYGON_CAPACITY]emath.Vec3,
	count:  int,
}

collide :: proc(
	shape_a: Shape,
	position_a: emath.Vec3,
	orientation_a: emath.Quaternion,
	shape_b: Shape,
	position_b: emath.Vec3,
	orientation_b: emath.Quaternion,
	max_separation: f32,
) -> (
	Manifold,
	Error,
) {
	deepest, normal, found, err := deepest_point(
		shape_a,
		position_a,
		orientation_a,
		shape_b,
		position_b,
		orientation_b,
	)
	if err != .None || !found || deepest.separation > max_separation {
		return {}, err
	}

	manifold := Manifold {
		normal = normal,
	}
	face_a := supporting_face(shape_a, position_a, orientation_a, normal)
	face_b := supporting_face(shape_b, position_b, orientation_b, -normal)
	clip_faces(face_a, face_b, normal, max_separation, position_a, &manifold)
	if manifold.count == 0 {
		manifold.points[0] = deepest
		manifold.count = 1
	}
	return manifold, .None
}

// Every shape is a core plus a radius: a sphere is a point, a capsule is a
// segment, and a box is just the box. If the cores are apart, GJK gives the
// closest points directly. If they overlap we need EPA, but points and segments
// have no inside to expand into, so for those we run EPA on the full rounded
// shapes.
@(private)
deepest_point :: proc(
	shape_a: Shape,
	position_a: emath.Vec3,
	orientation_a: emath.Quaternion,
	shape_b: Shape,
	position_b: emath.Vec3,
	orientation_b: emath.Quaternion,
) -> (
	point: Manifold_Point,
	normal: emath.Vec3,
	found: bool,
	err: Error,
) {
	origin := position_a
	core_a := convex(core_shape(shape_a), position_a, orientation_a, origin)
	core_b := convex(core_shape(shape_b), position_b, orientation_b, origin)
	radius_a, radius_b := f64(core_radius(shape_a)), f64(core_radius(shape_b))
	distance, simplex, gjk_error := gjk(core_a, core_b, COLLISION_TOLERANCE)
	if gjk_error != .None {
		return {}, {}, false, gjk_error
	}

	if distance.distance > COLLISION_TOLERANCE {
		point = {
			a          = origin + emath.Vec3(distance.a + distance.normal * radius_a),
			b          = origin + emath.Vec3(distance.b - distance.normal * radius_b),
			separation = f32(distance.distance - radius_a - radius_b),
		}
		return point,
			emath.Vec3(distance.normal),
			emath.finite_vector(point.a) && emath.finite_vector(point.b),
			.None
	}

	penetration: Penetration
	ok: bool
	if core_has_volume(shape_a) || core_has_volume(shape_b) {
		penetration, ok = penetration_depth(core_a, core_b, simplex, COLLISION_TOLERANCE)
		penetration.a += penetration.normal * radius_a
		penetration.b -= penetration.normal * radius_b
		penetration.depth += radius_a + radius_b
	} else {
		full_a := convex(shape_a, position_a, orientation_a, origin)
		full_b := convex(shape_b, position_b, orientation_b, origin)
		_, simplex, gjk_error = gjk(full_a, full_b, COLLISION_TOLERANCE)
		if gjk_error != .None {
			return {}, {}, false, gjk_error
		}
		penetration, ok = penetration_depth(full_a, full_b, simplex, COLLISION_TOLERANCE)
	}
	if !ok {
		return {}, {}, false, .None
	}

	point = {
		a          = origin + emath.Vec3(penetration.a),
		b          = origin + emath.Vec3(penetration.b),
		separation = -f32(penetration.depth),
	}
	return point,
		emath.Vec3(penetration.normal),
		emath.finite_vector(point.a) && emath.finite_vector(point.b),
		.None
}

@(private)
core_shape :: proc(shape: Shape) -> Shape {
	switch s in shape {
	case Sphere:
		return Sphere{}
	case Capsule:
		return Capsule{half_height = s.half_height}
	case Box:
		return s
	}
	return shape
}

@(private)
core_radius :: proc(shape: Shape) -> f32 {
	switch s in shape {
	case Sphere:
		return s.radius
	case Capsule:
		return s.radius
	case Box:
		return 0
	}
	return 0
}

@(private)
core_has_volume :: proc(shape: Shape) -> bool {
	_, box := shape.(Box)
	return box
}

// The face that faces direction the most, wound counter-clockwise around its
// normal. Spheres have no face. Capsules have their side segment, unless you're
// looking straight down the axis.
@(private)
supporting_face :: proc(
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	direction: emath.Vec3,
) -> (
	face: Polygon,
) {
	local := emath.quaternion_rotate(conj(orientation), direction)
	switch s in shape {
	case Sphere:
	case Capsule:
		side := emath.Vec3{local.x, 0, local.z}
		length := emath.length(side)
		if length == 0 {
			return
		}
		offset := side * (s.radius / length)
		face.points[0] = emath.Vec3{0, -s.half_height, 0} + offset
		face.points[1] = emath.Vec3{0, s.half_height, 0} + offset
		face.count = 2
	case Box:
		axis := 0
		for i in 1 ..< 3 {
			if abs(local[i]) > abs(local[axis]) {
				axis = i
			}
		}
		sign := f32(1) if local[axis] >= 0 else -1
		j, k := (axis + 1) % 3, (axis + 2) % 3
		corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
		for corner, i in corners {
			point: emath.Vec3
			point[axis] = sign * s.half_extent[axis]
			point[j] = corner[0] * s.half_extent[j]
			point[k] = corner[1] * s.half_extent[k]
			face.points[i if sign > 0 else 3 - i] = point
		}
		face.count = 4
	}

	for &point in face.points[:face.count] {
		point = emath.transform_point(position, orientation, point)
	}
	return
}

// Clips one face against the other face's side planes, then pairs each
// remaining point with its projection onto the other face. A two-point face can
// only be the clipper, so the corner counts decide the roles.
@(private)
clip_faces :: proc(
	face_a, face_b: Polygon,
	normal: emath.Vec3,
	max_separation: f32,
	center: emath.Vec3,
	manifold: ^Manifold,
) {
	polygon, clipper, outward := face_b, face_a, normal
	swapped := false
	if face_a.count >= 3 && face_b.count == 2 {
		polygon, clipper, outward = face_a, face_b, -normal
		swapped = true
	} else if face_a.count < 2 || face_b.count < 3 {
		return
	}

	clipped: Polygon
	if clipper.count >= 3 {
		clipped = clip_polygon(polygon, clipper, outward)
	} else {
		clipped = clip_polygon_edge(polygon, clipper.points[0], clipper.points[1], outward)
	}
	if clipped.count == 0 {
		return
	}

	plane_origin := clipper.points[0]
	edge := clipper.points[1] - plane_origin
	plane_normal: emath.Vec3
	if clipper.count >= 3 {
		plane_normal = emath.cross(edge, clipper.points[2] - plane_origin)
	} else {
		plane_normal = emath.cross(emath.cross(edge, outward), edge)
	}
	plane_scale := emath.dot(plane_normal, plane_normal)
	if plane_scale == 0 {
		return
	}

	pairs: [POLYGON_CAPACITY]Manifold_Point
	count := 0
	for on_polygon in clipped.points[:clipped.count] {
		height := emath.dot(on_polygon - plane_origin, plane_normal)
		on_clipper := on_polygon - plane_normal * (height / plane_scale)
		point := Manifold_Point {
			a = on_clipper,
			b = on_polygon,
		}
		if swapped {
			point.a, point.b = on_polygon, on_clipper
		}
		point.separation = emath.dot(point.b - point.a, normal)
		if point.separation > max_separation {
			continue
		}
		pairs[count] = point
		count += 1
	}

	if count > MANIFOLD_CAPACITY {
		reduce_points(pairs[:count], normal, center, manifold)
		return
	}
	for point, i in pairs[:count] {
		manifold.points[i] = point
	}
	manifold.count = count
}

// Sutherland-Hodgman clipping against the clipper's side planes. The clipper
// has to wind counter-clockwise around outward.
@(private)
clip_polygon :: proc(polygon, clipper: Polygon, outward: emath.Vec3) -> Polygon {
	result := polygon
	for i in 0 ..< clipper.count {
		start := clipper.points[i]
		end := clipper.points[(i + 1) % clipper.count]
		result = clip_polygon_plane(result, start, emath.cross(outward, end - start))
		if result.count < 3 {
			return {}
		}
	}
	return result
}

// Keeps the part of the polygon on the side plane_normal points to.
@(private)
clip_polygon_plane :: proc(
	polygon: Polygon,
	origin, plane_normal: emath.Vec3,
) -> (
	result: Polygon,
) {
	if polygon.count == 0 {
		return
	}

	previous := polygon.points[polygon.count - 1]
	previous_height := emath.dot(previous - origin, plane_normal)
	previous_inside := previous_height > 0
	for i in 0 ..< polygon.count {
		point := polygon.points[i]
		height := emath.dot(point - origin, plane_normal)
		inside := height > 0
		if inside != previous_inside {
			delta := point - previous
			slope := emath.dot(delta, plane_normal)
			if slope != 0 {
				result.points[result.count] = previous - delta * (previous_height / slope)
				result.count += 1
			} else {
				inside = previous_inside
			}
		}
		if inside {
			result.points[result.count] = point
			result.count += 1
		}
		previous, previous_height, previous_inside = point, height, inside
	}
	return
}

// Finds where the polygon's edges cross the plane through the segment, and
// clamps those points to the segment's length on the polygon.
@(private)
clip_polygon_edge :: proc(polygon: Polygon, start, end, axis: emath.Vec3) -> (result: Polygon) {
	edge := end - start
	edge_normal := emath.cross(axis, edge)
	polygon_normal := emath.cross(
		polygon.points[2] - polygon.points[0],
		polygon.points[1] - polygon.points[0],
	)
	polygon_scale := emath.dot(polygon_normal, polygon_normal)
	if polygon_scale == 0 {
		return
	}

	first :=
		start +
		polygon_normal * (emath.dot(polygon_normal, polygon.points[0] - start) / polygon_scale)
	last :=
		end + polygon_normal * (emath.dot(polygon_normal, polygon.points[0] - end) / polygon_scale)
	span := last - first
	span_scale := emath.dot(span, span)
	previous := polygon.points[polygon.count - 1]
	previous_height := emath.dot(previous - start, edge_normal)
	previous_inside := previous_height > 0
	for i in 0 ..< polygon.count {
		point := polygon.points[i]
		height := emath.dot(point - start, edge_normal)
		inside := height > 0
		if inside != previous_inside {
			delta := point - previous
			slope := emath.dot(delta, edge_normal)
			crossing := previous - delta * (previous_height / slope) if slope != 0 else previous
			along := emath.dot(crossing - first, span)
			if along < 0 {
				crossing = first
			} else if along > span_scale {
				crossing = last
			}
			result.points[result.count] = crossing
			result.count += 1
		}
		previous, previous_height, previous_inside = point, height, inside
	}
	return
}

// Keeps four points: the deepest one with the most leverage around center, the
// one farthest from it, and the farthest on each side of the line between them,
// so the area stays large.
@(private)
reduce_points :: proc(points: []Manifold_Point, normal, center: emath.Vec3, manifold: ^Manifold) {
	MIN_DISTANCE_SQ :: f32(1e-6)
	projected: [POLYGON_CAPACITY]emath.Vec3
	depth_sq: [POLYGON_CAPACITY]f32
	for point, i in points {
		arm := point.a - center
		projected[i] = arm - normal * emath.dot(arm, normal)
		gap := point.b - point.a
		depth_sq[i] = max(MIN_DISTANCE_SQ, emath.dot(gap, gap))
	}

	first := 0
	best := f32(-1)
	for arm, i in projected[:len(points)] {
		score := max(MIN_DISTANCE_SQ, emath.dot(arm, arm)) * depth_sq[i]
		if score > best {
			best, first = score, i
		}
	}
	second := -1
	best = -max(f32)
	for arm, i in projected[:len(points)] {
		if i == first {
			continue
		}
		delta := arm - projected[first]
		score := max(MIN_DISTANCE_SQ, emath.dot(delta, delta)) * depth_sq[i]
		if score > best {
			best, second = score, i
		}
	}

	third, fourth := -1, -1
	lowest, highest := f32(0), f32(0)
	side := emath.cross(projected[second] - projected[first], normal)
	for arm, i in projected[:len(points)] {
		if i == first || i == second {
			continue
		}
		offset := emath.dot(side, arm - projected[first])
		if offset < lowest {
			lowest, third = offset, i
		} else if offset > highest {
			highest, fourth = offset, i
		}
	}

	manifold.count = 0
	for index in ([4]int{first, third, second, fourth}) {
		if index == -1 {
			continue
		}
		manifold.points[manifold.count] = points[index]
		manifold.count += 1
	}
}
