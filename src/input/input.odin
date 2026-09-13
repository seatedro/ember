package input

Modifier :: enum {
	Shift,
	Control,
	Alt,
	Super,
}
Modifiers :: bit_set[Modifier;u8]

Button_State :: struct {
	modifiers: Modifiers,
	down:      bool,
	pressed:   bool,
	released:  bool,
	repeated:  bool,
}

State :: struct {
	keys:                 [Key]Button_State,
	text:                 [dynamic]rune,
	text_failed:          bool,
	mouse_buttons:        [Mouse_Button]Button_State,
	mouse_press_position: [Mouse_Button][2]f64,
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

record_key :: proc(state: ^State, key: Key, is_down: bool, modifiers: Modifiers = {}) {
	if !state.focused || !valid_key(key) {
		return
	}
	transition(&state.keys[key], is_down)
	if is_down {
		state.keys[key].modifiers = modifiers | current_modifiers(state)
	}
}

record_mouse_button :: proc(state: ^State, button: Mouse_Button, is_down: bool) {
	if !state.focused || !valid_mouse_button(button) {
		return
	}
	if is_down && !state.mouse_buttons[button].down {
		state.mouse_press_position[button] = state.mouse_position
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
		button.repeated = false
	}
	for &button in state.mouse_buttons {
		button.pressed, button.released = false, false
		button.repeated = false
	}
	state.mouse_delta = {}
	state.scroll_delta = {}
	resize(&state.text, 0)
	state.text_failed = false
}

@(private)
release_all :: proc(state: ^State) {
	for &button in state.keys {
		transition(&button, false)
		button.pressed = false
		button.repeated = false
	}
	for &button in state.mouse_buttons {
		transition(&button, false)
		button.pressed = false
		button.repeated = false
	}
	state.mouse_delta = {}
	state.scroll_delta = {}
	resize(&state.text, 0)
	state.text_failed = false
}

Clipboard :: struct {
	get:      proc(userdata: rawptr) -> (string, bool),
	set:      proc(userdata: rawptr, value: string) -> bool,
	userdata: rawptr,
}

record_text :: proc(state: ^State, character: rune) {
	if !state.focused ||
	   character < 32 ||
	   character == 127 ||
	   character > 0x10ffff ||
	   (character >= 0xd800 && character <= 0xdfff) {
		return
	}

	if _, err := append(&state.text, character); err != nil {
		state.text_failed = true
	}
}

record_repeat :: proc(state: ^State, key: Key, modifiers: Modifiers = {}) {
	if state.focused && valid_key(key) && state.keys[key].down {
		state.keys[key].repeated = true
		state.keys[key].modifiers = modifiers | current_modifiers(state)
	}
}

destroy :: proc(state: ^State) {
	delete(state.text)
	state^ = {}
}

current_modifiers :: proc(state: ^State) -> Modifiers {
	modifiers: Modifiers
	if down(state, .Left_Shift) || down(state, .Right_Shift) {
		modifiers += {.Shift}
	}
	if down(state, .Left_Control) || down(state, .Right_Control) {
		modifiers += {.Control}
	}
	if down(state, .Left_Alt) || down(state, .Right_Alt) {
		modifiers += {.Alt}
	}
	if down(state, .Left_Super) || down(state, .Right_Super) {
		modifiers += {.Super}
	}
	return modifiers
}

key_modifiers :: proc(state: ^State, key: Key) -> Modifiers {
	if valid_key(key) && (state.keys[key].pressed || state.keys[key].repeated) {
		return state.keys[key].modifiers
	}

	return current_modifiers(state)
}
