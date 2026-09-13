package game

import "ember:engine"

state: State

configure :: proc() -> engine.Config {
	return engine.Config {
		title = "Ember - drag to orbit, scroll to zoom, Space pauses light, M swaps materials, R resets, Escape closes",
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
