// odin run src/camera/test_gl -collection:ember=src -collection:game=game
package camera_gl_smoke

import "core:fmt"
import "core:slice"
import emath "ember:core/math"
import "ember:engine"
import game "game:."
import gl "vendor:OpenGL"
import "vendor:glfw"

Harness :: struct {
	config:            engine.Config,
	initial_pixels:    []u8,
	orbit_pixels:      []u8,
	initial_width:     i32,
	initial_height:    i32,
	initial_transform: emath.Transform,
	draw_count:        int,
}

on_init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	h := cast(^Harness)userdata
	h.initial_width, h.initial_height = app.width, app.height
	if !h.config.init(app, h.config.userdata) {
		return false
	}
	state := cast(^game.State)h.config.userdata
	h.initial_transform = state.transform
	return true
}

on_update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	h := cast(^Harness)userdata
	h.config.update(app, h.config.userdata, dt)
	state := cast(^game.State)h.config.userdata
	state.angle = 0 // Hold the object still so pixel differences measure the camera.
	state.transform = h.initial_transform
	switch app.frame_count {
	case 1:
		assert(state.orbit.yaw != game.INITIAL_ORBIT.yaw)
	case 2:
		assert(state.orbit.distance < game.INITIAL_ORBIT.distance)
	case 3, 4, 5:
		assert(state.orbit == game.INITIAL_ORBIT)
	}
	if app.frame_count == 5 {
		engine.request_quit(app)
	}
}

on_draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	h := cast(^Harness)userdata
	assert(h.config.draw(app, h.config.userdata))
	pixels := make([]u8, int(app.width * app.height * 4))
	defer delete(pixels)
	gl.ReadPixels(0, 0, app.width, app.height, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	assert(gl.GetError() == gl.NO_ERROR)

	handle := glfw.GetCurrentContext()
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

	// Inject through the installed callbacks without sending system input.
	switch app.frame_count {
	case 0:
		h.initial_pixels = make([]u8, len(pixels))
		copy(h.initial_pixels, pixels)
		focus(handle, 0)
		focus(handle, 1)
		cursor(handle, 100, 100)
		mouse(handle, glfw.MOUSE_BUTTON_LEFT, glfw.PRESS, 0)
		cursor(handle, 180, 120)
	case 1:
		assert(!slice.equal(pixels, h.initial_pixels))
		h.orbit_pixels = make([]u8, len(pixels))
		copy(h.orbit_pixels, pixels)
		mouse(handle, glfw.MOUSE_BUTTON_LEFT, glfw.RELEASE, 0)
		scroll(handle, 0, 2)
	case 2:
		assert(!slice.equal(pixels, h.orbit_pixels))
		key(handle, glfw.KEY_R, 0, glfw.PRESS, 0)
		key(handle, glfw.KEY_R, 0, glfw.RELEASE, 0)
	case 3:
		assert(slice.equal(pixels, h.initial_pixels))
		glfw.SetWindowSize(handle, 192, 64)
	case 4:
		assert(app.width != h.initial_width || app.height != h.initial_height)
		viewport: [4]i32
		gl.GetIntegerv(gl.VIEWPORT, &viewport[0])
		assert(viewport[2] == app.width && viewport[3] == app.height)
		center := (int(app.height / 2) * int(app.width) + int(app.width / 2)) * 4
		assert(
			abs(int(pixels[center]) - 26) +
				abs(int(pixels[center + 1]) - 26) +
				abs(int(pixels[center + 2]) - 26) >
			30,
		)
		mouse(handle, glfw.MOUSE_BUTTON_LEFT, glfw.PRESS, 0)
		cursor(handle, 400, 500)
		focus(handle, 0) // Cancel the pending drag.
		focus(handle, 1)
		cursor(handle, 900, 800) // Refocus establishes a fresh baseline.
	}
	h.draw_count += 1
	return true
}

on_quit :: proc(app: ^engine.Context, userdata: rawptr) {
	h := cast(^Harness)userdata
	h.config.quit(app, h.config.userdata)
}

main :: proc() {
	h := Harness {
		config = game.configure(),
	}
	defer delete(h.initial_pixels)
	defer delete(h.orbit_pixels)
	config := engine.Config {
		title    = "Ember camera smoke",
		width    = 128,
		height   = 96,
		hidden   = true,
		userdata = &h,
		init     = on_init,
		update   = on_update,
		draw     = on_draw,
		quit     = on_quit,
	}
	assert(engine.run(config) == .None)
	assert(h.draw_count == 5)
	fmt.println(
		"Camera smoke passed: drag and zoom change pixels; reset restores pixels; resize and refocus remain stable",
	)
}
