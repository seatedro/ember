package game

import "core:log"
import "ember:image"
import render "ember:renderer"

toggle_material_texture :: proc(game: ^State) -> bool {
	texture := game.textures[0]
	if game.materials[0].textures[0] == texture.handle {
		texture = game.textures[1]
	}

	return check(
		render.set_material_texture(&game.renderer, &game.materials[0], 0, texture),
		"replace material texture",
	)
}

init_textures :: proc(game: ^State) -> bool {
	PATH :: "examples/sphere/assets/textures/earth_daymap.jpg"
	earth, image_error := image.load(PATH)
	if image_error != .None {
		log.errorf("Load image %s: %v", PATH, image_error)
		return false
	}
	defer image.destroy(&earth)

	err: render.Error
	game.textures[0], err = render.create_texture(
		&game.renderer,
		{
			width = earth.width,
			height = earth.height,
			format = .RGBA8_SRGB,
			filter = .Linear,
			wrap_v = .Clamp,
			label = "Earth day map",
		},
		earth.pixels,
	)
	if !check(err, "create Earth texture") {
		return false
	}

	white := [4]u8{255, 255, 255, 255}
	game.textures[1], err = render.create_texture(
		&game.renderer,
		{width = 1, height = 1, label = "white"},
		white[:],
	)

	return check(err, "create white texture")
}
