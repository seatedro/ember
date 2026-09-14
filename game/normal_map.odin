package game

import "core:math"
import emath "ember:core/math"
import render "ember:renderer"

create_dimple_normal_map :: proc(renderer: ^render.Renderer) -> (render.Texture, render.Error) {
	SIZE :: 128
	pixels: [SIZE * SIZE * 4]u8
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			u := (f32(x % (SIZE / 2)) + 0.5) / (SIZE / 2) - 0.5
			v := (f32(y % (SIZE / 2)) + 0.5) / (SIZE / 2) - 0.5
			radius_squared := u * u + v * v
			gradient := 3 * max(1 - radius_squared / 0.16, 0)
			normal := emath.normalize({-u * gradient, -v * gradient, 1})
			offset := (y * SIZE + x) * 4
			for component, channel in normal {
				pixels[offset + channel] = u8(math.round((component * 0.5 + 0.5) * 255))
			}
			pixels[offset + 3] = 255
		}
	}
	return render.create_texture(
		renderer,
		{width = SIZE, height = SIZE, format = .RGBA8, label = "dimples"},
		pixels[:],
	)
}
