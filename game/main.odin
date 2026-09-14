package game

import "../examples/common"
import "core:log"
import "core:math"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import "ember:physics"
import render "ember:renderer"
import "ember:scene"
import "ember:shaders"
import "ember:ui"

State :: struct {
	debug_lines:                                             render.Debug_Lines,
	debug_error:                                             render.Error,
	physics_tab, query_mode, query_shape, query_total:       int,
	query_x, query_y, query_z:                               f32,
	query_probe, query_found:                                bool,
	query_hit:                                               physics.Query_Hit,
	query_overlaps:                                          [8]physics.Overlap_Hit,
	probe, probe_marker:                                     scene.Object,
	probe_body:                                              physics.Body_Handle,
	probe_thrust, probe_impulse, probe_spin, physics_failed: bool,
	world:                                                   scene.Scene,
	simulation:                                              ^engine.Clock,
	renderer:                                                render.Renderer,
	shaders:                                                 shaders.Library,
	draws:                                                   render.Draw_List,
	mesh:                                                    render.Mesh,
	pipeline:                                                render.Pipeline,
	materials:                                               [2]render.Material,
	target:                                                  render.Render_Target,
	presentation:                                            render.Presentation,
	orbit:                                                   camera.Orbit,
	overlay:                                                 common.Overlay,
	ui_failed:                                               bool,
	physics_window:                                          ui.Window,
	ui_scroll:                                               [2]f32,
	ui_layout_path:                                          string,
	saved_ui_layout:                                         []u8,
	next_ui_save:                                            f64,
	default_windows:                                         [1]ui.Window,
}

INITIAL_ORBIT :: camera.Orbit {
	pitch    = 0.3,
	distance = 16,
}
state: State

configure :: proc() -> engine.Config {
	return {
		title = "Ember",
		width = 1280,
		height = 720,
		vsync = true,
		userdata = &state,
		init = init,
		update = update,
		fixed_update = fixed_update,
		fixed_timestep = 1.0 / 60.0,
		draw = draw,
		quit = quit,
	}
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {
		orbit = INITIAL_ORBIT,
		physics_tab = 1,
		query_x = -5,
		query_probe = true,
		simulation = &app.simulation,
		physics_window = {
			id = ui.id("physics-window"),
			bounds = {{24, 24}, {384, 464}},
			minimum_size = {336, 160},
			open = true,
		},
	}
	if !init_physics(game) {
		return false
	}
	err: render.Error
	game.renderer, err = render.create(app.device)
	if !check(err, "create renderer") {
		return false
	}

	if !common.init_overlay(&game.overlay, app) {
		return false
	}
	game.overlay.interface.docking_enabled = true
	init_ui_layout(game)

	game.draws = render.create_draw_list()
	game.shaders = shaders.create(app.device)
	game.debug_lines, err = render.create_debug_lines(
		&game.renderer,
		&game.shaders,
		1024,
		depth_test = false,
	)
	if !check(err, "create debug lines") {
		return false
	}
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
		{
			{name = "albedo_texture", binding = 0},
			{name = "normal_texture", binding = 1},
			{name = "metallic_texture", binding = 2},
			{name = "roughness_texture", binding = 3},
		},
		lighting = true,
		environment = true,
	)
	if !check(err, "create pipeline") {
		return false
	}

	colors := [2][4]f32{{0.12, 0.4, 0.75, 1}, {0.85, 0.55, 0.18, 1}}
	for i in 0 ..< len(game.materials) {
		game.materials[i], err = render.create_lit_material(
			&game.renderer,
			shader,
			{tint = colors[i], roughness = 0.65},
			game.renderer.white_texture,
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

	game.target, err = render.create_render_target(
		&game.renderer,
		{width = 1280, height = 720, color_format = .RGBA16F, color_filter = .Nearest},
	)
	if !check(err, "create render target") {
		return false
	}

	game.presentation, err = render.create_presentation(&game.renderer, &game.shaders)
	return check(err, "create presentation")
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	if !build_ui(app, game) {
		game.ui_failed = true
		return
	}

	game_input := ui.remaining_input(&game.overlay.interface)
	if input.pressed(&game_input, .Escape) {
		engine.request_quit(app)
	}

	if input.pressed(&game_input, .Space) {
		game.simulation.paused = !game.simulation.paused
	}

	if input.pressed(&game_input, .R) {
		game.orbit = INITIAL_ORBIT
	}

	if input.mouse_down(&game_input, .Left) {
		camera.rotate_orbit(
			&game.orbit,
			{f32(game_input.mouse_delta.x) * 0.005, f32(game_input.mouse_delta.y) * 0.005},
			1.45,
		)
	}

	if game_input.scroll_delta.y != 0 {
		camera.zoom_orbit(&game.orbit, game_input.scroll_delta.y * 0.1, 3, 100)
	}

	if input.pressed(&game_input, .Period) {
		engine.step_clock(game.simulation)
	}
}

fixed_update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	update_physics(game, dt)
}

reset_simulation :: proc(game: ^State) {
	engine.reset_clock(game.simulation)
	reset_physics(game)
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.ui_failed || game.physics_failed {
		return false
	}

	render.clear_draw_list(&game.draws)
	if !draw_physics(game) {
		return false
	}

	if !check(
		render.begin_pass(&game.renderer, {target = &game.target}, common.BACKGROUND),
		"begin pass",
	) {
		return false
	}

	view := camera.from_orbit(game.orbit)
	projection := emath.perspective(
		math.PI / 3,
		f32(game.target.width) / f32(game.target.height),
		0.1,
		200,
	)
	lights := [1]render.Directional_Light {
		{direction = {1, 2, 3}, color = {1, 0.95, 0.85}, intensity = 3},
	}
	draw_error := render.draw_list(
		&game.renderer,
		&game.draws,
		view,
		projection,
		{ambient = {0.15, 0.15, 0.18}, directional_lights = lights[:]},
	)
	if draw_error == .None && game.physics_tab == 1 {
		if !update_queries(game) || !query_lines(game) {
			render.end_pass(&game.renderer)
			return false
		}
		draw_error = render.draw_debug_lines(&game.renderer, &game.debug_lines)
	}
	end_error := render.end_pass(&game.renderer)
	if !check(draw_error, "draw bodies") || !check(end_error, "end pass") {
		return false
	}

	if !check(
		render.present(
			&game.renderer,
			&game.presentation,
			game.target.color,
			render.pixel_viewport(
				{game.target.width, game.target.height},
				{app.width, app.height},
			),
		),
		"present",
	) {
		return false
	}

	return check(common.draw_overlay(&game.overlay, app), "draw overlay")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	scene.destroy(&game.world)
	check(render.destroy_debug_lines(&game.renderer, &game.debug_lines), "destroy debug lines")
	save_ui_layout(game)
	delete(game.ui_layout_path)
	delete(game.saved_ui_layout)
	common.destroy_overlay(&game.overlay, app.device)
	check(render.destroy_presentation(&game.renderer, &game.presentation), "destroy presentation")
	check(render.destroy_render_target(&game.renderer, &game.target), "destroy render target")
	for &material in game.materials {
		check(render.destroy_material(&game.renderer, &material), "destroy material")
	}
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
