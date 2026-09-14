package engine

import "core:math"

Clock :: struct {
	timestep:                       f64,
	scale:                          f32,
	paused:                         bool,
	max_steps:                      u32,
	elapsed, discarded_time:        f64,
	ticks:                          u64,
	interpolation:                  f32,
	accumulator:                    f64,
	pending_steps, remaining_steps: u32,
	manual_frame, snap:             bool,
}

create_clock :: proc(timestep: f64 = 1.0 / 60.0, max_steps: u32 = 8) -> Clock {
	assert(timestep > 0 && !math.is_inf(timestep) && max_steps > 0)
	return {timestep = timestep, max_steps = max_steps, scale = 1}
}

reset_clock :: proc(clock: ^Clock) {
	clock^ = {
		timestep  = clock.timestep,
		max_steps = clock.max_steps,
		scale     = clock.scale,
		paused    = clock.paused,
	}
}

step_clock :: proc(clock: ^Clock) {
	clock.paused = true
	if clock.pending_steps < max(u32) {
		clock.pending_steps += 1
	}
}

advance_clock :: proc(clock: ^Clock, real_delta: f64) -> bool {
	if !(real_delta >= 0) ||
	   math.is_inf(real_delta) ||
	   !(clock.timestep > 0) ||
	   math.is_inf(clock.timestep) ||
	   !(clock.scale >= 0) ||
	   math.is_inf(clock.scale) ||
	   clock.max_steps == 0 ||
	   clock.remaining_steps != 0 {
		return false
	}
	clock.manual_frame = clock.paused
	if clock.paused {
		clock.remaining_steps = min(clock.pending_steps, clock.max_steps)
		clock.pending_steps -= clock.remaining_steps
		return true
	}
	clock.pending_steps = 0
	if clock.scale == 0 {
		return true
	}

	total := clock.accumulator + real_delta * f64(clock.scale)
	whole := math.floor(total / clock.timestep + 1e-9)
	if math.is_inf(whole) {
		return false
	}
	clock.remaining_steps = u32(min(whole, f64(clock.max_steps)))
	clock.discarded_time += (whole - f64(clock.remaining_steps)) * clock.timestep
	clock.accumulator = max(total - whole * clock.timestep, 0)
	if !clock.snap {
		clock.interpolation = f32(clamp(clock.accumulator / clock.timestep, 0, 1))
	}
	return true
}

tick_clock :: proc(clock: ^Clock) -> bool {
	if clock.paused && !clock.manual_frame {
		clock.remaining_steps = 0
	}
	if clock.remaining_steps == 0 {
		return false
	}
	clock.remaining_steps -= 1
	clock.elapsed += clock.timestep
	clock.ticks += 1
	clock.snap = clock.manual_frame
	// A manual step shows its completed state until the next ordinary tick,
	// so resuming cannot interpolate backward from the displayed result.
	clock.interpolation = 1 if clock.snap else f32(clamp(clock.accumulator / clock.timestep, 0, 1))
	return true
}
