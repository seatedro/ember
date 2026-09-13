package game

import "ember:engine"

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - drag/scroll camera, Space pauses light, C light color, T texture, M materials, R resets, Esc closes",
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
