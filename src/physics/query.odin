package physics

import emath "../core/math"
import "../core/pool"
import "collision"

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

// The displacement sets both direction and distance, so a fraction of 1 is its
// end. A cast that starts overlapping returns fraction 0, and a zero normal
// when there's no way out. Shape casts slide the shape without rotating it.
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
		world        = world,
		filter       = filter,
		position     = origin,
		displacement = displacement,
	}
	collision.raycast_tree(&world.tree, origin, displacement, &query, visit_ray)
	return query.hit, query.found, query.error
}

cast_shape :: proc(
	world: ^World,
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	displacement: emath.Vec3,
	filter := ALL_QUERIES,
	tolerance: f32 = 0.0001,
) -> (
	Query_Hit,
	bool,
	Error,
) {
	query, bounds, err := shape_query(world, shape, position, orientation, filter, tolerance)
	if err != .None {
		return {}, false, err
	}
	if !valid_cast(position, displacement) {
		return {}, false, .Invalid_Value
	}
	end_bounds, valid := collision.shape_bounds(shape, position + displacement, orientation)
	if !valid {
		return {}, false, .Invalid_Value
	}
	query.displacement = displacement
	bounds = collision.combine_bounds(bounds, collision.expanded_bounds(end_bounds, tolerance))
	collision.query_tree(&world.tree, bounds, &query, visit_sweep)
	return query.hit, query.found, query.error
}

// Results come in no particular order. total also counts hits that didn't fit
// in output. On error, neither the results nor total are complete.
overlap_shape :: proc(
	world: ^World,
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	output: []Overlap_Hit,
	filter := ALL_QUERIES,
	tolerance: f32 = 0.0001,
) -> (
	written, total: int,
	err: Error,
) {
	query, bounds, error := shape_query(world, shape, position, orientation, filter, tolerance)
	if error != .None {
		return 0, 0, error
	}
	query.output = output
	collision.query_tree(&world.tree, bounds, &query, visit_overlap)
	return min(len(output), query.total), query.total, query.error
}

// What the tree callbacks share: the question being asked and the best answer
// so far.
@(private)
Query :: struct {
	world:        ^World,
	filter:       Query_Filter,
	shape:        Shape,
	position:     emath.Vec3,
	orientation:  emath.Quaternion,
	displacement: emath.Vec3,
	tolerance:    f32,
	hit:          Query_Hit,
	found:        bool,
	output:       []Overlap_Hit,
	total:        int,
	error:        Error,
}

@(private)
valid_cast :: proc(origin, displacement: emath.Vec3) -> bool {
	return(
		emath.finite_vector(origin) &&
		emath.finite_vector(displacement) &&
		emath.finite_vector(origin + displacement) \
	)
}

@(private)
shape_query :: proc(
	world: ^World,
	shape: Shape,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	filter: Query_Filter,
	tolerance: f32,
) -> (
	Query,
	collision.AABB,
	Error,
) {
	if !collision.valid_shape(shape) {
		return {}, {}, .Invalid_Shape
	}
	if !emath.finite(tolerance) || tolerance <= 0 {
		return {}, {}, .Invalid_Value
	}
	bounds, valid := collision.shape_bounds(shape, position, orientation)
	if !valid {
		return {}, {}, .Invalid_Value
	}
	bounds = collision.expanded_bounds(bounds, tolerance)
	if !emath.finite_vector(bounds.min) || !emath.finite_vector(bounds.max) {
		return {}, {}, .Invalid_Value
	}
	return {
			world = world,
			filter = filter,
			shape = shape,
			position = position,
			orientation = orientation,
			tolerance = tolerance,
		},
		bounds,
		.None
}

// Looks up a leaf's collider and placement, if the filter lets it through.
@(private)
admit :: proc(
	query: ^Query,
	handle: Collider_Handle,
) -> (
	collider: ^Collider,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	admitted: bool,
) {
	collider = pool.get(&query.world.colliders, handle)
	if !filters_match(collider.state.filter, query.filter.collision) {
		return nil, {}, {}, false
	}
	for body in query.filter.exclude {
		if body == collider.state.body {
			return nil, {}, {}, false
		}
	}
	position, orientation, _ = collider_position_and_orientation(query.world, handle)
	return collider, position, orientation, true
}

// The nearest hit wins. On a tie the lower collider index wins, so the result
// doesn't depend on the tree's shape.
@(private)
record_hit :: proc(
	query: ^Query,
	collider: ^Collider,
	handle: Collider_Handle,
	hit: collision.Cast_Hit,
) {
	if query.found &&
	   (hit.fraction > query.hit.fraction ||
			   (hit.fraction == query.hit.fraction && handle.index >= query.hit.collider.index)) {
		return
	}
	query.hit = {
		body                = collider.state.body,
		collider            = handle,
		position            = hit.position,
		normal              = hit.normal,
		fraction            = hit.fraction,
		started_overlapping = hit.started_overlapping,
	}
	query.found = true
}

@(private)
visit_ray :: proc(query: ^Query, handle: Collider_Handle) -> f32 {
	collider, position, orientation, admitted := admit(query, handle)
	if admitted {
		hit, found := collision.raycast(
			query.position,
			query.displacement,
			collider.state.shape,
			position,
			orientation,
		)
		if found {
			record_hit(query, collider, handle, hit)
		}
	}
	return query.hit.fraction if query.found else 1
}

@(private)
visit_sweep :: proc(query: ^Query, handle: Collider_Handle) -> bool {
	collider, position, orientation, admitted := admit(query, handle)
	if !admitted {
		return true
	}
	hit, found, err := collision.sweep(
		query.shape,
		query.position,
		query.orientation,
		query.displacement,
		collider.state.shape,
		position,
		orientation,
		query.tolerance,
	)
	if err != .None {
		query.error = collision_error(err)
		return false
	}
	if found {
		record_hit(query, collider, handle, hit)
	}
	return true
}

@(private)
visit_overlap :: proc(query: ^Query, handle: Collider_Handle) -> bool {
	collider, position, orientation, admitted := admit(query, handle)
	if !admitted {
		return true
	}
	distance, err := collision.distance(
		query.shape,
		query.position,
		query.orientation,
		collider.state.shape,
		position,
		orientation,
		query.tolerance * 0.05,
	)
	if err != .None {
		query.error = collision_error(err)
		return false
	}
	if distance.distance <= query.tolerance {
		if query.total < len(query.output) {
			query.output[query.total] = {
				body     = collider.state.body,
				collider = handle,
			}
		}
		query.total += 1
	}
	return true
}
