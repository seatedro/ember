package engine

import "../input"
import "core:testing"

Input_Harness :: struct {
	snapshots: [8]input.State,
	durations: [8]f32,
	count:     int,
	quit:      bool,
}

capture_input :: proc(app: ^Context, userdata: rawptr, dt: f32) {
	h := cast(^Input_Harness)userdata
	h.snapshots[h.count] = app.input^
	h.durations[h.count] = dt
	h.count += 1
	if h.quit {
		request_quit(app)
	}
}

@(test)
test_fixed_updates_deliver_input_once :: proc(t: ^testing.T) {
	events: input.State
	input.init(&events, true)
	input.record_key(&events, .Space, true)
	input.record_cursor(&events, {4, 2})
	input.record_scroll(&events, {0, 0.5})
	h: Input_Harness
	config := Config {
		fixed_timestep = 0.125,
		userdata       = &h,
		update         = capture_input,
	}
	app := Context {
		running = true,
		input   = &events,
	}
	accumulator: f64

	// Exactly representable intervals make the tick counts deterministic.
	run_updates(config, &app, 0.0625, &accumulator)
	testing.expect_value(t, h.count, 0)
	testing.expect(t, input.pressed(app.input, .Space))
	run_updates(config, &app, 0.375, &accumulator)
	testing.expect_value(t, h.count, 3)
	testing.expect(t, input.pressed(&h.snapshots[0], .Space))
	testing.expect_value(t, h.snapshots[0].mouse_delta, [2]f64{4, 2})
	testing.expect_value(t, h.snapshots[0].scroll_delta, [2]f64{0, 0.5})
	for i in 1 ..< h.count {
		testing.expect(t, input.down(&h.snapshots[i], .Space))
		testing.expect(t, !input.pressed(&h.snapshots[i], .Space))
		testing.expect_value(t, h.snapshots[i].mouse_delta, [2]f64{})
		testing.expect_value(t, h.snapshots[i].scroll_delta, [2]f64{})
		testing.expect_value(t, h.durations[i], f32(0.125))
	}
	testing.expect_value(t, accumulator, f64(0.0625))
	testing.expect(t, !input.pressed(app.input, .Space))
	testing.expect_value(t, app.input.mouse_delta, [2]f64{})

	input.record_key(&events, .Space, false)
	run_updates(config, &app, 0, &accumulator)
	testing.expect_value(t, h.count, 3)
	testing.expect(t, input.released(app.input, .Space))
	run_updates(config, &app, 0.0625, &accumulator)
	testing.expect_value(t, h.count, 4)
	testing.expect(t, input.released(&h.snapshots[3], .Space))
	testing.expect(t, !input.down(&h.snapshots[3], .Space))
	testing.expect(t, !input.released(app.input, .Space))
}

@(test)
test_variable_updates_and_missing_callback :: proc(t: ^testing.T) {
	events: input.State
	input.init(&events, true)
	input.record_key(&events, .R, true)
	input.record_key(&events, .R, false)
	h: Input_Harness
	app := Context {
		running = true,
		input   = &events,
	}
	accumulator: f64
	run_updates({}, &app, 0.01, &accumulator)
	config := Config {
		userdata = &h,
		update   = capture_input,
	}
	run_updates(config, &app, 0.01, &accumulator)
	run_updates(config, &app, 0.02, &accumulator)
	testing.expect_value(t, h.count, 2)
	testing.expect(t, input.pressed(&h.snapshots[0], .R) && input.released(&h.snapshots[0], .R))
	testing.expect(t, !input.pressed(&h.snapshots[1], .R) && !input.released(&h.snapshots[1], .R))
	testing.expect_value(t, h.durations[1], f32(0.02))
}

@(test)
test_quit_stops_catch_up_updates :: proc(t: ^testing.T) {
	events: input.State
	input.init(&events, true)
	h := Input_Harness {
		quit = true,
	}
	config := Config {
		fixed_timestep = 0.125,
		userdata       = &h,
		update         = capture_input,
	}
	app := Context {
		running = true,
		input   = &events,
	}
	accumulator: f64
	run_updates(config, &app, 0.5, &accumulator)
	testing.expect_value(t, h.count, 1)
	testing.expect(t, !app.running)
}
