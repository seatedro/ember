package game

import "../common"

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
import "ember:ui"

INITIAL_ORBIT :: camera.Orbit {
	pitch    = 0.3,
	distance = 16,
}

Tab :: enum {
	Motion,
	Queries,
	Contacts,
}

State :: struct {
	surface:    common.Surface,
	overlay:    common.Overlay,
	panel:      Panel,
	draws:      render.Draw_List,
	lines:      render.Debug_Lines,
	line_error: render.Error,
	mesh:       render.Mesh,
	pipeline:   render.Pipeline,
	materials:  [2]render.Material,
	orbit:      camera.Orbit,
	world:      scene.Scene,
	simulation: ^engine.Clock,
	tab:        Tab,
	motion:     Motion,
	queries:    Queries,
	contacts:   Contacts,
	failed:     bool,
}

state: State

configure :: proc() -> engine.Config {
	return {
		title = "Ember - Physics",
		width = 1280,
		height = 720,
		vsync = true,
		userdata = &state,
		init = init,
		update = update,
		fixed_update = fixed_update,
		fixed_timestep = 1.0 / 60.0,
		late_update = late_update,
		draw = draw,
		quit = quit,
	}
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {
		orbit = INITIAL_ORBIT,
		tab = .Contacts,
		simulation = &app.simulation,
		queries = {origin = {-5, 0, 0}, include_probe = true},
		contacts = {friction = 0.5, restitution = 0.15},
	}
	if !init_scene(game) {
		return false
	}

	if !common.init_surface(&game.surface, app.device) ||
	   !common.init_overlay(&game.overlay, app) {
		return false
	}
	game.overlay.interface.docking_enabled = true
	init_panel(game)

	err: render.Error
	game.draws = render.create_draw_list()
	game.lines, err = render.create_debug_lines(
		&game.surface.renderer,
		&game.surface.shaders,
		1024,
		depth_test = false,
	)
	if !common.check(err, "create debug lines") {
		return false
	}

	shader, shader_error := render.load_builtin_shader(&game.surface.shaders, .Lit)
	if shader_error != .None {
		log.errorf("Load lit shader: %v", shader_error)
		return false
	}

	game.pipeline, err = render.create_pipeline(
		&game.surface.renderer,
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
	if !common.check(err, "create pipeline") {
		return false
	}

	colors := [2][4]f32{{0.12, 0.4, 0.75, 1}, {0.85, 0.55, 0.18, 1}}
	for &material, i in game.materials {
		material, err = render.create_lit_material(
			&game.surface.renderer,
			shader,
			{tint = colors[i], roughness = 0.65},
			game.surface.renderer.white_texture,
		)
		if !common.check(err, "create material") {
			return false
		}
	}

	sphere, geometry_error := geometry.create_sphere(segments = 16, stacks = 8)
	if geometry_error != .None {
		log.errorf("Generate sphere: %v", geometry_error)
		return false
	}

	defer geometry.destroy_sphere(&sphere)
	game.mesh, err = render.create_mesh(
		&game.surface.renderer,
		sphere.vertices,
		sphere.indices,
		render.VERTEX_LAYOUT,
		sphere.bounds,
	)
	return common.check(err, "create mesh")
}

init_scene :: proc(game: ^State) -> bool {
	err: scene.Error
	game.world, err = scene.create(8)
	return check_scene(err) && init_motion(game) && init_queries(game) && init_contacts(game)
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	if !build_ui(app, game) {
		game.failed = true
		return
	}

	controls := ui.remaining_input(&game.overlay.interface)
	if input.pressed(&controls, .Escape) {
		engine.request_quit(app)
	}

	if input.pressed(&controls, .Space) {
		game.simulation.paused = !game.simulation.paused
	}

	if input.pressed(&controls, .Period) {
		engine.step_clock(game.simulation)
	}

	if input.pressed(&controls, .R) {
		game.orbit = INITIAL_ORBIT
	}

	if input.mouse_down(&controls, .Left) {
		camera.rotate_orbit(
			&game.orbit,
			{f32(controls.mouse_delta.x) * 0.005, f32(controls.mouse_delta.y) * 0.005},
			1.45,
		)
	}

	if controls.scroll_delta.y != 0 {
		camera.zoom_orbit(&game.orbit, controls.scroll_delta.y * 0.1, 3, 100)
	}
}

fixed_update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	ok := apply_motion(game) && update_contacts(game, dt)
	ok = check_physics(physics.step(&game.world.physics, dt)) && ok
	read_contacts(game)
	game.failed = game.failed || !ok
}

late_update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	if game.tab == .Queries && !run_query(game) {
		game.failed = true
	}
}

reset_simulation :: proc(game: ^State) {
	engine.reset_clock(game.simulation)
	game.failed = game.failed || !reset_motion(game) || !reset_contacts(game)
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.failed {
		return false
	}

	render.clear_draw_list(&game.draws)
	if !draw_probe(game) {
		return false
	}

	renderer := &game.surface.renderer
	if !common.check(
		render.begin_pass(renderer, {target = &game.surface.target.world}, common.BACKGROUND),
		"begin pass",
	) {
		return false
	}

	target := game.surface.target.world
	projection := emath.perspective(math.PI / 3, f32(target.width) / f32(target.height), 0.1, 200)
	lights := [1]render.Directional_Light {
		{direction = {1, 2, 3}, color = {1, 0.95, 0.85}, intensity = 3},
	}
	draw_error := render.draw_list(
		renderer,
		&game.draws,
		camera.from_orbit(game.orbit),
		projection,
		{ambient = {0.15, 0.15, 0.18}, directional_lights = lights[:]},
	)
	lines_ok := true
	if draw_error == .None && game.tab != .Motion {
		render.clear_debug_lines(&game.lines)
		game.line_error = .None
		lines_ok = query_lines(game) if game.tab == .Queries else contact_lines(game)
		if lines_ok {
			draw_error = render.draw_debug_lines(renderer, &game.lines)
		}
	}
	end_error := render.end_pass(renderer)
	if !lines_ok ||
	   !common.check(draw_error, "draw scene") ||
	   !common.check(end_error, "end pass") {
		return false
	}

	return(
		common.check(common.present_surface(&game.surface, app), "present") &&
		common.check(common.draw_overlay(&game.overlay, app), "draw overlay") \
	)
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	scene.destroy(&game.world)
	save_panel_layout(game)
	destroy_panel(game)
	common.destroy_overlay(&game.overlay, app.device)
	renderer := &game.surface.renderer
	common.check(render.destroy_debug_lines(renderer, &game.lines), "destroy debug lines")
	for &material in game.materials {
		common.check(render.destroy_material(renderer, &material), "destroy material")
	}
	common.check(render.destroy_mesh(renderer, &game.mesh), "destroy mesh")
	common.check(render.destroy_pipeline(renderer, &game.pipeline), "destroy pipeline")
	render.destroy_draw_list(&game.draws)
	common.destroy_surface(&game.surface)
}
