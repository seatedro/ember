package physics

import emath "../core/math"
import "../core/pool"
import "core:math"
import "core:math/linalg"

Body_Handle :: struct {
	index, generation: u32,
}

Motion_Type :: enum {
	Dynamic,
	Static,
	Kinematic,
}

Body_State :: struct {
	pose:                       emath.Pose,
	velocity, angular_velocity: emath.Vec3,
}

Body_Desc :: struct {
	motion:                          Motion_Type,
	state:                           Body_State,
	mass:                            Mass_Properties,
	linear_damping, angular_damping: f32,
}

World :: struct {
	bodies:    pool.Pool(Body, Body_Handle),
	colliders: pool.Pool(Collider, Collider_Handle),
	tree:      Tree,
}

@(private)
Body :: struct {
	first_collider:                  Collider_Handle,
	state:                           Body_State,
	previous:                        emath.Pose,
	next:                            Body_State,
	angular_momentum, next_momentum: emath.Vec3,
	motion:                          Motion_Type,
	inverse_mass:                    f32,
	inertia, inverse_inertia:        matrix[3, 3]f32,
	force, torque:                   emath.Vec3,
	linear_damping, angular_damping: f32,
	target:                          emath.Pose,
	has_target:                      bool,
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

create :: proc(
	capacity: int,
	allocator := context.allocator,
	collider_capacity: int = 0,
) -> (
	World,
	Error,
) {
	bodies, err := pool.create(Body, Body_Handle, capacity, allocator)
	switch err {
	case .Invalid_Capacity:
		return {}, .Invalid_Capacity
	case .Allocation_Failed:
		return {}, .Allocation_Failed
	case .None:
		count := capacity if collider_capacity == 0 else collider_capacity
		colliders, collider_error := pool.create(Collider, Collider_Handle, count, allocator)
		if collider_error != .None {
			pool.destroy(&bodies)
			return {},
				.Invalid_Capacity if collider_error == .Invalid_Capacity else .Allocation_Failed
		}
		tree, tree_error := create_tree(count, allocator)
		if tree_error != .None {
			pool.destroy(&colliders)
			pool.destroy(&bodies)
			return {}, tree_error
		}
		return {bodies = bodies, colliders = colliders, tree = tree}, .None
	}

	unreachable()
}

destroy :: proc(world: ^World) {
	for slot, index in world.bodies.slots {
		if slot.used {
			destroy_body(world, Body_Handle{index = u32(index), generation = slot.generation})
		}
	}
	pool.destroy(&world.bodies)
	pool.destroy(&world.colliders)
	delete(world.tree.nodes, world.tree.allocator)
	world^ = {}
}

create_body :: proc(world: ^World, desc: Body_Desc) -> (Body_Handle, Error) {
	if desc.motion < .Dynamic || desc.motion > .Kinematic {
		return {}, .Invalid_Motion_Type
	}
	if !valid_pose(desc.state.pose) ||
	   !finite_vector(desc.state.velocity) ||
	   !finite_vector(desc.state.angular_velocity) ||
	   !finite(desc.linear_damping) ||
	   desc.linear_damping < 0 ||
	   !finite(desc.angular_damping) ||
	   desc.angular_damping < 0 {
		return {}, .Invalid_Value
	}
	if desc.motion != .Dynamic &&
	   (desc.state.velocity != emath.Vec3{} || desc.state.angular_velocity != emath.Vec3{}) {
		return {}, .Invalid_Value
	}

	body := Body {
		motion          = desc.motion,
		state           = desc.state,
		linear_damping  = desc.linear_damping,
		angular_damping = desc.angular_damping,
	}
	body.state.pose.orientation = emath.quaternion_normalize(body.state.pose.orientation)
	body.previous = body.state.pose
	if desc.motion == .Dynamic {
		if !valid_mass(desc.mass) {
			return {}, .Invalid_Mass
		}
		body.inverse_mass = 1 / desc.mass.mass
		body.inertia = desc.mass.inertia
		body.inverse_inertia = linalg.inverse(desc.mass.inertia)
		if !finite(body.inverse_mass) {
			return {}, .Invalid_Mass
		}
		for row in 0 ..< 3 {
			for column in 0 ..< 3 {
				if !finite(body.inverse_inertia[row, column]) {
					return {}, .Invalid_Mass
				}
			}
		}
	}

	body.angular_momentum = tensor_vector(
		body.inertia,
		body.state.pose.orientation,
		body.state.angular_velocity,
	)
	if !finite_vector(body.angular_momentum) {
		return {}, .Invalid_Value
	}

	handle, stored := pool.alloc(&world.bodies)
	if stored == nil {
		return {}, .Capacity_Exceeded
	}
	stored^ = body
	return handle, .None
}

destroy_body :: proc(world: ^World, handle: Body_Handle) -> bool {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return false
	}
	for body.first_collider.generation != 0 {
		destroy_collider(world, body.first_collider)
	}
	return pool.free(&world.bodies, handle)
}

