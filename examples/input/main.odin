package game

import "../common"

import "core:fmt"
import "core:log"
import "ember:engine"
import "ember:input"
import "ember:rhi"
import "ember:ui"

State :: struct {
	surface:    common.Surface,
	overlay:    common.Overlay,
	window:     ui.Window,
	failed:     bool,
	focused:    bool,
	space_down: bool,
}

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - Input",
		width = 1280,
		height = 720,
		vsync = true,
		userdata = &state,
		init = init,
		update = update,
		draw = draw,
		quit = quit,
	}
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {
		window = common.info_window("input", 252),
	}
	if !common.init_surface(&game.surface, app.device) ||
	   !common.init_overlay(&game.overlay, app) {
		return false
	}

	game.focused = app.input.focused
	log.info(
		"Hold Space to change the background; drag left mouse for motion; scroll; Escape closes.",
	)
	log.info("Key and mouse transitions appear here. Switch applications to check focus handling.")
	return true
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	game.space_down = input.down(app.input, .Space)
	if app.input.focused != game.focused {
		game.focused = app.input.focused
		log.infof("Focused: %v", game.focused)
	}
	for key in input.Key {
		if input.pressed(app.input, key) {
			log.infof("Key pressed: %v", key)
		}
		if input.released(app.input, key) {
			log.infof("Key released: %v", key)
		}
	}
	for button in input.Mouse_Button {
		if input.mouse_pressed(app.input, button) {
			log.infof("Mouse pressed: %v", button)
		}
		if input.mouse_released(app.input, button) {
			log.infof("Mouse released: %v", button)
		}
	}
	if input.mouse_down(app.input, .Left) && app.input.mouse_delta != ([2]f64{}) {
		log.infof("Cursor: %v, delta: %v", app.input.mouse_position, app.input.mouse_delta)
	}
	if app.input.scroll_delta != ([2]f64{}) {
		log.infof("Scroll: %v", app.input.scroll_delta)
	}

	buffer: [512]u8
	text := fmt.bprintf(
		buffer[:],
		"Space held: %v\nFocused: %v\n\nSpace Change background\nDrag / scroll: log input\n\nF1  Toggle overlay\nEsc Close",
		game.space_down,
		game.focused,
	)
	game.failed = !common.info_panel(&game.overlay, app, &game.window, "INPUT", text)
	controls := ui.remaining_input(&game.overlay.interface)

	if input.pressed(&controls, .Escape) {
		engine.request_quit(app)
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.failed {
		return false
	}

	color := common.BACKGROUND
	if game.space_down {
		color = {0.1, 0.4, 0.25, 1}
	}

	if rhi.begin_pass(app.device, {target = game.surface.target.handle}, color) != .None {
		return false
	}

	if rhi.end_pass(app.device) != .None {
		return false
	}

	if !common.check(common.present_surface(&game.surface, app), "present") {
		return false
	}

	return common.check(common.draw_overlay(&game.overlay, app), "draw overlay")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	common.destroy_overlay(&game.overlay, app.device)
	common.destroy_surface(&game.surface)
	game^ = {}
}
