package game

import emath "ember:core/math"
import "ember:geometry"
import render "ember:renderer"

init_blending :: proc(game: ^State) -> bool {
	quad := geometry.create_quad()
	err: render.Error
	game.blend_mesh, err = render.create_mesh(
		&game.renderer,
		quad.vertices[:],
		quad.indices[:],
		render.VERTEX_LAYOUT,
		quad.bounds,
	)
	if !check(err, "create blend mesh") {
		return false
	}

	settings := render.Pipeline_Settings {
		layout = render.VERTEX_LAYOUT,
		primitive = .Triangles,
		depth = {test_enabled = true, write_enabled = false, compare = .Less},
		raster = {cull = .None},
		blend = {
			enabled = true,
			src_factor_rgb = .Src_Alpha,
			dst_factor_rgb = .One_Minus_Src_Alpha,
			src_factor_alpha = .One,
			dst_factor_alpha = .One_Minus_Src_Alpha,
		},
	}

	program := game.light_pipeline.shader
	for &pipeline, i in game.blend_pipelines {
		if i == 1 {
			settings.blend.dst_factor_rgb = .One
		}

		pipeline, err = render.create_pipeline(&game.renderer, program, settings)
		if !check(err, "create blend pipeline") {
			return false
		}
	}

	for tint, i in ([2][4]f32{{1, 0.15, 0.08, 0.35}, {0.08, 0.45, 1, 0.35}}) {
		game.blend_materials[i], err = render.create_material(
			&game.renderer,
			program,
			render.Tint_Parameters{tint = tint},
		)
		if !check(err, "create blend material") {
			return false
		}
	}

	game.blend_transforms = {
		{
			position = {0, 0.3, 1.5},
			orientation = emath.quaternion_angle_axis(-0.3, {0, 0, 1}),
			scale = {1.2, 1.1, 1},
		},
		{
			position = {0, 0.3, 2},
			orientation = emath.quaternion_angle_axis(0.3, {0, 0, 1}),
			scale = {1.2, 1.1, 1},
		},
	}

	return true
}

add_blending :: proc(game: ^State) -> bool {
	pipeline := game.blend_pipelines[1 if game.additive_blending else 0]
	for transform, i in game.blend_transforms {
		if !check(
			render.add_draw(
				&game.draws,
				{
					pipeline = pipeline,
					mesh = game.blend_mesh,
					material = game.blend_materials[i],
					transform = transform,
					order = .Transparent,
				},
			),
			"submit blended panel",
		) {
			return false
		}
	}

	return true
}

destroy_blending :: proc(game: ^State) {
	for &material in game.blend_materials {
		check(render.destroy_material(&game.renderer, &material), "destroy blend material")
	}

	for &pipeline in game.blend_pipelines {
		check(render.destroy_pipeline(&game.renderer, &pipeline), "destroy blend pipeline")
	}

	check(render.destroy_mesh(&game.renderer, &game.blend_mesh), "destroy blend mesh")
}
