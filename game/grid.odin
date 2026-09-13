package game

import render "ember:renderer"

init_grid :: proc(game: ^State) -> bool {
	err: render.Error
	game.grid, err = render.create_debug_grid(
		&game.renderer,
		&game.shaders,
		extent = 10,
		spacing = 1,
	)
	return check(err, "create debug grid")
}
