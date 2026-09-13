package game

import "ember:engine"

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - drag/scroll camera, Space pause, C light, T texture, M material, B blend, O tone map, -/+ exposure, R reset, Esc close",
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
