package particles

import emath "../core/math"
import "core:testing"

@(test)
test_recycling_and_expiry :: proc(t: ^testing.T) {
	emitter, err := create(3, 0)
	testing.expect_value(t, err, Error.None)
	defer destroy(&emitter)
	for i in 0 ..< 8 {
		emitter.settings.position.x = f32(i)
		testing.expect_value(t, emit(&emitter, 1), Error.None)
	}

	testing.expect_value(t, emitter.count, 3)
	testing.expect_value(t, emitter.replaced, 5)
	for particle in emitter.particles {
		testing.expect(t, particle.position.x >= 5)
	}

	testing.expect_value(t, update(&emitter, 1), Error.None)
	testing.expect_value(t, emitter.count, 0)
	testing.expect_value(t, emit(&emitter, 1), Error.None)
	testing.expect_value(t, emitter.count, 1)
	testing.expect_value(t, emitter.replaced, 5)
}

@(test)
test_seeded_reset_and_pause :: proc(t: ^testing.T) {
	emitter, err := create(4, 0)
	testing.expect_value(t, err, Error.None)
	defer destroy(&emitter)
	emitter.settings.radius = 2
	emitter.settings.radial_speed = {1, 3}
	emitter.settings.lifetime = {2, 4}
	testing.expect_value(t, emit(&emitter, 4), Error.None)
	before: [4]Particle
	copy(before[:], emitter.particles)
	emitter.paused = true
	testing.expect_value(t, update(&emitter, 1), Error.None)
	testing.expect_value(t, emit(&emitter, 8), Error.None)
	for particle, i in emitter.particles {
		testing.expect_value(t, particle, before[i])
	}
	reset(&emitter)
	emitter.paused = false
	testing.expect_value(t, emit(&emitter, 4), Error.None)
	for particle, i in emitter.particles {
		testing.expect_value(t, particle, before[i])
	}
}

@(test)
test_emission_times_and_motion :: proc(t: ^testing.T) {
	emitter, err := create(8, 5)
	testing.expect_value(t, err, Error.None)
	defer destroy(&emitter)
	emitter.settings.rate = 4
	emitter.settings.lifetime = {2, 2}
	emitter.settings.velocity = {2, 0, 0}
	emitter.settings.acceleration = {0, -8, 0}
	testing.expect_value(t, update(&emitter, 0.5), Error.None)
	testing.expect_value(t, emitter.count, 2)
	testing.expect_value(t, emitter.particles[0].age, 0.25)
	testing.expect_value(t, emitter.particles[0].position, emath.Vec3{0.5, -0.25, 0})
	testing.expect_value(t, emitter.particles[1].age, 0)
	before: [2]Particle
	copy(before[:], emitter.particles[:2])
	reset(&emitter)
	for _ in 0 ..< 4 {
		testing.expect_value(t, update(&emitter, 0.125), Error.None)
	}

	for particle, i in emitter.particles[:2] {
		testing.expect_value(t, particle, before[i])
	}

	emitter.emitting = false
	testing.expect_value(t, update(&emitter, 2), Error.None)
	testing.expect_value(t, emitter.count, 0)
}
