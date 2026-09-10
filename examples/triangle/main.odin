package game

import "ember:engine"

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - Triangle",
		width = 1280,
		height = 720,
		vsync = true,
		userdata = &state,
		init = init,
		draw = draw,
		quit = quit,
	}
}
