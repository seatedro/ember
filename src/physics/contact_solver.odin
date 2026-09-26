package physics

import emath "../core/math"
import "collision"

// Settings for the sequential impulse solver. Velocity iterations stop bodies
// from moving into each other and apply friction; position iterations push out
// leftover overlap, a baumgarte fraction at a time. penetration_slop is how
// much overlap we allow before pushing, which stops jitter. Points within
// warm_start_distance of last step's points reuse their impulses.
Solver_Settings :: struct {
	velocity_iterations, position_iterations: int,
	baumgarte:                                f32,
	penetration_slop:                         f32,
	max_penetration_correction:               f32,
	speculative_distance:                     f32,
	restitution_threshold:                    f32,
	warm_start_distance:                      f32,
}

DEFAULT_SOLVER_SETTINGS :: Solver_Settings {
	velocity_iterations        = 10,
	position_iterations        = 2,
	baumgarte                  = 0.2,
	penetration_slop           = 0.02,
	max_penetration_correction = 0.2,
	speculative_distance       = 0.02,
	restitution_threshold      = 1,
	warm_start_distance        = 0.01,
}

// The solver's copy of a touching manifold, rebuilt every step. Anchors are
// world-space offsets from each body's position at the start of the step.
@(private)
Contact_Constraint :: struct {
	a, b:                  ^Step_Body,
	normal:                emath.Vec3,
	tangents:              [2]emath.Vec3,
	friction, restitution: f32,
	points:                [collision.MANIFOLD_CAPACITY]Constraint_Point,
	count:                 int,
}

@(private)
Constraint_Point :: struct {
	cache:              ^Cached_Point,
	anchor_a, anchor_b: emath.Vec3,
	normal_mass:        f32,
	tangent_mass:       [2]f32,
	velocity_bias:      f32,
	normal_impulse:     f32,
	tangent_impulse:    [2]f32,
}

@(private)
valid_settings :: proc(settings: Solver_Settings) -> bool {
	return(
		settings.velocity_iterations >= 0 &&
		settings.position_iterations >= 0 &&
		emath.finite(settings.baumgarte) &&
		settings.baumgarte >= 0 &&
		settings.baumgarte <= 1 &&
		emath.finite(settings.penetration_slop) &&
		settings.penetration_slop >= 0 &&
		emath.finite(settings.max_penetration_correction) &&
		settings.max_penetration_correction > 0 &&
		emath.finite(settings.speculative_distance) &&
		settings.speculative_distance > 0 &&
		emath.finite(settings.restitution_threshold) &&
		settings.restitution_threshold >= 0 &&
		emath.finite(settings.warm_start_distance) &&
		settings.warm_start_distance >= 0 \
	)
}

// There's always room: the scratch has one constraint per manifold slot.
@(private)
prepare_contacts :: proc(world: ^World, dt: f32) {
	scratch := &world.scratch
	scratch.constraint_count = 0
	settings := world.settings
	cache := unpublished_cache(world)
	for &manifold in cache.manifolds[:cache.manifold_count] {
		if !manifold.touching || manifold.sensor {
			continue
		}
		a := &scratch.bodies[manifold.body_a.index]
		b := &scratch.bodies[manifold.body_b.index]
		constraint := &scratch.constraints[scratch.constraint_count]
		scratch.constraint_count += 1
		constraint^ = {
			a           = a,
			b           = b,
			normal      = manifold.normal,
			tangents    = tangent_basis(manifold.normal),
			friction    = manifold.friction,
			restitution = manifold.restitution,
			count       = manifold.count,
		}

		state_a, state_b := a.body.state, b.body.state
		for &cached, i in manifold.points[:manifold.count] {
			point := &constraint.points[i]
			world_a := emath.transform_point(state_a.position, state_a.orientation, cached.local_a)
			world_b := emath.transform_point(state_b.position, state_b.orientation, cached.local_b)
			center := (world_a + world_b) * 0.5
			point.cache = &cached
			point.anchor_a = center - state_a.position
			point.anchor_b = center - state_b.position
			point.normal_impulse = cached.normal_impulse
			point.tangent_impulse = cached.tangent_impulse
			point.normal_mass = effective_mass(
				a,
				b,
				point.anchor_a,
				point.anchor_b,
				constraint.normal,
			)
			for t in 0 ..< 2 {
				point.tangent_mass[t] = effective_mass(
					a,
					b,
					point.anchor_a,
					point.anchor_b,
					constraint.tangents[t],
				)
			}

			// velocity_bias is the lowest normal velocity we allow. A point
			// with a gap can close it this step but no further. A fast hit that
			// would land this step bounces instead.
			speculative := max(0, cached.separation / dt)
			point.velocity_bias = -speculative
			normal_velocity := emath.dot(
				relative_velocity(a, b, point.anchor_a, point.anchor_b),
				constraint.normal,
			)
			if constraint.restitution > 0 &&
			   normal_velocity < -settings.restitution_threshold &&
			   normal_velocity < -speculative {
				point.velocity_bias = -constraint.restitution * normal_velocity
			}
		}
	}
}

@(private)
solve_velocities :: proc(world: ^World) {
	constraints := world.scratch.constraints[:world.scratch.constraint_count]
	for &constraint in constraints {
		for &point in constraint.points[:constraint.count] {
			apply_impulse(
				&constraint,
				&point,
				constraint.normal * point.normal_impulse +
				constraint.tangents[0] * point.tangent_impulse[0] +
				constraint.tangents[1] * point.tangent_impulse[1],
			)
		}
	}

	for _ in 0 ..< world.settings.velocity_iterations {
		for &constraint in constraints {
			for &point in constraint.points[:constraint.count] {
				solve_point(&constraint, &point)
			}
		}
	}
}

