package game

import "core:testing"
import "ember:camera"
import "ember:engine"
import "ember:input"

@(test)
test_camera_controls_drag_zoom_reset_and_focus :: proc(t: ^testing.T) {
	state := State {
		orbit = INITIAL_ORBIT,
	}
	events: input.State
	input.init(&events, true)
	app := engine.Context {
		input = &events,
	}

	// Free cursor motion leaves the orbit alone.
	input.record_cursor(&events, {20, 10})
	update_camera(&state, &app)
	testing.expect_value(t, state.orbit, INITIAL_ORBIT)
	input.clear(&events)

	input.record_mouse_button(&events, .Left, true)
	input.record_cursor(&events, {60, 30})
	update_camera(&state, &app)
	testing.expect(
		t,
		state.orbit.yaw != INITIAL_ORBIT.yaw && state.orbit.pitch > INITIAL_ORBIT.pitch,
	)
	input.clear(&events)
	input.record_cursor(&events, {60, 1e6})
	input.record_scroll(&events, {0, 1e6})
	update_camera(&state, &app)
	testing.expect_value(t, state.orbit.pitch, PITCH_LIMIT)
	testing.expect_value(t, state.orbit.distance, MIN_DISTANCE)
	input.clear(&events)
	input.record_scroll(&events, {0, -1e6})
	update_camera(&state, &app)
	testing.expect_value(t, state.orbit.distance, MAX_DISTANCE)
	input.clear(&events)

	input.record_key(&events, .R, true)
	update_camera(&state, &app)
	testing.expect_value(t, state.orbit, INITIAL_ORBIT)
	input.clear(&events)

	input.record_focus(&events, false)
	input.record_cursor(&events, {100, 200})
	update_camera(&state, &app)
	testing.expect_value(t, state.orbit, INITIAL_ORBIT)
	input.record_focus(&events, true)
	input.record_cursor(&events, {500, 500})
	update_camera(&state, &app)
	testing.expect_value(t, state.camera, camera.from_orbit(INITIAL_ORBIT))
}

@(test)
test_camera_scroll_accumulation_and_clear :: proc(t: ^testing.T) {
	events: input.State
	input.init(&events, true)
	app := engine.Context {
		input = &events,
	}
	combined := State {
		orbit = INITIAL_ORBIT,
	}
	input.record_scroll(&events, {0, 0.25})
	input.record_scroll(&events, {0, 0.75})
	update_camera(&combined, &app)
	input.clear(&events)
	before := combined.orbit
	update_camera(&combined, &app)
	testing.expect_value(t, combined.orbit, before)

	split := State {
		orbit = INITIAL_ORBIT,
	}
	for delta in ([2]f64{0.25, 0.75}) {
		input.record_scroll(&events, {0, delta})
		update_camera(&split, &app)
		input.clear(&events)
	}
	testing.expect(t, abs(split.orbit.distance - combined.orbit.distance) < 0.00001)
}