body_state :: proc(world: ^World, handle: Body_Handle) -> (Body_State, bool) {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return {}, false
	}

	return body.state, true
}

body_pose :: proc(world: ^World, handle: Body_Handle, alpha: f32 = 1) -> (emath.Pose, bool) {
	body := pool.get(&world.bodies, handle)
	if body == nil || !finite(alpha) || alpha < 0 || alpha > 1 {
		return {}, false
	}

	return emath.interpolate_pose(body.previous, body.state.pose, alpha), true
}

teleport :: proc(
	world: ^World,
	handle: Body_Handle,
	pose: emath.Pose,
	clear_velocity := false,
) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if !valid_pose(pose) {
		return .Invalid_Value
	}

	state := body.state
	state.pose = {
		position    = pose.position,
		orientation = emath.quaternion_normalize(pose.orientation),
	}
	if clear_velocity || body.motion != .Dynamic {
		state.velocity, state.angular_velocity = {}, {}
	}
	momentum := tensor_vector(body.inertia, state.pose.orientation, state.angular_velocity)
	if !finite_vector(momentum) || !valid_body_bounds(world, body, state.pose) {
		return .Invalid_Value
	}

	body.state = state
	body.previous = state.pose
	body.angular_momentum = momentum
	body.force, body.torque = {}, {}
	body.has_target = false
	sync_colliders(world, body)
	return .None
}

set_velocity :: proc(world: ^World, handle: Body_Handle, linear, angular: emath.Vec3) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if body.motion != .Dynamic {
		return .Invalid_Motion_Type
	}
	if !finite_vector(linear) || !finite_vector(angular) {
		return .Invalid_Value
	}

	momentum := tensor_vector(body.inertia, body.state.pose.orientation, angular)
	if !finite_vector(momentum) {
		return .Invalid_Value
	}
	body.state.velocity, body.state.angular_velocity = linear, angular
	body.angular_momentum = momentum
	return .None
}

move_kinematic :: proc(world: ^World, handle: Body_Handle, target: emath.Pose) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if body.motion != .Kinematic {
		return .Invalid_Motion_Type
	}
	if !valid_pose(target) {
		return .Invalid_Value
	}

	body.target = {
		position    = target.position,
		orientation = emath.quaternion_normalize(target.orientation),
	}
	body.has_target = true
	return .None
}

add_force :: proc(
	world: ^World,
	handle: Body_Handle,
	force: emath.Vec3,
	offset: emath.Vec3 = {},
) -> Error {
	return apply_load(world, handle, force, emath.cross(offset, force), false)
}

add_torque :: proc(world: ^World, handle: Body_Handle, torque: emath.Vec3) -> Error {
	return apply_load(world, handle, {}, torque, false)
}

add_impulse :: proc(
	world: ^World,
	handle: Body_Handle,
	impulse: emath.Vec3,
	offset: emath.Vec3 = {},
) -> Error {
	return apply_load(world, handle, impulse, emath.cross(offset, impulse), true)
}

add_angular_impulse :: proc(world: ^World, handle: Body_Handle, impulse: emath.Vec3) -> Error {
	return apply_load(world, handle, {}, impulse, true)
}

velocity_at :: proc(state: Body_State, point: emath.Vec3) -> emath.Vec3 {
	return state.velocity + emath.cross(state.angular_velocity, point - state.pose.position)
}

