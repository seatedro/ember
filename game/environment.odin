package game

import "core:math"
import "core:math/linalg"
import "ember:camera"
import emath "ember:core/math"
import render "ember:renderer"
import "ember:shaders"
import "ember:ui"

Environment_Uniforms :: struct {
	inverse_view_projection: emath.Mat4,
	sun:                     [4]f32,
}

init_environment :: proc(game: ^State) -> bool {
	err: render.Error
	game.environment, err = render.create_environment(&game.renderer, &game.shaders)
	if !check(err, "create environment") {
		return false
	}
	game.environment_capture, err = render.create_render_target(
		&game.renderer,
		{kind = .Cube, width = 128, height = 128, color_format = .RGBA16F, color_filter = .Linear},
	)
	if !check(err, "create environment capture") {
		return false
	}
	program, shader_error := shaders.load_source(
		&game.shaders,
		"game/environment",
		#partial shaders.Sources {
			.MSL = {
				vertex = {
					entry_point = "screen_vertex",
					code = render.MSL_COMMON_SOURCE + #load("msl/environment.metal", string),
				},
				fragment = {
					entry_point = "environment_fragment",
					code = render.MSL_COMMON_SOURCE + #load("msl/environment.metal", string),
				},
			},
			.GLSL = {
				vertex = {
					entry_point = "main",
					code = render.GLSL_INSTANCE_SOURCE +
					#load("../src/renderer/glsl/present.vert", string),
				},
				fragment = {entry_point = "main", code = #load("glsl/environment.frag", string)},
			},
		},
	)
	if shader_error != .None {
		return false
	}
	game.environment_pipeline, err = render.create_pipeline(
		&game.renderer,
		program,
		{layout = render.VERTEX_LAYOUT},
	)
	if !check(err, "create environment pipeline") {
		return false
	}
	game.environment_material, err = render.create_material(
		&game.renderer,
		program,
		Environment_Uniforms{},
	)
	return check(err, "create environment material")
}

capture_environment :: proc(
	renderer: ^render.Renderer,
	view: camera.Camera,
	projection: emath.Mat4,
	userdata: rawptr,
) -> render.Error {
	game := cast(^State)userdata
	pose := view
	pose.position = {}
	parameters := Environment_Uniforms {
		inverse_view_projection = linalg.inverse(projection * camera.view_matrix(pose)),
		sun                     = {
			math.cos(game.environment_sun) * 0.8,
			0.6,
			math.sin(game.environment_sun) * 0.8,
			12,
		},
	}
	if err := render.update_material(renderer, &game.environment_material, parameters);
	   err != .None {
		return err
	}
	if err := render.set_view(renderer, {orientation = 1}, emath.identity()); err != .None {
		return err
	}
	return render.draw_mesh(
		renderer,
		&game.environment_pipeline,
		&game.environment.mesh,
		&game.environment_material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

refresh_environment :: proc(game: ^State) -> bool {
	if !game.environment_dirty {
		return true
	}
	if !check(
		render.capture_cubemap(
			&game.renderer,
			&game.environment_capture,
			{},
			0.1,
			100,
			capture_environment,
			game,
		),
		"capture environment",
	) {
		return false
	}
	if !check(
		render.update_environment(
			&game.renderer,
			&game.environment,
			game.environment_capture.color,
		),
		"filter environment",
	) {
		return false
	}
	game.environment_dirty = false
	return true
}

environment_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 24)
	if !check_ui(err) {
		return false
	}
	_, control_error := ui.checkbox(
		ctx,
		ui.id("environment-enabled"),
		rect,
		"ENABLED",
		&game.environment_enabled,
	)
	if !check_ui(control_error) {
		return false
	}
	previous_sun := game.environment_sun
	for control in ([3]struct {
			name, label: string,
			value:       ^f32,
			high:        f32,
		} {
			{"environment-intensity", "INTENSITY", &game.environment_intensity, 4},
			{"environment-rotation", "ROTATION", &game.environment_rotation, 6.28},
			{"environment-sun", "SUN POSITION", &game.environment_sun, 6.28},
		}) {
		rect, err = ui.next(column, 48)
		if !check_ui(err) {
			return false
		}
		_, control_error = ui.slider(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
			0,
			control.high,
			step = 0.01,
		)
		if !check_ui(control_error) {
			return false
		}
	}
	game.environment_dirty = game.environment_dirty || previous_sun != game.environment_sun
	return true
}

quit_environment :: proc(game: ^State) {
	check(
		render.destroy_material(&game.renderer, &game.environment_material),
		"destroy environment material",
	)
	check(
		render.destroy_pipeline(&game.renderer, &game.environment_pipeline),
		"destroy environment pipeline",
	)
	check(render.destroy_environment(&game.renderer, &game.environment), "destroy environment")
	check(
		render.destroy_render_target(&game.renderer, &game.environment_capture),
		"destroy environment capture",
	)
}
