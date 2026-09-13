package game

import "core:log"
import "core:math"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import render "ember:renderer"
import "ember:shaders"

State :: struct {
	renderer:            render.Renderer,
	shaders:             shaders.Library,
	draws:               render.Draw_List,
	mesh:                render.Mesh,
	pipeline:            render.Pipeline,
	materials:           [2]render.Material,
	texture:             render.Texture,
	presentation:        render.Presentation,
	target, next_target: render.Render_Target,
	orbit:               camera.Orbit,
	angle:               f32,
	batching, paused:    bool,
	last_stats:          render.Draw_Stats,
	next_report:         f64,
}

INITIAL_ORBIT :: camera.Orbit {
	pitch    = 0.6,
	distance = 58,
}
state: State

configure :: proc() -> engine.Config {
	return {
		title = "Ember Instancing - B batching, drag/scroll camera, Space pause, R reset, Esc close; counts in console",
		width = 1280,
		height = 720,
		vsync = true,
		userdata = &state,
		init = init,
		update = update,
		draw = draw,
		quit = quit,
	}
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {
		orbit    = INITIAL_ORBIT,
		batching = true,
	}
	err: render.Error
	game.renderer, err = render.create(app.device)
	if !check(err, "create renderer") {
		return false
	}

	game.draws = render.create_draw_list()
	game.shaders = shaders.create(app.device)
	shader, shader_error := render.load_builtin_shader(&game.shaders, .Lit)
	if shader_error != .None {
		log.errorf("Load lit shader: %v", shader_error)
		return false
	}

	game.pipeline, err = render.create_pipeline(
		&game.renderer,
		shader,
		{
			layout = render.VERTEX_LAYOUT,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = .Back, winding = .CCW},
		},
		{{name = "albedo_texture", binding = 0}},
		lighting = true,
	)
	if !check(err, "create pipeline") {
		return false
	}

	game.texture, err = render.create_texture(
		&game.renderer,
		{width = 1, height = 1, format = .RGBA8},
		{255, 255, 255, 255},
	)
	if !check(err, "create texture") {
		return false
	}

	for color, i in ([2][4]f32{{0.12, 0.4, 0.75, 1}, {0.85, 0.3, 0.08, 1}}) {
		game.materials[i], err = render.create_material(
			&game.renderer,
			shader,
			render.Tint_Parameters{tint = color},
			{{binding = 0, texture = game.texture}},
		)
		if !check(err, "create material") {
			return false
		}
	}

	mesh, geometry_error := geometry.create_sphere(segments = 16, stacks = 8)
	if geometry_error != .None {
		log.errorf("Generate sphere: %v", geometry_error)
		return false
	}

	defer geometry.destroy_sphere(&mesh)
	game.mesh, err = render.create_mesh(
		&game.renderer,
		mesh.vertices,
		mesh.indices,
		render.VERTEX_LAYOUT,
		mesh.bounds,
	)
	if !check(err, "create mesh") {
		return false
	}

	game.presentation, err = render.create_presentation(&game.renderer, &game.shaders)
	return check(err, "create presentation")
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	if input.pressed(app.input, .Escape) {
		engine.request_quit(app)
	}

	if input.pressed(app.input, .B) {
		game.batching = !game.batching
		game.next_report = 0
	}

	if input.pressed(app.input, .Space) {
		game.paused = !game.paused
	}

	if input.pressed(app.input, .R) {
		game.orbit = INITIAL_ORBIT
	}

	if input.mouse_down(app.input, .Left) {
		camera.rotate_orbit(
			&game.orbit,
			{f32(app.input.mouse_delta.x) * 0.005, f32(app.input.mouse_delta.y) * 0.005},
			1.45,
		)
	}

	if app.input.scroll_delta.y != 0 {
		camera.zoom_orbit(&game.orbit, app.input.scroll_delta.y * 0.1, 3, 100)
	}

	if !game.paused {
		game.angle += dt * 0.3
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.target.width != app.width || game.target.height != app.height {
		err: render.Error
		game.next_target, err = render.create_render_target(
			&game.renderer,
			{width = app.width, height = app.height, color_format = .RGBA16F},
		)
		if !check(err, "create target") {
			return false
		}

		if !check(
			render.destroy_render_target(&game.renderer, &game.target),
			"destroy old target",
		) {
			return false
		}

		game.target = game.next_target
		game.next_target = {}
	}

	render.clear_draw_list(&game.draws)
	for z in 0 ..< 20 {
		for x in 0 ..< 20 {
			transform := emath.Transform {
				position    = {
					(f32(x) - 9.5) * 2.5,
					math.sin(f32(x + z) * 0.4),
					(f32(z) - 9.5) * 2.5,
				},
				orientation = emath.quaternion_angle_axis(
					game.angle + f32(x) * 0.2,
					emath.normalize({1, 1, 0}),
				),
				scale       = {0.7, 1.0, 0.7},
			}
			if !check(
				render.add_draw(
					&game.draws,
					{
						mesh = game.mesh,
						pipeline = game.pipeline,
						material = game.materials[(x + z) % 2],
						transform = transform,
					},
				),
				"submit sphere",
			) {
				return false
			}
		}
	}

	if !check(
		render.begin_pass(&game.renderer, {target = &game.target}, {0.02, 0.025, 0.04, 1}),
		"begin pass",
	) {
		return false
	}

	lights := [1]render.Point_Light {
		{position = {-15, 30, 20}, color = {1, 0.9, 0.8}, intensity = 3, range = 130},
	}
	draw_error := render.draw_list(
		&game.renderer,
		&game.draws,
		camera.from_orbit(game.orbit),
		emath.perspective(math.PI / 3, f32(app.width) / f32(app.height), 0.1, 200),
		{ambient = {0.12, 0.14, 0.2}, point_lights = lights[:]},
		batching = game.batching,
	)
	end_error := render.end_pass(&game.renderer)
	if !check(draw_error, "draw instances") || !check(end_error, "end pass") {
		return false
	}

	stats := game.draws.stats
	if app.elapsed_time >= game.next_report &&
	   (stats != game.last_stats || game.next_report == 0) {
		log.infof(
			"Batching %v: %d submitted, %d visible, %d mesh draws",
			game.batching,
			stats.submitted,
			stats.visible,
			stats.draw_calls,
		)
		game.last_stats = stats
		game.next_report = app.elapsed_time + 0.5
	}

	return check(
		render.present(
			&game.renderer,
			&game.presentation,
			game.target.color,
			{width = app.width, height = app.height},
		),
		"present",
	)
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	check(render.destroy_presentation(&game.renderer, &game.presentation), "destroy presentation")
	check(
		render.destroy_render_target(&game.renderer, &game.next_target),
		"destroy pending target",
	)
	check(render.destroy_render_target(&game.renderer, &game.target), "destroy target")
	for &material in game.materials {
		check(render.destroy_material(&game.renderer, &material), "destroy material")
	}

	check(render.destroy_texture(&game.renderer, &game.texture), "destroy texture")
	check(render.destroy_mesh(&game.renderer, &game.mesh), "destroy mesh")
	check(render.destroy_pipeline(&game.renderer, &game.pipeline), "destroy pipeline")
	check(render.destroy(&game.renderer), "destroy renderer")
	render.destroy_draw_list(&game.draws)
	if err := shaders.destroy(&game.shaders); err != .None {
		log.errorf("Destroy shaders: %v", err)
	}
}

check :: proc(err: render.Error, operation: string) -> bool {
	if err != .None {
		log.errorf("%s: %v", operation, err)
	}

	return err == .None
}
