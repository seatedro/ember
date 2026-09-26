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
	position:                   emath.Vec3,
	orientation:                emath.Quaternion,
	velocity, angular_velocity: emath.Vec3,
}

Body_Desc :: struct {
	motion:                          Motion_Type,
	state:                           Body_State,
	mass:                            Mass_Properties,
	linear_damping, angular_damping: f32,
}

@(private)
Body :: struct {
	first_collider:                  Collider_Handle,
	state:                           Body_State,
	previous_position:               emath.Vec3,
	previous_orientation:            emath.Quaternion,
	angular_momentum:                emath.Vec3,
	motion:                          Motion_Type,
	inverse_mass:                    f32,
	inertia, inverse_inertia:        emath.Mat3,
	// Update this whenever state.orientation changes.
	inverse_inertia_world:           emath.Mat3,
	force, torque:                   emath.Vec3,
	linear_damping, angular_damping: f32,
	target_position:                 emath.Vec3,
	target_orientation:              emath.Quaternion,
	has_target:                      bool,
}

// What the current step computes for a body. It's only copied back if the whole
// step succeeds.
@(private)
Step_Body :: struct {
	body:                 ^Body,
	next:                 Body_State,
	next_momentum:        emath.Vec3,
	next_inverse_inertia: emath.Mat3,
}

create_body :: proc(world: ^World, desc: Body_Desc) -> (Body_Handle, Error) {
	if desc.motion < .Dynamic || desc.motion > .Kinematic {
		return {}, .Invalid_Motion_Type
	}
	if !emath.finite_vector(desc.state.position) ||
	   !emath.valid_orientation(desc.state.orientation) ||
	   !emath.finite_vector(desc.state.velocity) ||
	   !emath.finite_vector(desc.state.angular_velocity) ||
	   !emath.finite(desc.linear_damping) ||
	   desc.linear_damping < 0 ||
	   !emath.finite(desc.angular_damping) ||
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
	body.state.orientation = emath.quaternion_normalize(body.state.orientation)
	body.previous_position, body.previous_orientation = body.state.position, body.state.orientation

	if desc.motion == .Dynamic {
		if !valid_mass(desc.mass) {
			return {}, .Invalid_Mass
		}
		body.inverse_mass = 1 / desc.mass.mass
		body.inertia = desc.mass.inertia
		body.inverse_inertia = linalg.inverse(desc.mass.inertia)
		if !emath.finite(body.inverse_mass) {
			return {}, .Invalid_Mass
		}
		for row in 0 ..< 3 {
			for column in 0 ..< 3 {
				if !emath.finite(body.inverse_inertia[row, column]) {
					return {}, .Invalid_Mass
				}
			}
		}
		body.inverse_inertia_world = inertia_tensor_to_world(
			body.inverse_inertia,
			body.state.orientation,
		)
	}

	body.angular_momentum =
		inertia_tensor_to_world(body.inertia, body.state.orientation) * body.state.angular_velocity
	if !emath.finite_vector(body.angular_momentum) {
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

// alpha blends from the previous step (0) to the latest one (1).
body_position_and_orientation :: proc(
	world: ^World,
	handle: Body_Handle,
	alpha: f32 = 1,
) -> (
	position: emath.Vec3,
	orientation: emath.Quaternion,
	ok: bool,
) {
	body := pool.get(&world.bodies, handle)
	if body == nil || !emath.finite(alpha) || alpha < 0 || alpha > 1 {
		return {}, {}, false
	}

	return math.lerp(body.previous_position, body.state.position, alpha),
		emath.quaternion_slerp(body.previous_orientation, body.state.orientation, alpha),
		true
}

teleport :: proc(
	world: ^World,
	handle: Body_Handle,
	position: emath.Vec3,
	orientation: emath.Quaternion,
	clear_velocity := false,
) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if !emath.finite_vector(position) || !emath.valid_orientation(orientation) {
		return .Invalid_Value
	}

	state := body.state
	state.position = position
	state.orientation = emath.quaternion_normalize(orientation)
	if clear_velocity || body.motion != .Dynamic {
		state.velocity, state.angular_velocity = {}, {}
	}
	momentum := inertia_tensor_to_world(body.inertia, state.orientation) * state.angular_velocity
	if !emath.finite_vector(momentum) ||
	   !valid_body_bounds(world, body, state.position, state.orientation) {
		return .Invalid_Value
	}

	body.state = state
	body.previous_position, body.previous_orientation = state.position, state.orientation
	body.angular_momentum = momentum
	body.inverse_inertia_world = inertia_tensor_to_world(body.inverse_inertia, state.orientation)
	body.force, body.torque = {}, {}
	body.has_target = false
	sync_colliders(world, body)
	return .None
}

set_velocity :: proc(world: ^World, handle: Body_Handle, linear, angular: emath.Vec3) -> Error {
	body, err := dynamic_body(world, handle)
	if err != .None {
		return err
	}
	if !emath.finite_vector(linear) || !emath.finite_vector(angular) {
		return .Invalid_Value
	}

	momentum := inertia_tensor_to_world(body.inertia, body.state.orientation) * angular
	if !emath.finite_vector(momentum) {
		return .Invalid_Value
	}
	body.state.velocity, body.state.angular_velocity = linear, angular
	body.angular_momentum = momentum
	return .None
}

// The body gets to the target by the end of the next step, however fast that
// needs to be.
move_kinematic :: proc(
	world: ^World,
	handle: Body_Handle,
	position: emath.Vec3,
	orientation: emath.Quaternion,
) -> Error {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return .Invalid_Body
	}
	if body.motion != .Kinematic {
		return .Invalid_Motion_Type
	}
	if !emath.finite_vector(position) || !emath.valid_orientation(orientation) {
		return .Invalid_Value
	}

	body.target_position = position
	body.target_orientation = emath.quaternion_normalize(orientation)
	body.has_target = true
	return .None
}

