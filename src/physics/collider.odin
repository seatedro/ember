package physics

import emath "../core/math"
import "../core/pool"
import "collision"

// The shape types live in collision; these aliases let callers write
// physics.Box and the rest.
Shape :: collision.Shape
Sphere :: collision.Sphere
Box :: collision.Box
Capsule :: collision.Capsule

Collider_Handle :: struct {
	index, generation: u32,
}

Collision_Filter :: struct {
	category, mask: u32,
}

ALL_COLLISIONS :: Collision_Filter {
	category = 1,
	mask     = 0xffff_ffff,
}

Collider_Material :: struct {
	friction, restitution: f32,
}

DEFAULT_MATERIAL :: Collider_Material {
	friction    = 0.6,
	restitution = 0,
}

// local_position and local_orientation place the shape relative to its body.
Collider_State :: struct {
	body:              Body_Handle,
	shape:             Shape,
	local_position:    emath.Vec3,
	local_orientation: emath.Quaternion,
	filter:            Collision_Filter,
	material:          Collider_Material,
	// Sensors report contacts but don't push back.
	sensor:            bool,
}

@(private)
Collider :: struct {
	state:               Collider_State,
	previous, next:      Collider_Handle,
	proxy:               int,
	// Set when the collider is created, moves, or gets a new filter. Cleared
	// once a step has looked for its new neighbors.
	pending_pair_search: bool,
}

filters_match :: proc(a, b: Collision_Filter) -> bool {
	return a.category & b.mask != 0 && b.category & a.mask != 0
}

create_collider :: proc(
	world: ^World,
	body: Body_Handle,
	shape: Shape,
	local_position := emath.Vec3{},
	local_orientation := emath.Quaternion(1),
	filter := ALL_COLLISIONS,
	material := DEFAULT_MATERIAL,
	sensor := false,
) -> (
	Collider_Handle,
	Error,
) {
	owner := pool.get(&world.bodies, body)
	if owner == nil {
		return {}, .Invalid_Body
	}
	if !collision.valid_shape(shape) {
		return {}, .Invalid_Shape
	}
	if !emath.finite_vector(local_position) ||
	   !emath.valid_orientation(local_orientation) ||
	   !valid_collider_material(material) {
		return {}, .Invalid_Value
	}
	orientation := emath.quaternion_normalize(local_orientation)
	world_position, world_orientation := compose(
		owner.state.position,
		owner.state.orientation,
		local_position,
		orientation,
	)
	bounds, valid := collision.shape_bounds(shape, world_position, world_orientation)
	if !valid {
		return {}, .Invalid_Value
	}

	handle, collider := pool.alloc(&world.colliders)
	if collider == nil {
		return {}, .Capacity_Exceeded
	}
	collider^ = {
		state = {
			body = body,
			shape = shape,
			local_position = local_position,
			local_orientation = orientation,
			filter = filter,
			material = material,
			sensor = sensor,
		},
		next = owner.first_collider,
		proxy = collision.create_proxy(&world.tree, bounds, handle),
		pending_pair_search = true,
	}
	if next := pool.get(&world.colliders, collider.next); next != nil {
		next.previous = handle
	}
	owner.first_collider = handle
	return handle, .None
}

destroy_collider :: proc(world: ^World, handle: Collider_Handle) -> bool {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return false
	}
	owner := pool.get(&world.bodies, collider.state.body)
	if previous := pool.get(&world.colliders, collider.previous); previous != nil {
		previous.next = collider.next
	} else {
		owner.first_collider = collider.next
	}
	if next := pool.get(&world.colliders, collider.next); next != nil {
		next.previous = collider.previous
	}
	collision.destroy_proxy(&world.tree, collider.proxy)
	return pool.free(&world.colliders, handle)
}

collider_state :: proc(world: ^World, handle: Collider_Handle) -> (Collider_State, bool) {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return {}, false
	}
	return collider.state, true
}

// Where the shape is in the world, interpolated the same way as its body.
collider_position_and_orientation :: proc(
	world: ^World,
	handle: Collider_Handle,
	alpha: f32 = 1,
) -> (
	position: emath.Vec3,
	orientation: emath.Quaternion,
	ok: bool,
) {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return {}, {}, false
	}
	body_position, body_orientation, valid := body_position_and_orientation(
		world,
		collider.state.body,
		alpha,
	)
	position, orientation = compose(
		body_position,
		body_orientation,
		collider.state.local_position,
		collider.state.local_orientation,
	)
	return position, orientation, valid
}

set_collider_filter :: proc(
	world: ^World,
	handle: Collider_Handle,
	filter: Collision_Filter,
) -> Error {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return .Invalid_Collider
	}
	collider.state.filter = filter
	collider.pending_pair_search = true
	return .None
}

set_collider_material :: proc(
	world: ^World,
	handle: Collider_Handle,
	material: Collider_Material,
) -> Error {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return .Invalid_Collider
	}
	if !valid_collider_material(material) {
		return .Invalid_Value
	}

	collider.state.material = material
	return .None
}

@(private)
valid_collider_material :: proc(material: Collider_Material) -> bool {
	return(
		emath.finite(material.friction) &&
		material.friction >= 0 &&
		emath.finite(material.restitution) &&
		material.restitution >= 0 &&
		material.restitution <= 1 \
	)
}

@(private)
valid_body_bounds :: proc(
	world: ^World,
	body: ^Body,
	position: emath.Vec3,
	orientation: emath.Quaternion,
) -> bool {
	handle := body.first_collider
	for handle.generation != 0 {
		collider := pool.get(&world.colliders, handle)
		_, valid := collision.shape_bounds(
			collider.state.shape,
			collider_placement(collider, position, orientation),
		)
		if !valid {
			return false
		}
		handle = collider.next
	}
	return true
}

@(private)
sync_colliders :: proc(world: ^World, body: ^Body) {
	handle := body.first_collider
	for handle.generation != 0 {
		collider := pool.get(&world.colliders, handle)
		bounds, _ := collision.shape_bounds(
			collider.state.shape,
			collider_placement(collider, body.state.position, body.state.orientation),
		)
		if collision.move_proxy(&world.tree, collider.proxy, bounds) {
			collider.pending_pair_search = true
		}
		handle = collider.next
	}
}

// The collider's world position and orientation, given its body's.
@(private)
collider_placement :: proc(
	collider: ^Collider,
	body_position: emath.Vec3,
	body_orientation: emath.Quaternion,
) -> (
	emath.Vec3,
	emath.Quaternion,
) {
	return compose(
		body_position,
		body_orientation,
		collider.state.local_position,
		collider.state.local_orientation,
	)
}

@(private)
compose :: proc(
	parent_position: emath.Vec3,
	parent_orientation: emath.Quaternion,
	local_position: emath.Vec3,
	local_orientation: emath.Quaternion,
) -> (
	emath.Vec3,
	emath.Quaternion,
) {
	return emath.transform_point(
		parent_position,
		parent_orientation,
		local_position,
	), emath.quaternion_normalize(parent_orientation * local_orientation)
}
