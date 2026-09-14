package physics

import emath "../core/math"
import "../core/pool"

Query_Filter :: struct {
	collision: Collision_Filter,
	exclude:   []Body_Handle,
}

ALL_QUERIES :: Query_Filter {
	collision = {category = 0xffff_ffff, mask = 0xffff_ffff},
}

Query_Hit :: struct {
	body:                Body_Handle,
	collider:            Collider_Handle,
	position, normal:    emath.Vec3,
	fraction:            f32,
	started_overlapping: bool,
}

Overlap_Hit :: struct {
	body:     Body_Handle,
	collider: Collider_Handle,
}

// Cast displacement includes distance. A fraction of one is its endpoint.
// Initial overlaps return fraction zero and a zero normal when no separating
// direction exists. Shape casts translate without rotating the query shape.
cast_ray :: proc(
	world: ^World,
	origin, displacement: emath.Vec3,
	filter := ALL_QUERIES,
) -> (
	Query_Hit,
	bool,
	Error,
) {
	if !valid_cast(origin, displacement) {
		return {}, false, .Invalid_Value
	}
	query := Query {
		kind         = .Ray,
		origin       = origin,
		displacement = displacement,
		filter       = filter,
	}
	visit_query(world, world.tree.root, &query)
	return query.hit, query.found, query.error
}

cast_shape :: proc(
	world: ^World,
	shape: Shape,
	pose: emath.Pose,
	displacement: emath.Vec3,
	filter := ALL_QUERIES,
	tolerance: f32 = 0.0001,
) -> (
	Query_Hit,
	bool,
	Error,
) {
	query, err := shape_query(shape, pose, filter, tolerance)
	if err != .None {
		return {}, false, err
	}
	if !valid_cast(pose.position, displacement) {
		return {}, false, .Invalid_Value
	}
	end_bounds, valid := shape_bounds(
		shape,
		{position = pose.position + displacement, orientation = pose.orientation},
	)
	if !valid {
		return {}, false, .Invalid_Value
	}
	query.kind = .Sweep
	query.displacement = displacement
	query.bounds = combine_bounds(query.bounds, expanded_bounds(end_bounds, tolerance))
	visit_query(world, world.tree.root, &query)
	return query.hit, query.found, query.error
}

// Results are unordered. total includes hits beyond the caller's output slice;
// an error means neither the partial results nor total describe a complete query.
overlap_shape :: proc(
	world: ^World,
	shape: Shape,
	pose: emath.Pose,
	output: []Overlap_Hit,
	filter := ALL_QUERIES,
	tolerance: f32 = 0.0001,
) -> (
	written, total: int,
	err: Error,
) {
	query, error := shape_query(shape, pose, filter, tolerance)
	if error != .None {
		return 0, 0, error
	}
	query.kind = .Overlap
	query.output = output
	visit_query(world, world.tree.root, &query)
	return min(len(output), query.total), query.total, query.error
}

@(private)
Query :: struct {
	kind:                 enum {
		Ray,
		Sweep,
		Overlap,
	},
	origin, displacement: emath.Vec3,
	shape:                Convex,
	bounds:               AABB,
	tolerance:            f32,
	filter:               Query_Filter,
	hit:                  Query_Hit,
	found:                bool,
	output:               []Overlap_Hit,
	total:                int,
	error:                Error,
}

@(private)
valid_cast :: proc(origin, displacement: emath.Vec3) -> bool {
	return(
		finite_vector(origin) &&
		finite_vector(displacement) &&
		finite_vector(origin + displacement) \
	)
}

@(private)
shape_query :: proc(
	shape: Shape,
	pose: emath.Pose,
	filter: Query_Filter,
	tolerance: f32,
) -> (
	Query,
	Error,
) {
	if !valid_shape(shape) {
		return {}, .Invalid_Shape
	}
	if !finite(tolerance) || tolerance <= 0 {
		return {}, .Invalid_Value
	}
	bounds, valid := shape_bounds(shape, pose)
	if !valid {
		return {}, .Invalid_Value
	}
	bounds = expanded_bounds(bounds, tolerance)
	if !finite_vector(bounds.min) || !finite_vector(bounds.max) {
		return {}, .Invalid_Value
	}
	return {
			origin = pose.position,
			shape = convex(shape, pose, pose.position),
			bounds = bounds,
			tolerance = tolerance,
			filter = filter,
		},
		.None
}

