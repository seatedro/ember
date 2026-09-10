// odin run src/platform/window/test_input -collection:ember=src
package window_input_smoke

import "core:fmt"
import "ember:input"
import win "ember:platform/window"
import "vendor:glfw"

main :: proc() {
	window: win.Window
	assert(
		win.create(&window, {title = "Ember input smoke", width = 64, height = 64, hidden = true}),
	)
	defer win.destroy(&window)
	handle := window.handle

	// Retrieve the actual registered callbacks, restore them, and inject events
	// through that boundary. This needs a native window, but does not send OS keys
	// or move the user's cursor.
	key := glfw.SetKeyCallback(handle, nil)
	mouse := glfw.SetMouseButtonCallback(handle, nil)
	cursor := glfw.SetCursorPosCallback(handle, nil)
	scroll := glfw.SetScrollCallback(handle, nil)
	focus := glfw.SetWindowFocusCallback(handle, nil)
	assert(key != nil && mouse != nil && cursor != nil && scroll != nil && focus != nil)
	glfw.SetKeyCallback(handle, key)
	glfw.SetMouseButtonCallback(handle, mouse)
	glfw.SetCursorPosCallback(handle, cursor)
	glfw.SetScrollCallback(handle, scroll)
	glfw.SetWindowFocusCallback(handle, focus)

	focus(handle, 0)
	focus(handle, 1)
	cursor(handle, 100, 200)
	cursor(handle, 110, 190)
	scroll(handle, 0.25, -0.5)
	key(handle, glfw.KEY_UNKNOWN, 0, glfw.PRESS, 0)
	key(handle, glfw.KEY_SPACE, 0, glfw.PRESS, 0)
	key(handle, glfw.KEY_SPACE, 0, glfw.REPEAT, 0)
	mouse(handle, glfw.MOUSE_BUTTON_LEFT, glfw.PRESS, 0)
	state := &window.input
	assert(state.focused && state.mouse_position_valid)
	assert(input.pressed(state, .Space) && input.down(state, .Space))
	assert(input.mouse_pressed(state, .Left) && input.mouse_down(state, .Left))
	assert(state.mouse_position == [2]f64{110, 190})
	assert(state.mouse_delta == [2]f64{10, -10})
	assert(state.scroll_delta == [2]f64{0.25, -0.5})
	input.clear(state)

	key(handle, glfw.KEY_SPACE, 0, glfw.REPEAT, 0)
	assert(input.down(state, .Space) && !input.pressed(state, .Space))
	input.clear(state)
	key(handle, glfw.KEY_SPACE, 0, glfw.RELEASE, 0)
	assert(input.released(state, .Space) && !input.down(state, .Space))

	input.clear(state)
	key(handle, glfw.KEY_W, 0, glfw.PRESS, 0)
	focus(handle, 0)
	// GLFW may synthesize releases after the focus callback. They must not replay.
	mouse(handle, glfw.MOUSE_BUTTON_LEFT, glfw.RELEASE, 0)
	assert(!state.focused)
	assert(input.released(state, .W) && !input.pressed(state, .W))
	assert(input.mouse_released(state, .Left) && !input.mouse_down(state, .Left))
	input.clear(state)
	assert(!input.mouse_released(state, .Left))

	focus(handle, 1)
	cursor(handle, 500, 500)
	assert(state.mouse_position_valid && state.mouse_delta == [2]f64{})
	glfw.SetWindowShouldClose(handle, true)
	assert(win.should_close(&window))
	fmt.println(
		"Window input smoke passed: registered callbacks, key repeat, motion, scroll, focus, close",
	)
}
