package engine

import "../input"
import "core:math"
import "core:testing"

@(private)
clock_frame :: proc(t: ^testing.T, clock: ^Clock, dt: f64, previous, current: ^f64) {
	testing.expect(t, advance_clock(clock, dt))
	for tick_clock(clock) {
		previous^ = current^
		current^ += clock.timestep
	}
}

@(test)
test_clock_frame_rates_pause_step_and_resume :: proc(t: ^testing.T) {
	for fps in ([3]int{30, 60, 144}) {
		clock := create_clock()
		previous, current: f64
		for _ in 0 ..< fps * 2 {
			clock_frame(t, &clock, 1.0 / f64(fps), &previous, &current)
		}
		testing.expect_value(t, clock.ticks, u64(120))
		testing.expect(t, abs(clock.elapsed - 2) < 1e-10 && abs(current - 2) < 1e-10)
		testing.expect_value(t, clock.discarded_time, f64(0))
		clock_frame(t, &clock, clock.timestep / 3, &previous, &current)
		shown := math.lerp(previous, current, f64(clock.interpolation))
		elapsed := clock.elapsed
		clock.paused = true
		clock_frame(t, &clock, 10, &previous, &current)
		testing.expect_value(t, math.lerp(previous, current, f64(clock.interpolation)), shown)
		testing.expect_value(t, clock.elapsed, elapsed)
		step_clock(&clock)
		clock_frame(t, &clock, 1, &previous, &current)
		testing.expect(t, abs(clock.elapsed - elapsed - clock.timestep) < 1e-10)
		testing.expect_value(t, clock.interpolation, f32(1))
		shown = current
		clock.paused = false
		for _ in 0 ..< 12 {
			clock_frame(t, &clock, clock.timestep / 4, &previous, &current)
			next := math.lerp(previous, current, f64(clock.interpolation))
			testing.expect(t, next >= shown)
			shown = next
		}
		clock.scale = 0
		elapsed = clock.elapsed
		shown = math.lerp(previous, current, f64(clock.interpolation))
		clock_frame(t, &clock, 5, &previous, &current)
		testing.expect_value(t, clock.elapsed, elapsed)
		testing.expect_value(t, math.lerp(previous, current, f64(clock.interpolation)), shown)
	}
}

@(test)
test_clock_catchup_cap_and_queued_steps :: proc(t: ^testing.T) {
	clock := create_clock(0.125, 2)
	clock.scale = 2
	previous, current: f64
	clock_frame(t, &clock, 0.34, &previous, &current)
	testing.expect_value(t, clock.ticks, u64(2))
	testing.expect_value(t, clock.elapsed, f64(0.25))
	testing.expect(t, abs(clock.discarded_time - 0.375) < 1e-10)
	testing.expect(t, abs(clock.interpolation - 0.44) < 1e-6)
	clock_frame(t, &clock, 0.01, &previous, &current)
	testing.expect_value(t, clock.ticks, u64(2))
	testing.expect(t, abs(clock.interpolation - 0.6) < 1e-6)
	for _ in 0 ..< 3 {
		step_clock(&clock)
	}
	clock_frame(t, &clock, 10, &previous, &current)
	testing.expect(t, clock.ticks == 4 && clock.pending_steps == 1)
	clock_frame(t, &clock, 10, &previous, &current)
	testing.expect(t, clock.ticks == 5 && clock.pending_steps == 0)
	testing.expect(t, abs(clock.discarded_time - 0.375) < 1e-10)
	reset_clock(&clock)
	testing.expect(
		t,
		clock.ticks == 0 &&
		clock.elapsed == 0 &&
		clock.discarded_time == 0 &&
		clock.accumulator == 0,
	)
	testing.expect(t, clock.paused && clock.scale == 2 && clock.timestep == 0.125)
	before := clock
	testing.expect(t, !advance_clock(&clock, transmute(f64)u64(0x7ff0000000000000)))
	testing.expect_value(t, clock, before)
}

@(private)
Update_Probe :: struct {
	frames, ticks, presses, commands_consumed: int,
	command_pending:                           bool,
	step_requested:                            bool,
	bad_input, bad_time:                       bool,
}

@(test)
test_frame_input_and_fixed_simulation_are_separate :: proc(t: ^testing.T) {
	state: input.State
	input.init(&state, true)
	probe: Update_Probe
	app := Context {
		running    = true,
		input      = &state,
		simulation = create_clock(0.02),
	}
	config := Config {
		userdata = &probe,
		update = proc(app: ^Context, userdata: rawptr, dt: f32) {
			probe := cast(^Update_Probe)userdata
			probe.frames += 1
			if input.pressed(app.input, .Space) {
				probe.presses += 1
				probe.command_pending = true
			}
			if probe.step_requested {
				step_clock(&app.simulation)
				probe.step_requested = false
			}
		},
		fixed_update = proc(app: ^Context, userdata: rawptr, dt: f32) {
			probe := cast(^Update_Probe)userdata
			probe.ticks += 1
			probe.bad_input = probe.bad_input || input.pressed(app.input, .Space)
			probe.bad_time =
				probe.bad_time ||
				abs(dt - 0.02) > 1e-7 ||
				abs(app.simulation.elapsed - f64(probe.ticks) * 0.02) > 1e-10
			if probe.command_pending {
				probe.commands_consumed += 1
				probe.command_pending = false
			}
		},
	}
	input.record_key(&state, .Space, true)
	testing.expect(t, run_updates(config, &app, 0.001))
	testing.expect(t, probe.frames == 1 && probe.ticks == 0 && probe.command_pending)
	testing.expect(t, run_updates(config, &app, 0.099))
	testing.expect(
		t,
		probe.frames == 2 &&
		probe.ticks == 5 &&
		probe.presses == 1 &&
		probe.commands_consumed == 1,
	)
	app.simulation.paused = true
	testing.expect(t, run_updates(config, &app, 1))
	testing.expect(t, probe.frames == 3 && probe.ticks == 5)
	probe.step_requested = true
	testing.expect(t, run_updates(config, &app, 1))
	testing.expect(t, probe.frames == 4 && probe.ticks == 6 && app.simulation.paused)
	testing.expect(t, !probe.bad_input && !probe.bad_time)
}
