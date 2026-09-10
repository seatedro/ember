// odin run src/engine/test_gl -collection:ember=src -collection:game=game
package engine_gl_smoke

import engine ".."
import "core:fmt"
import "core:time"
import "ember:input"
import game "game:."
import gl "vendor:OpenGL"
import "vendor:glfw"

Mode :: enum {
	Normal,
	Fixed,
	Input,
	Init_Failure,
	Draw_Failure,
	Quit_During_Init,
}

Harness :: struct {
	game_config:  engine.Config,
	mode:         Mode,
	init_count:   int,
	update_count: int,
	draw_count:   int,
	quit_count:   int,
}

on_init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	h := cast(^Harness)userdata
	h.init_count += 1
	assert(app.device.initialized)
	assert(app.width > 0 && app.height > 0)
	assert(h.game_config.init(app, h.game_config.userdata))

	if h.mode == .Quit_During_Init {
		engine.request_quit(app)
	}
	return h.mode != .Init_Failure
}

on_update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	h := cast(^Harness)userdata
	h.update_count += 1
	assert(dt >= 0 && dt <= f32(1.0 / 15.0))
	assert(app.elapsed_time >= 0)
	if h.mode == .Fixed {
		assert(abs(dt - 0.001) < 0.000001)
	}
	if h.mode == .Input {
		check_update_input(app)
	}
	if h.game_config.update != nil {
		h.game_config.update(app, h.game_config.userdata, dt)
	}
	if app.frame_count >= 3 {
		engine.request_quit(app)
	}
}

on_draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	h := cast(^Harness)userdata
	if h.mode == .Draw_Failure {
		return false
	}
	assert(app.frame_count == u64(h.draw_count))
	assert(h.game_config.draw(app, h.game_config.userdata))
	if h.mode == .Input {
		// Update has consumed the tap before drawing.
		assert(!input.pressed(app.input, .F25) && !input.released(app.input, .F25))
		if app.frame_count == 0 {
			inject_tap()
		}
	}

	// Read the actual game's back buffer before engine presentation.
	center, corner: [4]u8
	gl.ReadPixels(app.width / 2, app.height / 2, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &center)
	gl.ReadPixels(0, app.height - 1, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &corner)
	difference := abs(int(center[0]) - 26) + abs(int(center[1]) - 26) + abs(int(center[2]) - 26)
	assert(difference > 30 && center[3] == 255)
	for i in 0 ..< 3 {
		assert(abs(int(corner[i]) - 26) <= 2)
	}
	assert(gl.GetError() == gl.NO_ERROR)
	h.draw_count += 1

	// Give the fixed update accumulator a measurable interval between frames.
	if h.mode == .Fixed {
		time.sleep(2 * time.Millisecond)
	}
	return true
}

on_quit :: proc(app: ^engine.Context, userdata: rawptr) {
	h := cast(^Harness)userdata
	h.quit_count += 1
	assert(app.device.initialized)
	h.game_config.quit(app, h.game_config.userdata)
	assert(app.device.buffers.free_count == len(app.device.buffers.slots))
	assert(app.device.shaders.free_count == len(app.device.shaders.slots))
	assert(app.device.pipelines.free_count == len(app.device.pipelines.slots))
}

main :: proc() {
	assert(engine.run({}) == .Invalid_Config)

	for mode in Mode {
		h := Harness {
			game_config = game.configure(),
			mode        = mode,
		}
		config := engine.Config {
			title    = "Ember engine smoke",
			width    = 96,
			height   = 96,
			hidden   = true,
			userdata = &h,
			init     = on_init,
			update   = on_update,
			draw     = on_draw,
			quit     = on_quit,
		}
		if mode == .Fixed {
			config.fixed_timestep = 0.001
		}

		err := engine.run(config)
		switch mode {
		case .Init_Failure:
			assert(err == .Init_Failed && h.draw_count == 0)
		case .Draw_Failure:
			assert(err == .Draw_Failed && h.draw_count == 0)
		case .Quit_During_Init:
			assert(err == .None && h.draw_count == 0 && h.update_count == 0)
		case .Normal, .Fixed, .Input:
			assert(err == .None && h.draw_count == 3 && h.update_count > 0)
		}
		assert(h.init_count == 1 && h.quit_count == 1)
	}

	fmt.println(
		"Engine smoke passed: game pixels, variable/fixed updates, input delivery, quit, failure cleanup",
	)
}

check_update_input :: proc(app: ^engine.Context) {
	expected := app.frame_count == 1
	assert(input.pressed(app.input, .F25) == expected)
	assert(input.released(app.input, .F25) == expected)
	assert(!input.down(app.input, .F25))
}

inject_tap :: proc() {
	// Events delivered during drawing must survive until the next update.
	// Invoke registered callbacks only; do not send system keyboard events.
	handle := glfw.GetCurrentContext()
	key := glfw.SetKeyCallback(handle, nil)
	focus := glfw.SetWindowFocusCallback(handle, nil)
	assert(key != nil && focus != nil)
	glfw.SetKeyCallback(handle, key)
	glfw.SetWindowFocusCallback(handle, focus)
	focus(handle, 1)
	key(handle, glfw.KEY_F25, 0, glfw.PRESS, 0)
	key(handle, glfw.KEY_F25, 0, glfw.RELEASE, 0)
}
