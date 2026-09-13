package game

import "core:log"
import "core:math"
import "ember:engine"
import "ember:input"
import render "ember:renderer"

init_presentation :: proc(game: ^State, width, height: i32) -> bool {
	game.presentation = {
		exposure     = 1,
		tone_mapping = .Reinhard,
	}

	err: render.Error
	game.presenter, err = render.create_presentation(&game.renderer, &game.shaders)
	if !check(err, "create presentation") {
		return false
	}

	return resize_target(game, width, height)
}

update_presentation :: proc(game: ^State, app: ^engine.Context) {
	settings := game.presentation
	if input.pressed(app.input, .O) {
		settings.tone_mapping = .ACES_Fitted if settings.tone_mapping == .Reinhard else .Reinhard
	}

	if input.pressed(app.input, .Minus) {
		settings.exposure /= math.sqrt(f32(2))
	}

	if input.pressed(app.input, .Equal) {
		settings.exposure *= math.sqrt(f32(2))
	}

	settings.exposure = clamp(settings.exposure, 1.0 / 256.0, 256.0)
	if settings == game.presentation {
		return
	}

	game.presentation = settings
	log.infof("Tone mapping: %v, exposure: %.2f", settings.tone_mapping, settings.exposure)
}

resize_target :: proc(game: ^State, width, height: i32) -> bool {
	if game.target.width == width && game.target.height == height {
		return true
	}

	err: render.Error
	game.next_target, err = render.create_render_target(
		&game.renderer,
		{
			width = width,
			height = height,
			color_format = .RGBA16F,
			color_filter = .Nearest,
			label = "demo color",
		},
	)
	if !check(err, "create resized render target") {
		return false
	}

	if !check(
		render.destroy_render_target(&game.renderer, &game.target),
		"release old render target",
	) {
		return false
	}

	game.target = game.next_target
	game.next_target = {}
	return true
}

present :: proc(game: ^State, app: ^engine.Context) -> bool {
	return check(
		render.present(
			&game.renderer,
			&game.presenter,
			game.target.color,
			{width = app.width, height = app.height},
			game.presentation,
		),
		"present",
	)
}

destroy_presentation :: proc(game: ^State) {
	check(render.destroy_presentation(&game.renderer, &game.presenter), "destroy presentation")
	check(
		render.destroy_render_target(&game.renderer, &game.next_target),
		"destroy replacement target",
	)
	check(render.destroy_render_target(&game.renderer, &game.target), "destroy target")
}
