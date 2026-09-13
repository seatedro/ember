package game

import "core:log"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import render "ember:renderer"
import shader "ember:shaders"

init_presentation :: proc(game: ^State, width, height: i32) -> bool {
	program, shader_error := shader.load(&game.shaders, "game/assets/shaders/present")
	if shader_error != .None {
		log.errorf("Load presentation shader: %v", shader_error)
		return false
	}

	err: render.Error
	game.target, err = render.create_render_target(
		&game.renderer,
		{width = width, height = height, label = "demo color"},
	)
	if !check(err, "create render target") {
		return false
	}

	game.present_pipeline, err = render.create_pipeline(
		&game.renderer,
		program,
		{layout = SPHERE_LAYOUT, primitive = .Triangles},
		{{name = "source_texture", binding = 0}},
	)
	if !check(err, "create presentation pipeline") {
		return false
	}

	game.present_material, err = render.create_material(
		&game.renderer,
		program,
		Unlit_Parameters{tint = {1, 1, 1, 1}},
		{{binding = 0, texture = game.target.color}},
	)
	if !check(err, "create presentation material") {
		return false
	}

	vertices := [4]geometry.Vertex {
		{{-1, -1, 0}, {0, 0, 1}, {0, 0}},
		{{1, -1, 0}, {0, 0, 1}, {1, 0}},
		{{1, 1, 0}, {0, 0, 1}, {1, 1}},
		{{-1, 1, 0}, {0, 0, 1}, {0, 1}},
	}

	indices := [6]u32{0, 1, 2, 0, 2, 3}
	game.present_mesh, err = render.create_mesh(
		&game.renderer,
		vertices[:],
		indices[:],
		SPHERE_LAYOUT,
	)
	return check(err, "create presentation mesh")
}

resize_target :: proc(game: ^State, width, height: i32) -> bool {
	if game.target.width == width && game.target.height == height {
		return true
	}

	err: render.Error
	game.next_target, err = render.create_render_target(
		&game.renderer,
		{width = width, height = height, label = "demo color"},
	)
	if !check(err, "create resized render target") {
		return false
	}

	if !check(
		render.set_material_texture(
			&game.renderer,
			&game.present_material,
			0,
			game.next_target.color,
		),
		"update presentation texture",
	) {
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
	if !check(
		render.begin_pass(&game.renderer, {viewport = {width = app.width, height = app.height}}),
		"begin window pass",
	) {
		return false
	}

	defer check(render.end_pass(&game.renderer), "end window pass")
	if !check(
		render.set_view(&game.renderer, {orientation = 1}, emath.identity()),
		"set presentation view",
	) {
		return false
	}

	return check(
		render.draw_mesh(
			&game.renderer,
			&game.present_pipeline,
			&game.present_mesh,
			&game.present_material,
			{orientation = 1, scale = {1, 1, 1}},
		),
		"present color texture",
	)
}

destroy_presentation :: proc(game: ^State) {
	check(
		render.destroy_material(&game.renderer, &game.present_material),
		"destroy presentation material",
	)
	check(
		render.destroy_pipeline(&game.renderer, &game.present_pipeline),
		"destroy presentation pipeline",
	)
	check(render.destroy_mesh(&game.renderer, &game.present_mesh), "destroy presentation mesh")
	check(
		render.destroy_render_target(&game.renderer, &game.next_target),
		"destroy replacement target",
	)
	check(render.destroy_render_target(&game.renderer, &game.target), "destroy render target")
}