@(private)
solve_point :: proc(constraint: ^Contact_Constraint, point: ^Constraint_Point) {
	a, b := constraint.a, constraint.b
	for t in 0 ..< 2 {
		tangent := constraint.tangents[t]
		tangent_velocity := emath.dot(
			relative_velocity(a, b, point.anchor_a, point.anchor_b),
			tangent,
		)
		limit := constraint.friction * point.normal_impulse
		total := clamp(
			point.tangent_impulse[t] - point.tangent_mass[t] * tangent_velocity,
			-limit,
			limit,
		)
		impulse := total - point.tangent_impulse[t]
		point.tangent_impulse[t] = total
		apply_impulse(constraint, point, tangent * impulse)
	}

	normal_velocity := emath.dot(
		relative_velocity(a, b, point.anchor_a, point.anchor_b),
		constraint.normal,
	)
	total := max(
		point.normal_impulse + point.normal_mass * (point.velocity_bias - normal_velocity),
		0,
	)
	impulse := total - point.normal_impulse
	point.normal_impulse = total
	apply_impulse(constraint, point, constraint.normal * impulse)
}

@(private)
relative_velocity :: proc(a, b: ^Step_Body, anchor_a, anchor_b: emath.Vec3) -> emath.Vec3 {
	velocity_a := a.next.velocity + emath.cross(a.next.angular_velocity, anchor_a)
	velocity_b := b.next.velocity + emath.cross(b.next.angular_velocity, anchor_b)
	return velocity_b - velocity_a
}

@(private)
effective_mass :: proc(a, b: ^Step_Body, anchor_a, anchor_b, direction: emath.Vec3) -> f32 {
	arm_a := emath.cross(anchor_a, direction)
	arm_b := emath.cross(anchor_b, direction)
	k :=
		a.body.inverse_mass +
		b.body.inverse_mass +
		emath.dot(arm_a, a.body.inverse_inertia_world * arm_a) +
		emath.dot(arm_b, b.body.inverse_inertia_world * arm_b)
	return 1 / k if k > 0 else 0
}

@(private)
apply_impulse :: proc(
	constraint: ^Contact_Constraint,
	point: ^Constraint_Point,
	impulse: emath.Vec3,
) {
	a, b := constraint.a, constraint.b
	if a.body.motion == .Dynamic {
		a.next.velocity -= impulse * a.body.inverse_mass
		a.next.angular_velocity -=
			a.body.inverse_inertia_world * emath.cross(point.anchor_a, impulse)
	}
	if b.body.motion == .Dynamic {
		b.next.velocity += impulse * b.body.inverse_mass
		b.next.angular_velocity +=
			b.body.inverse_inertia_world * emath.cross(point.anchor_b, impulse)
	}
}

// Position iterations move the bodies directly. Anchors are recomputed from the
// current positions each time so the corrections converge.
@(private)
solve_positions :: proc(world: ^World) -> Error {
	settings := world.settings
	for _ in 0 ..< settings.position_iterations {
		for &constraint in world.scratch.constraints[:world.scratch.constraint_count] {
			a, b := constraint.a, constraint.b
			normal := constraint.normal
			for point in constraint.points[:constraint.count] {
				world_a := emath.transform_point(
					a.next.position,
					a.next.orientation,
					point.cache.local_a,
				)
				world_b := emath.transform_point(
					b.next.position,
					b.next.orientation,
					point.cache.local_b,
				)
				separation := max(
					emath.dot(world_b - world_a, normal) + settings.penetration_slop,
					-settings.max_penetration_correction,
				)
				if separation >= 0 {
					continue
				}

				anchor_a := world_a - a.next.position
				anchor_b := world_b - b.next.position
				mass := effective_mass(a, b, anchor_a, anchor_b, normal)
				correction := normal * (-settings.baumgarte * separation * mass)
				if !correct_position(a, anchor_a, -correction) ||
				   !correct_position(b, anchor_b, correction) {
					return .Invalid_Value
				}
			}
		}
	}
	return .None
}

@(private)
correct_position :: proc(step: ^Step_Body, anchor, correction: emath.Vec3) -> bool {
	body := step.body
	if body.motion != .Dynamic {
		return true
	}

	step.next.position += correction * body.inverse_mass
	orientation, ok := advance_orientation(
		step.next.orientation,
		body.inverse_inertia_world * emath.cross(anchor, correction),
		1,
	)
	step.next.orientation = orientation
	return ok
}

@(private)
store_impulses :: proc(world: ^World) {
	for &constraint in world.scratch.constraints[:world.scratch.constraint_count] {
		for point in constraint.points[:constraint.count] {
			point.cache.normal_impulse = point.normal_impulse
			point.cache.tangent_impulse = point.tangent_impulse
		}
	}
}

@(private)
tangent_basis :: proc(normal: emath.Vec3) -> [2]emath.Vec3 {
	axis := emath.Vec3{1, 0, 0}
	if abs(normal.x) > abs(normal.y) && abs(normal.x) > abs(normal.z) {
		axis = {0, 1, 0}
	}
	first := emath.normalize(emath.cross(normal, axis))
	return {first, emath.cross(normal, first)}
}
