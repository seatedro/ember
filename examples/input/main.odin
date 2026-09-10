package game

import "core:log"
import "ember:engine"
import "ember:input"
import "ember:rhi"

State :: struct {
	focused:    bool,
	space_down: bool,
}

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - Input: hold Space, drag, scroll; Escape closes",
		width = 960,
		height = 540,
		vsync = true,
		userdata = &state,
		init = init,
		update = update,
		draw = draw,
	}
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
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
	if input.pressed(app.input, .Escape) {
		engine.request_quit(app)
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	color: [4]f32 = {0.1, 0.1, 0.1, 1}
	if game.space_down {
		color = {0.1, 0.4, 0.25, 1}
	}
	rhi.clear(app.device, color, 1)
	return true
}
