package particles

import emath "../core/math"
import "../physics"
import "core:math"
import "core:math/rand"
import "core:mem"

Error :: enum {
	None,
	Invalid_Emitter,
	Invalid_Settings,
	Invalid_Time_Step,
	Allocation_Failed,
}

Settings :: struct {
	position:                     emath.Vec3,
	radius:                       f32,
	velocity, velocity_variation: emath.Vec3,
	radial_speed:                 [2]f32,
	acceleration:                 emath.Vec3,
	rate:                         f32,
	lifetime:                     [2]f32,
	size:                         [2]f32,
	color:                        [2]emath.Vec4,
	rotation, angular_velocity:   [2]f32,
}

Particle :: struct {
	using motion:               physics.Motion,
	age, lifetime:              f32,
	size:                       [2]f32,
	color:                      [2]emath.Vec4,
	rotation, angular_velocity: f32,
	active:                     bool,
}

Emitter :: struct {
	particles:        []Particle,
	settings:         Settings,
	emitting, paused: bool,
	count, next:      int,
	replaced:         u64,
	seed:             u64,
	random:           rand.Xoshiro256_Random_State,
	remainder:        f64,
	allocator:        mem.Allocator,
}

create :: proc(capacity: int, seed: u64, allocator := context.allocator) -> (Emitter, Error) {
	if capacity <= 0 || capacity > max(int) / size_of(Particle) {
		return {}, .Invalid_Emitter
	}

	storage, err := make([]Particle, capacity, allocator)
	if err != .None {
		return {}, .Allocation_Failed
	}

	emitter := Emitter {
		particles = storage,
		seed = seed,
		allocator = allocator,
		emitting = true,
		settings = {lifetime = {1, 1}, size = {0.1, 0}, color = {{1, 1, 1, 1}, {1, 1, 1, 0}}},
	}
	reset(&emitter)
	return emitter, .None
}

destroy :: proc(emitter: ^Emitter) {
	delete(emitter.particles, emitter.allocator)
	emitter^ = {}
}

reset :: proc(emitter: ^Emitter) {
	for &particle in emitter.particles {
		particle = {}
	}

	emitter.count, emitter.next = 0, 0
	emitter.replaced, emitter.remainder = 0, 0
	rand.reset(emitter.seed, rand.xoshiro256_random_generator(&emitter.random))
}

emit :: proc(emitter: ^Emitter, count: int) -> Error {
	if len(emitter.particles) == 0 || count < 0 {
		return .Invalid_Emitter
	}

	if !valid_settings(emitter.settings) {
		return .Invalid_Settings
	}

	if !emitter.paused {
		for _ in 0 ..< count {
			spawn(emitter)
		}
	}

	return .None
}

update :: proc(emitter: ^Emitter, dt: f32) -> Error {
	if len(emitter.particles) == 0 {
		return .Invalid_Emitter
	}

	if !(dt >= 0) || math.is_inf(dt) {
		return .Invalid_Time_Step
	}

	if !valid_settings(emitter.settings) {
		return .Invalid_Settings
	}

	if emitter.paused || dt == 0 {
		return .None
	}

	total := emitter.remainder
	if emitter.emitting {
		total += f64(emitter.settings.rate) * f64(dt)
	}

	if total >= f64(max(i32)) {
		return .Invalid_Time_Step
	}

	for &particle in emitter.particles {
		if particle.active && !advance(&particle, dt) {
			emitter.count -= 1
		}
	}

	if emitter.emitting && emitter.settings.rate > 0 {
		count := int(math.floor(total))
		emitter.remainder = total - f64(count)
		for i in 0 ..< count {
			particle := spawn(emitter)
			// Births occur throughout the step, so a steady stream does not clump at frame boundaries.
			age := f32((total - f64(i + 1)) / f64(emitter.settings.rate))
			if !advance(particle, age) {
				emitter.count -= 1
			}
		}
	}

	return .None
}

appearance :: proc(particle: Particle) -> (size: f32, color: emath.Vec4) {
	u := clamp(particle.age / particle.lifetime, 0, 1)
	return math.lerp(particle.size[0], particle.size[1], u),
		particle.color[0] * (1 - u) + particle.color[1] * u
}

@(private)
spawn :: proc(emitter: ^Emitter) -> ^Particle {
	settings := emitter.settings
	gen := rand.xoshiro256_random_generator(&emitter.random)
	z := rand.float32_range(-1, 1, gen)
	phi := rand.float32(gen) * (2 * math.PI)
	r := math.sqrt(max(0, 1 - z * z))
	direction := emath.Vec3{r * math.cos(phi), r * math.sin(phi), z}
	radius := settings.radius * math.pow(rand.float32(gen), f32(1.0 / 3.0))
	velocity :=
		settings.velocity +
		direction * rand.float32_range(settings.radial_speed[0], settings.radial_speed[1], gen)
	for &component, axis in velocity {
		component += rand.float32_range(-1, 1, gen) * settings.velocity_variation[axis]
	}

	particle := &emitter.particles[emitter.next]
	if particle.active {
		emitter.replaced += 1
	} else {
		emitter.count += 1
	}
	particle^ = {
		position         = settings.position + direction * radius,
		velocity         = velocity,
		acceleration     = settings.acceleration,
		lifetime         = rand.float32_range(settings.lifetime[0], settings.lifetime[1], gen),
		size             = settings.size,
		color            = settings.color,
		rotation         = rand.float32_range(settings.rotation[0], settings.rotation[1], gen),
		angular_velocity = rand.float32_range(
			settings.angular_velocity[0],
			settings.angular_velocity[1],
			gen,
		),
		active           = true,
	}

	emitter.next = (emitter.next + 1) % len(emitter.particles)
	return particle
}

@(private)
advance :: proc(particle: ^Particle, dt: f32) -> bool {
	particle.age += dt
	if particle.age >= particle.lifetime {
		particle.active = false
		return false
	}

	physics.integrate(&particle.motion, dt)
	particle.rotation += particle.angular_velocity * dt
	return true
}

@(private)
valid_settings :: proc(settings: Settings) -> bool {
	for vector in ([4]emath.Vec3 {
			settings.position,
			settings.velocity,
			settings.velocity_variation,
			settings.acceleration,
		}) {
		for value in vector {
			if !finite(value) {
				return false
			}
		}
	}

	for range in ([4][2]f32 {
			settings.lifetime,
			settings.radial_speed,
			settings.rotation,
			settings.angular_velocity,
		}) {
		if !finite(range[0]) || !finite(range[1]) || range[0] > range[1] {
			return false
		}
	}

	for color in settings.color {
		for value in color {
			if !finite(value) || value < 0 {
				return false
			}
		}

		if color.a > 1 {
			return false
		}
	}

	for size in settings.size {
		if !finite(size) || size < 0 {
			return false
		}
	}

	return(
		finite(settings.rate) &&
		settings.rate >= 0 &&
		finite(settings.radius) &&
		settings.radius >= 0 &&
		settings.lifetime[0] > 0 &&
		settings.radial_speed[0] >= 0 &&
		settings.velocity_variation.x >= 0 &&
		settings.velocity_variation.y >= 0 &&
		settings.velocity_variation.z >= 0 \
	)
}

@(private)
finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}
