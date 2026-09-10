package input

Button_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}

State :: struct {
	keys:                 [Key]Button_State,
	mouse_buttons:        [Mouse_Button]Button_State,
	focused:              bool,
	mouse_position:       [2]f64,
	mouse_position_valid: bool,
	mouse_delta:          [2]f64,
	scroll_delta:         [2]f64,
}

down :: proc(state: ^State, key: Key) -> bool {
	return state != nil && valid_key(key) && state.keys[key].down
}

pressed :: proc(state: ^State, key: Key) -> bool {
	return state != nil && valid_key(key) && state.keys[key].pressed
}

released :: proc(state: ^State, key: Key) -> bool {
	return state != nil && valid_key(key) && state.keys[key].released
}

mouse_down :: proc(state: ^State, button: Mouse_Button) -> bool {
	return state != nil && valid_mouse_button(button) && state.mouse_buttons[button].down
}

mouse_pressed :: proc(state: ^State, button: Mouse_Button) -> bool {
	return state != nil && valid_mouse_button(button) && state.mouse_buttons[button].pressed
}

mouse_released :: proc(state: ^State, button: Mouse_Button) -> bool {
	return state != nil && valid_mouse_button(button) && state.mouse_buttons[button].released
}

init :: proc(state: ^State, focused: bool, position: [2]f64 = {}) {
	state^ = State {
		focused              = focused,
		mouse_position       = position,
		mouse_position_valid = focused,
	}
}

record_key :: proc(state: ^State, key: Key, is_down: bool) {
	if !state.focused || !valid_key(key) {
		return
	}
	transition(&state.keys[key], is_down)
}

record_mouse_button :: proc(state: ^State, button: Mouse_Button, is_down: bool) {
	if !state.focused || !valid_mouse_button(button) {
		return
	}
	transition(&state.mouse_buttons[button], is_down)
}

record_cursor :: proc(state: ^State, position: [2]f64) {
	if !state.focused {
		return
	}
	delta: [2]f64
	if state.mouse_position_valid {
		delta = position - state.mouse_position
	}
	state.mouse_position = position
	state.mouse_position_valid = true
	state.mouse_delta += delta
}

record_scroll :: proc(state: ^State, offset: [2]f64) {
	if !state.focused {
		return
	}
	state.scroll_delta += offset
}

// Discard the old cursor position so regaining focus cannot cause a jump.
record_focus :: proc(state: ^State, focused: bool) {
	if state.focused == focused {
		return
	}
	state.focused = focused
	state.mouse_position_valid = false
	if !focused {
		release_all(state)
	}
}

@(private)
valid_key :: proc(key: Key) -> bool {
	return key > .Unknown && key <= max(Key)
}

@(private)
valid_mouse_button :: proc(button: Mouse_Button) -> bool {
	return button >= min(Mouse_Button) && button <= max(Mouse_Button)
}

@(private)
transition :: proc(button: ^Button_State, is_down: bool) {
	if button.down == is_down {
		return
	}
	button.down = is_down
	if is_down {
		button.pressed = true
	} else {
		button.released = true
	}
}

clear :: proc(state: ^State) {
	for &button in state.keys {
		button.pressed, button.released = false, false
	}
	for &button in state.mouse_buttons {
		button.pressed, button.released = false, false
	}
	state.mouse_delta = {}
	state.scroll_delta = {}
}

@(private)
release_all :: proc(state: ^State) {
	for &button in state.keys {
		transition(&button, false)
		button.pressed = false
	}
	for &button in state.mouse_buttons {
		transition(&button, false)
		button.pressed = false
	}
	state.mouse_delta = {}
	state.scroll_delta = {}
}