add_force :: proc(
	world: ^World,
	handle: Body_Handle,
	force: emath.Vec3,
	offset: emath.Vec3 = {},
) -> Error {
	return add_body_force(world, handle, force, emath.cross(offset, force))
}

add_torque :: proc(world: ^World, handle: Body_Handle, torque: emath.Vec3) -> Error {
	return add_body_force(world, handle, {}, torque)
}

add_impulse :: proc(
	world: ^World,
	handle: Body_Handle,
	impulse: emath.Vec3,
	offset: emath.Vec3 = {},
) -> Error {
	return add_body_impulse(world, handle, impulse, emath.cross(offset, impulse))
}

add_angular_impulse :: proc(world: ^World, handle: Body_Handle, impulse: emath.Vec3) -> Error {
	return add_body_impulse(world, handle, {}, impulse)
}

velocity_at :: proc(state: Body_State, point: emath.Vec3) -> emath.Vec3 {
	return state.velocity + emath.cross(state.angular_velocity, point - state.position)
}

@(private)
integrate_velocity :: proc(body: ^Body, step: ^Step_Body, dt: f32) -> Error {
	step^ = {
		body                 = body,
		next                 = body.state,
		next_momentum        = body.angular_momentum,
		next_inverse_inertia = body.inverse_inertia_world,
	}

	switch body.motion {
	case .Static:
	case .Kinematic:
		step.next.velocity, step.next.angular_velocity = {}, {}
		if body.has_target {
			step.next.velocity = (body.target_position - body.state.position) / dt
			rotation := body.target_orientation * conj(body.state.orientation)
			if real(rotation) < 0 {
				rotation = -rotation
			}
			axis := emath.Vec3(rotation.xyz)
			sine := emath.length(axis)
			if sine > 0 {
				step.next.angular_velocity =
					axis / sine * (2 * math.atan2(sine, real(rotation)) / dt)
			}
		}
	case .Dynamic:
		step.next.velocity =
			(body.state.velocity + body.force * (body.inverse_mass * dt)) *
			math.exp(-body.linear_damping * dt)
		step.next_momentum =
			(body.angular_momentum + body.torque * dt) * math.exp(-body.angular_damping * dt)
		step.next.angular_velocity = body.inverse_inertia_world * step.next_momentum
	}
	if !emath.finite_vector(step.next.velocity) ||
	   !emath.finite_vector(step.next.angular_velocity) {
		return .Invalid_Value
	}
	return .None
}

