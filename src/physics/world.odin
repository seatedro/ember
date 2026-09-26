package physics

import emath "../core/math"
import "../core/pool"
import "base:runtime"
import "collision"

World :: struct {
	bodies:    pool.Pool(Body, Body_Handle),
	colliders: pool.Pool(Collider, Collider_Handle),
	tree:      collision.Tree(Collider_Handle),
	settings:  Solver_Settings,
	// Two contact caches: the step fills one while the other stays readable.
	// They swap only when the step succeeds, so a failed step leaves the last
	// contacts and events alone.
	caches:    [2]Contact_Cache,
	published: int,
	scratch:   Step_Scratch,
	allocator: runtime.Allocator,
}

// Working data for a single step. None of it matters once the step is over.
@(private)
Step_Scratch :: struct {
	// Same indices as the body pool's slots.
	bodies:           []Step_Body,
	constraints:      []Contact_Constraint,
	constraint_count: int,
	// Colliders whose search found room for every pair.
	searched:         []Collider_Handle,
	searched_count:   int,
	// Where each pair lives in the cache the step is filling.
	pair_index:       map[Pair_Key]int,
}

Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
	Capacity_Exceeded,
	Invalid_Body,
	Invalid_Motion_Type,
	Invalid_Mass,
	Invalid_Value,
	Invalid_Time,
	Invalid_Shape,
	Invalid_Collider,
	Query_Did_Not_Converge,
}

// collider_capacity defaults to capacity, and contact_capacity (how many
// collider pairs we track at once) defaults to collider_capacity. Nothing
// allocates after this.
create :: proc(
	capacity: int,
	allocator := context.allocator,
	collider_capacity: int = 0,
	contact_capacity: int = 0,
) -> (
	World,
	Error,
) {
	collider_count := capacity if collider_capacity == 0 else collider_capacity
	contact_count := collider_count if contact_capacity == 0 else contact_capacity
	per_contact :=
		2 * size_of(Cached_Manifold) + 4 * size_of(Contact_Event) + size_of(Contact_Constraint)
	if contact_count <= 0 || contact_count > max(int) / per_contact {
		return {}, .Invalid_Capacity
	}

	world := World {
		settings  = DEFAULT_SOLVER_SETTINGS,
		allocator = allocator,
	}
	if err := create_storage(&world, capacity, collider_count, contact_count); err != .None {
		destroy(&world)
		return {}, err
	}
	return world, .None
}

@(private)
create_storage :: proc(world: ^World, capacity, collider_count, contact_count: int) -> Error {
	allocator := world.allocator
	pool_error: pool.Error
	world.bodies, pool_error = pool.create(Body, Body_Handle, capacity, allocator)
	if pool_error == .None {
		world.colliders, pool_error = pool.create(
			Collider,
			Collider_Handle,
			collider_count,
			allocator,
		)
	}
	switch pool_error {
	case .Invalid_Capacity:
		return .Invalid_Capacity
	case .Allocation_Failed:
		return .Allocation_Failed
	case .None:
	}

	tree_error: collision.Error
	world.tree, tree_error = collision.create_tree(Collider_Handle, collider_count, allocator)
	if tree_error != .None {
		return collision_error(tree_error)
	}

	scratch := &world.scratch
	errors: [8]runtime.Allocator_Error
	for &cache, i in world.caches {
		cache.manifolds, errors[i] = make([]Cached_Manifold, contact_count, allocator)
		cache.events, errors[2 + i] = make([]Contact_Event, 2 * contact_count, allocator)
	}
	scratch.bodies, errors[4] = make([]Step_Body, capacity, allocator)
	scratch.constraints, errors[5] = make([]Contact_Constraint, contact_count, allocator)
	scratch.searched, errors[6] = make([]Collider_Handle, collider_count, allocator)
	// Maps grow at 75% full, so reserve enough that every pair fits under that.
	scratch.pair_index, errors[7] = make(
		map[Pair_Key]int,
		contact_count * 100 / runtime.MAP_LOAD_FACTOR + 1,
		allocator,
	)
	for err in errors {
		if err != .None {
			return .Allocation_Failed
		}
	}
	return .None
}