step :: proc(world: ^World, dt: f32) -> Error {
	if !finite(dt) || dt <= 0 {
		return .Invalid_Time
	}

	for &slot in world.bodies.slots {
		if !slot.used {
			continue
		}
		body := &slot.value
		state := body.state
		momentum := body.angular_momentum
		switch body.motion {
		case .Static:
		case .Kinematic:
			state.velocity, state.angular_velocity = {}, {}
			if body.has_target {
				state.velocity = (body.target.position - state.pose.position) / dt
				rotation := body.target.orientation * conj(state.pose.orientation)
				if real(rotation) < 0 {
					rotation = -rotation
				}
				axis := emath.Vec3(rotation.xyz)
				sine := emath.length(axis)
				if sine > 0 {
					state.angular_velocity =
						axis / sine * (2 * math.atan2(sine, real(rotation)) / dt)
				}
				state.pose = body.target
			}
		case .Dynamic:
			state.velocity =
				(state.velocity + body.force * (body.inverse_mass * dt)) *
				math.exp(-body.linear_damping * dt)
			state.pose.position += state.velocity * dt
			// Inertia rotates with the body. Integrating world angular momentum
			// preserves torque-free momentum even when the principal moments differ.
			new_momentum := (momentum + body.torque * dt) * math.exp(-body.angular_damping * dt)
			midpoint_momentum := (momentum + new_momentum) * 0.5
			angular := tensor_vector(
				body.inverse_inertia,
				state.pose.orientation,
				midpoint_momentum,
			)
			midpoint, midpoint_ok := advance_orientation(state.pose.orientation, angular, dt * 0.5)
			if !midpoint_ok {
				return .Invalid_Value
			}
			angular = tensor_vector(body.inverse_inertia, midpoint, midpoint_momentum)
			orientation, orientation_ok := advance_orientation(state.pose.orientation, angular, dt)
			if !orientation_ok {
				return .Invalid_Value
			}
			state.pose.orientation = orientation
			state.angular_velocity = tensor_vector(
				body.inverse_inertia,
				state.pose.orientation,
				new_momentum,
			)
			momentum = new_momentum
		}
		if !valid_pose(state.pose) ||
		   !valid_body_bounds(world, body, state.pose) ||
		   !finite_vector(state.velocity) ||
		   !finite_vector(state.angular_velocity) {
			return .Invalid_Value
		}

		body.next = state
		body.next_momentum = momentum
	}

	for &slot in world.bodies.slots {
		if !slot.used {
			continue
		}
		body := &slot.value
		body.previous = body.state.pose
		body.state = body.next
		body.angular_momentum = body.next_momentum
		body.force, body.torque = {}, {}
		body.has_target = false
		sync_colliders(world, body)
	}
	return .None
}

@(private)
apply_load :: proc(
	world: ^World,
	handle: Body_Handle,
	linear, angular: emath.Vec3,
	impulse: bool,
) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if body.motion != .Dynamic {
		return .Invalid_Motion_Type
	}

	if impulse {
		velocity := body.state.velocity + linear * body.inverse_mass
		momentum := body.angular_momentum + angular
		angular_velocity := tensor_vector(
			body.inverse_inertia,
			body.state.pose.orientation,
			momentum,
		)
		if !finite_vector(velocity) ||
		   !finite_vector(angular_velocity) ||
		   !finite_vector(momentum) {
			return .Invalid_Value
		}
		body.state.velocity, body.state.angular_velocity = velocity, angular_velocity
		body.angular_momentum = momentum
	} else {
		force, torque := body.force + linear, body.torque + angular
		if !finite_vector(force) || !finite_vector(torque) {
			return .Invalid_Value
		}
		body.force, body.torque = force, torque
	}
	return .None
}

@(private)
tensor_vector :: proc(
	tensor: matrix[3, 3]f32,
	orientation: emath.Quaternion,
	vector: emath.Vec3,
) -> emath.Vec3 {
	local := emath.quaternion_rotate(conj(orientation), vector)
	return emath.quaternion_rotate(orientation, tensor * local)
}

@(private)
finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

@(private)
finite_vector :: proc(value: emath.Vec3) -> bool {
	return finite(value.x) && finite(value.y) && finite(value.z)
}

valid_pose :: proc(pose: emath.Pose) -> bool {
	magnitude := abs(pose.orientation)
	return finite_vector(pose.position) && finite(magnitude) && magnitude > 0
}

@(private)
advance_orientation :: proc(
	orientation: emath.Quaternion,
	angular: emath.Vec3,
	dt: f32,
) -> (
	emath.Quaternion,
	bool,
) {
	speed := emath.length(angular)
	if !finite(speed) || !finite(speed * dt) {
		return {}, false
	}
	if speed == 0 {
		return orientation, true
	}

	rotation := emath.quaternion_angle_axis(speed * dt, angular / speed)
	return emath.quaternion_normalize(rotation * orientation), true
}
