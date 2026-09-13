package physics

import emath "../core/math"
import "core:math"

Motion :: struct {
	position, velocity, acceleration: emath.Vec3,
}

// Exact for constant acceleration over dt. Update position with the old velocity.
integrate :: proc(motion: ^Motion, dt: f32) {
	assert(dt >= 0 && !math.is_inf(dt))
	motion.position += motion.velocity * dt + motion.acceleration * (0.5 * dt * dt)
	motion.velocity += motion.acceleration * dt
}
