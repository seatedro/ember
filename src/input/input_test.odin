package input

import "core:testing"

@(test)
test_button_transitions_and_taps :: proc(t: ^testing.T) {
	state: State
	init(&state, true)
	record_key(&state, .Space, true)
	record_key(&state, .Space, true)
	testing.expect(t, down(&state, .Space) && pressed(&state, .Space))
	testing.expect(t, !released(&state, .Space))
	testing.expect(t, pressed(&state, .Space))

	clear(&state)
	testing.expect(t, down(&state, .Space) && !pressed(&state, .Space))
	record_key(&state, .Space, false)
	record_key(&state, .Space, false)
	testing.expect(t, !down(&state, .Space) && released(&state, .Space))
	testing.expect(t, !pressed(&state, .Space))

	record_key(&state, .A, true)
	record_key(&state, .A, false)
	record_mouse_button(&state, .Left, true)
	record_mouse_button(&state, .Left, false)
	testing.expect(t, pressed(&state, .A) && released(&state, .A) && !down(&state, .A))
	testing.expect(t, mouse_pressed(&state, .Left) && mouse_released(&state, .Left))
	testing.expect(t, !mouse_down(&state, .Left))
}

@(test)
test_motion_accumulates_until_cleared :: proc(t: ^testing.T) {
	state: State
	init(&state, true, {10, 20})
	record_cursor(&state, {12, 23})
	record_scroll(&state, {0.25, 1})
	record_cursor(&state, {15, 22})
	record_scroll(&state, {-0.5, 0.5})
	testing.expect_value(t, state.mouse_delta, [2]f64{5, 2})
	testing.expect_value(t, state.scroll_delta, [2]f64{-0.25, 1.5})
	testing.expect_value(t, state.mouse_position, [2]f64{15, 22})

	clear(&state)
	testing.expect_value(t, state.mouse_delta, [2]f64{})
	testing.expect_value(t, state.scroll_delta, [2]f64{})
	testing.expect_value(t, state.mouse_position, [2]f64{15, 22})
}

@(test)
test_focus_loss_releases_and_cancels_actions :: proc(t: ^testing.T) {
	state: State
	init(&state, true, {10, 20})
	record_key(&state, .W, true)
	record_mouse_button(&state, .Left, true)
	record_cursor(&state, {20, 30})
	record_scroll(&state, {0, 2})
	record_focus(&state, false)

	testing.expect(t, !state.focused && !state.mouse_position_valid)
	testing.expect(t, !down(&state, .W) && released(&state, .W))
	testing.expect(t, !pressed(&state, .W))
	testing.expect(t, !mouse_down(&state, .Left) && mouse_released(&state, .Left))
	testing.expect(t, !mouse_pressed(&state, .Left))
	testing.expect_value(t, state.mouse_delta, [2]f64{})
	testing.expect_value(t, state.scroll_delta, [2]f64{})
	clear(&state)

	// Ignore unfocused input and the synthetic releases GLFW sends after blur.
	record_key(&state, .W, false)
	record_key(&state, .Space, true)
	record_mouse_button(&state, .Left, true)
	record_cursor(&state, {500, 500})
	record_scroll(&state, {1, 1})
	testing.expect(t, !released(&state, .W) && !pressed(&state, .Space))
	testing.expect(t, !mouse_down(&state, .Left))
	testing.expect_value(t, state.scroll_delta, [2]f64{})

	record_focus(&state, true)
	record_cursor(&state, {800, 900})
	record_cursor(&state, {803, 896})
	testing.expect(t, state.focused && state.mouse_position_valid)
	testing.expect_value(t, state.mouse_delta, [2]f64{3, -4})
	testing.expect(t, !down(&state, .W))
}

@(test)
test_invalid_controls_and_empty_state :: proc(t: ^testing.T) {
	state: State
	init(&state, true)
	for key in ([3]Key{.Unknown, Key(-1), Key(10000)}) {
		record_key(&state, key, true)
		testing.expect(t, !down(&state, key) && !pressed(&state, key) && !released(&state, key))
	}
	for button in ([2]Mouse_Button{Mouse_Button(-1), Mouse_Button(10000)}) {
		record_mouse_button(&state, button, true)
		testing.expect(t, !mouse_down(&state, button) && !mouse_pressed(&state, button))
		testing.expect(t, !mouse_released(&state, button))
	}
	testing.expect(t, !down(nil, .A) && !pressed(nil, .A) && !released(nil, .A))
	testing.expect(t, !mouse_down(nil, .Left) && !mouse_pressed(nil, .Left))
}
