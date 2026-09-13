package game

import "core:log"
import "core:math"
import emath "ember:core/math"
import render "ember:renderer"
import shader "ember:shaders"

Unlit_Parameters :: struct {
	tint: [4]f32,
}

LIGHT_COLORS :: [2]emath.Vec3{{1, 0.9, 0.7}, {0.35, 0.65, 1}}

init_light :: proc(game: ^State) -> bool {
	game.lights[0] = {
		position  = {0, 2, 3},
		color     = LIGHT_COLORS[0],
		intensity = 2,
		range     = 7,
	}

	program, shader_error := shader.load(&game.shaders, "game/assets/shaders/unlit")
	if shader_error != .None {
		log.errorf("Load unlit shader: %v", shader_error)
		return false
	}

	err: render.Error
	game.light_pipeline, err = render.create_pipeline(
		&game.renderer,
		program,
		{
			layout = SPHERE_LAYOUT,
			primitive = .Triangles,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = .Back, winding = .CCW},
		},
	)
	if !check(err, "create light marker pipeline") {
		return false
	}

	color := game.lights[0].color
	game.light_material, err = render.create_material(
		&game.renderer,
		program,
		Unlit_Parameters{tint = {color.x, color.y, color.z, 1}},
	)
	return check(err, "create light marker material")
}

toggle_light_color :: proc(game: ^State) -> bool {
	color := LIGHT_COLORS[0]
	if game.lights[0].color == color {
		color = LIGHT_COLORS[1]
	}

	if !check(
		render.update_material(
			&game.renderer,
			&game.light_material,
			Unlit_Parameters{tint = {color.x, color.y, color.z, 1}},
		),
		"update light marker color",
	) {
		return false
	}

	game.lights[0].color = color
	return true
}

update_light :: proc(game: ^State, dt: f32) {
	if game.light_paused {
		return
	}

	game.light_angle = math.mod(game.light_angle + dt * 0.5, f32(2 * math.PI))
	game.lights[0].position = {3.5 * math.sin(game.light_angle), 2, 3 * math.cos(game.light_angle)}
}
