package game

import render "ember:renderer"

init_textures :: proc(game: ^State) -> bool {
	WIDTH :: 32
	HEIGHT :: 16
	pixels: [WIDTH * HEIGHT * 4]u8
	for y in 0 ..< HEIGHT {
		for x in 0 ..< WIDTH {
			value := u8(255) if (x / 4 + y / 4) % 2 == 0 else u8(70)
			i := (y * WIDTH + x) * 4
			pixels[i + 0], pixels[i + 1], pixels[i + 2], pixels[i + 3] = value, value, value, 255
		}
	}
	err: render.Error
	game.textures[0], err = render.create_texture(
		&game.renderer,
		{
			width = WIDTH,
			height = HEIGHT,
			filter = .Nearest,
			wrap_v = .Clamp,
			label = "checkerboard",
		},
		pixels[:],
	)
	if !check(err, "create checkerboard texture") {return false}
	white := [4]u8{255, 255, 255, 255}
	game.textures[1], err = render.create_texture(
		&game.renderer,
		{width = 1, height = 1, label = "white"},
		white[:],
	)
	return check(err, "create white texture")
}
