package game

import "../examples/common"

import "core:log"
import "core:math"
import "ember:engine"
import "ember:input"
import render "ember:renderer"

init_presentation :: proc(game: ^State) -> bool {
	game.presentation = {
		exposure     = 1,
		tone_mapping = .Reinhard,
	}

	err: render.Error
	game.presenter, err = render.create_presentation(&game.renderer, &game.shaders)
	if !check(err, "create presentation") {
		return false
	}

	game.target, err = common.create_pixel_target(&game.renderer, &game.shaders)
	return check(err, "create pixel target")
}

update_presentation :: proc(game: ^State, controls: ^input.State) {
	settings := game.presentation
	if input.pressed(controls, .O) {
		settings.tone_mapping = .ACES_Fitted if settings.tone_mapping == .Reinhard else .Reinhard
	}

	if input.pressed(controls, .Minus) {
		settings.exposure /= math.sqrt(f32(2))
	}

	if input.pressed(controls, .Equal) {
		settings.exposure *= math.sqrt(f32(2))
	}

	settings.exposure = clamp(settings.exposure, 1.0 / 256.0, 256.0)
	if settings == game.presentation {
		return
	}

	game.presentation = settings
	log.infof("Tone mapping: %v, exposure: %.2f", settings.tone_mapping, settings.exposure)
}

present :: proc(game: ^State, app: ^engine.Context) -> bool {
	if !check(common.resolve_pixels(&game.renderer, &game.target), "resolve pixels") {
		return false
	}

	return check(
		render.present(
			&game.renderer,
			&game.presenter,
			game.target.pixels.color,
			render.pixel_viewport(common.RESOLUTION, {app.width, app.height}),
			game.presentation,
		),
		"present",
	)
}

destroy_presentation :: proc(game: ^State) {
	check(render.destroy_presentation(&game.renderer, &game.presenter), "destroy presentation")
	common.destroy_pixel_target(&game.renderer, &game.target)
}