@(private)
visit_query :: proc(world: ^World, index: int, query: ^Query) {
	if index == -1 || query.error != .None {
		return
	}
	node := &world.tree.nodes[index]
	if query.kind == .Ray {
		if !ray_bounds(
			query.origin,
			query.displacement,
			node.bounds,
			query.hit.fraction if query.found else 1,
		) {
			return
		}
	} else if !bounds_overlap(query.bounds, node.bounds) {
		return
	}
	if node.height > 0 {
		visit_query(world, node.children[0], query)
		visit_query(world, node.children[1], query)
		return
	}
	collider := pool.get(&world.colliders, node.collider)
	if !filters_match(collider.state.filter, query.filter.collision) {
		return
	}
	for body in query.filter.exclude {
		if body == collider.state.body {
			return
		}
	}
	pose, _ := collider_pose(world, node.collider)
	hit := Query_Hit {
		body     = collider.state.body,
		collider = node.collider,
	}
	found := false
	switch query.kind {
	case .Ray:
		hit.fraction, hit.normal, hit.started_overlapping, found = ray_shape(
			query.origin,
			query.displacement,
			collider.state.shape,
			pose,
		)
		hit.position = query.origin + query.displacement * hit.fraction
	case .Overlap:
		target := convex(collider.state.shape, pose, query.origin)
		distance, err := convex_distance(query.shape, target, f64(query.tolerance) * 0.05)
		query.error = err
		if err == .None && distance.distance <= f64(query.tolerance) {
			if query.total < len(query.output) {
				query.output[query.total] = {
					body     = hit.body,
					collider = hit.collider,
				}
			}
			query.total += 1
		}
		return
	case .Sweep:
		target := convex(collider.state.shape, pose, query.origin)
		hit.fraction, hit.position, hit.normal, hit.started_overlapping, found, query.error =
			sweep_convex(query.shape, target, query.displacement, query.tolerance)
		hit.position += query.origin
	}
	if found &&
	   (!query.found ||
			   hit.fraction < query.hit.fraction ||
			   (hit.fraction == query.hit.fraction &&
					   hit.collider.index < query.hit.collider.index)) {
		query.hit, query.found = hit, true
	}
}

// Advance to the separating plane along the closest-point normal. This bounds
// safe translation without stepping over thin obstacles between samples.
@(private)
sweep_convex :: proc(
	a, b: Convex,
	displacement: emath.Vec3,
	tolerance: f32,
) -> (
	f32,
	emath.Vec3,
	emath.Vec3,
	bool,
	bool,
	Error,
) {
	fraction := f64(0)
	delta := cast([3]f64)(displacement)
	normal: [3]f64
	for iteration in 0 ..< 128 {
		moving := a
		moving.center += delta * fraction
		distance, err := convex_distance(moving, b, f64(tolerance) * 0.05)
		if err != .None {
			return 0, {}, {}, false, false, err
		}
		if distance.distance <= f64(tolerance) {
			return f32(fraction),
				emath.Vec3(distance.b),
				emath.Vec3(normal),
				fraction == 0,
				true,
				.None
		}
		normal = distance.normal
		closing := -dot64(normal, delta)
		if closing <= 0 {
			return 0, {}, {}, false, false, .None
		}
		advance := (distance.distance - f64(tolerance) * 0.25) / closing
		if fraction + advance > 1 {
			return 0, {}, {}, false, false, .None
		}
		if fraction + advance <= fraction {
			return 0, {}, {}, false, false, .Query_Did_Not_Converge
		}
		fraction += advance
	}
	return 0, {}, {}, false, false, .Query_Did_Not_Converge
}
