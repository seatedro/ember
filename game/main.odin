package game

import "ember:engine"

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - Sphere",
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
