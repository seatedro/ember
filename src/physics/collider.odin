package physics

import emath "../core/math"
import "../core/pool"

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

Collider_State :: struct {
	body:       Body_Handle,
	shape:      Shape,
	local_pose: emath.Pose,
	filter:     Collision_Filter,
}

@(private)
Collider :: struct {
	state:          Collider_State,
	previous, next: Collider_Handle,
	leaf:           int,
}

filters_match :: proc(a, b: Collision_Filter) -> bool {
	return a.category & b.mask != 0 && b.category & a.mask != 0
}

create_collider :: proc(
	world: ^World,
	body: Body_Handle,
	shape: Shape,
	local_pose := emath.Pose{orientation = 1},
	filter := ALL_COLLISIONS,
) -> (
	Collider_Handle,
	Error,
) {
	owner := pool.get(&world.bodies, body)
	if owner == nil {
		return {}, .Invalid_Body
	}
	if !valid_shape(shape) {
		return {}, .Invalid_Shape
	}
	if !valid_pose(local_pose) {
		return {}, .Invalid_Value
	}
	pose := local_pose
	pose.orientation = emath.quaternion_normalize(pose.orientation)
	bounds, valid := shape_bounds(shape, compose_pose(owner.state.pose, pose))
	if !valid {
		return {}, .Invalid_Value
	}

	handle, collider := pool.alloc(&world.colliders)
	if collider == nil {
		return {}, .Capacity_Exceeded
	}
	collider^ = {
		state = {body = body, shape = shape, local_pose = pose, filter = filter},
		next = owner.first_collider,
		leaf = tree_alloc(&world.tree),
	}
	if next := pool.get(&world.colliders, collider.next); next != nil {
		next.previous = handle
	}
	owner.first_collider = handle
	world.tree.nodes[collider.leaf].bounds = bounds
	world.tree.nodes[collider.leaf].collider = handle
	tree_insert(&world.tree, collider.leaf)
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
	tree_remove(&world.tree, collider.leaf)
	tree_free(&world.tree, collider.leaf)
	return pool.free(&world.colliders, handle)
}

collider_state :: proc(world: ^World, handle: Collider_Handle) -> (Collider_State, bool) {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return {}, false
	}
	return collider.state, true
}

collider_pose :: proc(
	world: ^World,
	handle: Collider_Handle,
	alpha: f32 = 1,
) -> (
	emath.Pose,
	bool,
) {
	collider := pool.get(&world.colliders, handle)
	if collider == nil {
		return {}, false
	}
	pose, ok := body_pose(world, collider.state.body, alpha)
	return compose_pose(pose, collider.state.local_pose), ok
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
	return .None
}

@(private)
valid_body_bounds :: proc(world: ^World, body: ^Body, pose: emath.Pose) -> bool {
	handle := body.first_collider
	for handle.generation != 0 {
		collider := pool.get(&world.colliders, handle)
		_, valid := shape_bounds(
			collider.state.shape,
			compose_pose(pose, collider.state.local_pose),
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
		bounds, _ := shape_bounds(
			collider.state.shape,
			compose_pose(body.state.pose, collider.state.local_pose),
		)
		if world.tree.nodes[collider.leaf].bounds != bounds {
			tree_remove(&world.tree, collider.leaf)
			world.tree.nodes[collider.leaf].bounds = bounds
			tree_insert(&world.tree, collider.leaf)
		}
		handle = collider.next
	}
}