@(private)
integrate_position :: proc(step: ^Step_Body, dt: f32) -> Error {
	body := step.body
	switch body.motion {
	case .Static:
	case .Kinematic:
		if body.has_target {
			step.next.position, step.next.orientation =
				body.target_position, body.target_orientation
		}
	case .Dynamic:
		// Contacts changed the angular velocity, so turn it back into momentum
		// before rotating.
		orientation := body.state.orientation
		momentum := inertia_tensor_to_world(body.inertia, orientation) * step.next.angular_velocity
		if !emath.finite_vector(momentum) {
			return .Invalid_Value
		}
		step.next_momentum = momentum
		step.next.position += step.next.velocity * dt

		// Inertia turns with the body. Integrating angular momentum in world
		// space keeps a free-spinning body's momentum steady, even when its
		// moments of inertia differ.
		angular := body.inverse_inertia_world * momentum
		midpoint, midpoint_ok := advance_orientation(orientation, angular, dt * 0.5)
		if !midpoint_ok {
			return .Invalid_Value
		}
		angular = inertia_tensor_to_world(body.inverse_inertia, midpoint) * momentum
		next, next_ok := advance_orientation(orientation, angular, dt)
		if !next_ok {
			return .Invalid_Value
		}
		step.next.orientation = next
	}
	return .None
}

@(private)
dynamic_body :: proc(world: ^World, handle: Body_Handle) -> (^Body, Error) {
	body := pool.get(&world.bodies, handle)
	if body == nil {
		return nil, .Invalid_Body
	}
	if body.motion != .Dynamic {
		return nil, .Invalid_Motion_Type
	}
	return body, .None
}

// Forces add up until the next step uses and clears them.
@(private)
add_body_force :: proc(world: ^World, handle: Body_Handle, force, torque: emath.Vec3) -> Error {
	body, err := dynamic_body(world, handle)
	if err != .None {
		return err
	}

	total_force, total_torque := body.force + force, body.torque + torque
	if !emath.finite_vector(total_force) || !emath.finite_vector(total_torque) {
		return .Invalid_Value
	}
	body.force, body.torque = total_force, total_torque
	return .None
}

// Impulses change momentum right away, and velocity is recomputed from it.
@(private)
add_body_impulse :: proc(
	world: ^World,
	handle: Body_Handle,
	impulse, angular_impulse: emath.Vec3,
) -> Error {
	body, err := dynamic_body(world, handle)
	if err != .None {
		return err
	}

	velocity := body.state.velocity + impulse * body.inverse_mass
	angular_momentum := body.angular_momentum + angular_impulse
	angular_velocity := body.inverse_inertia_world * angular_momentum
	if !emath.finite_vector(velocity) ||
	   !emath.finite_vector(angular_velocity) ||
	   !emath.finite_vector(angular_momentum) {
		return .Invalid_Value
	}
	body.state.velocity, body.state.angular_velocity = velocity, angular_velocity
	body.angular_momentum = angular_momentum
	return .None
}

@(private)
inertia_tensor_to_world :: proc(tensor: emath.Mat3, orientation: emath.Quaternion) -> emath.Mat3 {
	rotation := emath.rotation_matrix3(orientation)
	return rotation * tensor * linalg.transpose(rotation)
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
	if !emath.finite(speed) || !emath.finite(speed * dt) {
		return {}, false
	}
	if speed == 0 {
		return orientation, true
	}

	rotation := emath.quaternion_angle_axis(speed * dt, angular / speed)
	return emath.quaternion_normalize(rotation * orientation), true
}