destroy :: proc(world: ^World) {
	for slot, index in world.bodies.slots {
		if slot.used {
			destroy_body(world, Body_Handle{index = u32(index), generation = slot.generation})
		}
	}
	pool.destroy(&world.bodies)
	pool.destroy(&world.colliders)
	collision.destroy_tree(&world.tree)
	for cache in world.caches {
		delete(cache.manifolds, world.allocator)
		delete(cache.events, world.allocator)
	}
	delete(world.scratch.bodies, world.allocator)
	delete(world.scratch.constraints, world.allocator)
	delete(world.scratch.searched, world.allocator)
	delete(world.scratch.pair_index)
	world^ = {}
}

// Advances the world by dt seconds. If it fails, nothing changes: bodies,
// contacts, and events stay as the last good step left them.
step :: proc(world: ^World, dt: f32) -> Error {
	if !emath.finite(dt) || dt <= 0 {
		return .Invalid_Time
	}
	if !valid_settings(world.settings) {
		return .Invalid_Value
	}

	// Apply forces, torques, and damping to get each body's velocity before
	// contacts. Kinematic bodies get the velocity that reaches their target.
	for &slot, index in world.bodies.slots {
		if !slot.used {
			continue
		}
		if err := integrate_velocity(&slot.value, &world.scratch.bodies[index], dt); err != .None {
			return err
		}
	}

	// Find and rebuild manifolds from where bodies were at the start of the
	// step, and record Begin and End events.
	update_contacts(world)

	// Turn each touching, non-sensor manifold into a constraint, including the
	// lowest normal velocity each point allows.
	prepare_contacts(world, dt)

	// Start from last step's impulses, then iterate on the velocities.
	solve_velocities(world)

	// Move bodies with the solved velocities. Kinematic bodies land on their
	// target.
	for &slot, index in world.bodies.slots {
		if !slot.used {
			continue
		}
		if err := integrate_position(&world.scratch.bodies[index], dt); err != .None {
			return err
		}
	}

	// Push apart whatever overlap is left beyond the slop.
	if err := solve_positions(world); err != .None {
		return err
	}

	// Save this step's impulses to warm start the next one.
	store_impulses(world)

	// The inertia tensor rotated with the body, so recompute angular velocity
	// from momentum at the new orientation.
	for &slot, index in world.bodies.slots {
		if !slot.used {
			continue
		}
		body := &slot.value
		body_step := &world.scratch.bodies[index]
		next := &body_step.next
		if body.motion == .Dynamic {
			body_step.next_inverse_inertia = inertia_tensor_to_world(
				body.inverse_inertia,
				next.orientation,
			)
			next.angular_velocity = body_step.next_inverse_inertia * body_step.next_momentum
		}

		if !emath.finite_vector(next.position) ||
		   !emath.valid_orientation(next.orientation) ||
		   !valid_body_bounds(world, body, next.position, next.orientation) ||
		   !emath.finite_vector(next.velocity) ||
		   !emath.finite_vector(next.angular_velocity) {
			return .Invalid_Value
		}
	}

	// Commit everything at once so every contact saw the same state.
	world.published = 1 - world.published
	for handle in world.scratch.searched[:world.scratch.searched_count] {
		pool.get(&world.colliders, handle).pending_pair_search = false
	}
	for &slot, index in world.bodies.slots {
		if !slot.used {
			continue
		}
		body := &slot.value
		body_step := &world.scratch.bodies[index]
		body.previous_position, body.previous_orientation =
			body.state.position, body.state.orientation
		body.state = body_step.next
		body.angular_momentum = body_step.next_momentum
		body.inverse_inertia_world = body_step.next_inverse_inertia
		body.force, body.torque = {}, {}
		body.has_target = false
		sync_colliders(world, body)
	}
	return .None
}

@(private)
collision_error :: proc(err: collision.Error) -> Error {
	switch err {
	case .None:
		return .None
	case .Invalid_Capacity:
		return .Invalid_Capacity
	case .Allocation_Failed:
		return .Allocation_Failed
	case .Did_Not_Converge:
		return .Query_Did_Not_Converge
	}
	return .None
}
