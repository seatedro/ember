package game

import "../common"

import "core:log"
import "core:math"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import "ember:particles"
import render "ember:renderer"
import "ember:shaders"
import "ember:ui"

CAPACITY :: 4096
INITIAL_ORBIT :: camera.Orbit {
	target   = {0, -1, 0},
	pitch    = 0.2,
	yaw      = -0.35,
	distance = 11,
}

State :: struct {
	renderer:       render.Renderer,
	billboards:     render.Billboard_Renderer,
	items:          [dynamic]render.Billboard,
	emitter:        particles.Emitter,
	shaders:        shaders.Library,
	mesh:           render.Mesh,
	pipeline:       render.Pipeline,
	material:       render.Material,
	grid:           render.Debug_Grid,
	target:         render.Render_Target,
	presentation:   render.Presentation,
	bloom:          render.Bloom,
	overlay:        common.Overlay,
	window:         ui.Window,
	scroll:         [2]f32,
	orbit:          camera.Orbit,
	preset, blend:  int,
	bloom_enabled:  bool,
	bloom_strength: f32,
	failed:         bool,
}

state: State

configure :: proc() -> engine.Config {
	return {
		title = "Ember - Particles",
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
		orbit = INITIAL_ORBIT,
		blend = int(render.Billboard_Blend.Additive),
		bloom_enabled = true,
		bloom_strength = 0.35,
		window = {
			id = ui.id("particles"),
			bounds = {{24, 24}, {312, 536}},
			minimum_size = {264, 140},
			open = true,
		},
	}

	game.items = make([dynamic]render.Billboard)
	particle_error: particles.Error
	game.emitter, particle_error = particles.create(CAPACITY, 42)
	if !check_particles(particle_error) {
		return false
	}
	set_preset(game)

	err: render.Error
	game.renderer, err = render.create(app.device)
	if !check(err, "create renderer") {
		return false
	}

	game.billboards, err = render.create_billboard_renderer(app.device, CAPACITY)
	if !check(err, "create billboards") {
		return false
	}

	game.shaders = shaders.create(app.device)
	program, shader_error := render.load_builtin_shader(&game.shaders, .Unlit)
	if shader_error != .None {
		log.errorf("Load shader: %v", shader_error)
		return false
	}

	game.pipeline, err = render.create_pipeline(
		&game.renderer,
		program,
		{
			layout = render.VERTEX_LAYOUT,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = .Back, winding = .CCW},
		},
	)
	if !check(err, "create pipeline") {
		return false
	}

	game.material, err = render.create_material(
		&game.renderer,
		program,
		render.Tint_Parameters{tint = {0.08, 0.12, 0.2, 1}},
	)
	if !check(err, "create material") {
		return false
	}
	sphere, geometry_error := geometry.create_sphere(segments = 24, stacks = 12)
	if geometry_error != .None {
		log.errorf("Create sphere: %v", geometry_error)
		return false
	}

	defer geometry.destroy_sphere(&sphere)
	game.mesh, err = render.create_mesh(
		&game.renderer,
		sphere.vertices,
		sphere.indices,
		render.VERTEX_LAYOUT,
		sphere.bounds,
	)
	if !check(err, "create mesh") {
		return false
	}

	game.grid, err = render.create_debug_grid(&game.renderer, &game.shaders, extent = 8)
	if !check(err, "create grid") {
		return false
	}

	game.target, err = render.create_render_target(&game.renderer, common.TARGET_DESC)
	if !check(err, "create target") {
		return false
	}

	game.bloom, err = render.create_bloom(&game.renderer, &game.shaders)
	if !check(err, "create bloom") {
		return false
	}

	game.presentation, err = render.create_presentation(&game.renderer, &game.shaders)
	if !check(err, "create presentation") {
		return false
	}

	if !common.init_overlay(&game.overlay, app) {
		return false
	}

	return true
}

set_preset :: proc(game: ^State) {
	particles.reset(&game.emitter)
	game.emitter.paused = false
	game.emitter.emitting = game.preset == 0
	game.emitter.settings = {
		position           = {0, -1, 0},
		radius             = 0.12,
		velocity           = {0, -3, 0},
		velocity_variation = {0.25, 0.3, 0.25},
		rate               = 500,
		lifetime           = {0.5, 1.2},
		size               = {0.18, 0.02},
		color              = {{4, 1.4, 0.3, 1}, {0.7, 0.08, 0.01, 0}},
		rotation           = {0, 2 * math.PI},
		angular_velocity   = {-1, 1},
	}

	if game.preset == 1 {
		game.emitter.settings = {
			radius           = 1.1,
			radial_speed     = {1.5, 4},
			rate             = 500,
			lifetime         = {1, 3},
			size             = {0.12, 0.02},
			color            = {{5, 2.4, 0.5, 1}, {1, 0.1, 0.02, 0}},
			rotation         = {0, 2 * math.PI},
			angular_velocity = {-2, 2},
		}

		game.failed = !check_particles(particles.emit(&game.emitter, 1200))
	}
}

restart :: proc(game: ^State) {
	particles.reset(&game.emitter)
	game.emitter.paused = false
	if game.preset == 1 {
		game.failed = !check_particles(particles.emit(&game.emitter, 1200))
	}
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
		game.emitter.paused = !game.emitter.paused
	}

	if input.pressed(&controls, .R) {
		restart(game)
	}

	if input.mouse_down(&controls, .Left) {
		camera.rotate_orbit(
			&game.orbit,
			{f32(controls.mouse_delta.x) * 0.005, f32(controls.mouse_delta.y) * 0.005},
			1.45,
		)
	}

	if controls.scroll_delta.y != 0 {
		camera.zoom_orbit(&game.orbit, controls.scroll_delta.y * 0.1, 3, 40)
	}

	if !check_particles(particles.update(&game.emitter, dt)) {
		game.failed = true
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.failed {
		return false
	}

	clear(&game.items)
	if !check(render.append_particle_billboards(&game.items, &game.emitter), "gather particles") {
		return false
	}

	view := camera.from_orbit(game.orbit)
	projection := emath.perspective(
		math.PI / 3,
		f32(game.target.width) / f32(game.target.height),
		0.1,
		100,
	)
	if !check(
		render.begin_pass(&game.renderer, {target = &game.target}, common.BACKGROUND),
		"begin particles",
	) {
		return false
	}

	ok := check(render.set_view(&game.renderer, view, projection), "set view")
	ok =
		check(
			render.draw_mesh(
				&game.renderer,
				&game.pipeline,
				&game.mesh,
				&game.material,
				{orientation = 1, scale = {1, 1, 1}},
			),
			"draw sphere",
		) &&
		ok
	ok =
		check(
			render.draw_mesh(
				&game.renderer,
				&game.grid.pipeline,
				&game.grid.mesh,
				&game.grid.material,
				{position = {0, -4, 0}, orientation = 1, scale = {1, 1, 1}},
			),
			"draw grid",
		) &&
		ok
	ok =
		check(
			render.draw_billboards(
				&game.billboards,
				game.items[:],
				view,
				projection,
				render.Billboard_Blend(game.blend),
			),
			"draw particles",
		) &&
		ok
	ok = check(render.end_pass(&game.renderer), "end particles") && ok
	if !ok {
		return false
	}

	bloom_texture: render.Texture
	if game.bloom_enabled && game.bloom_strength > 0 {
		err: render.Error
		bloom_texture, err = render.apply_bloom(
			&game.renderer,
			&game.bloom,
			game.target,
			{threshold = 1, softness = 0.5},
		)
		if !check(err, "bloom") {
			return false
		}
	}

	viewport := render.pixel_viewport(common.RESOLUTION, {app.width, app.height})

	if !check(
		render.present(
			&game.renderer,
			&game.presentation,
			game.target.color,
			viewport,
			{exposure = 1, bloom_strength = game.bloom_strength if game.bloom_enabled else 0},
			bloom_texture,
		),
		"present",
	) {
		return false
	}

	return check(common.draw_overlay(&game.overlay, app), "draw overlay")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	particles.destroy(&game.emitter)
	delete(game.items)
	common.destroy_overlay(&game.overlay, app.device)
	check(render.destroy_billboard_renderer(&game.billboards), "destroy billboards")
	check(render.destroy_bloom(&game.renderer, &game.bloom), "destroy bloom")
	check(render.destroy_presentation(&game.renderer, &game.presentation), "destroy presentation")
	check(render.destroy_render_target(&game.renderer, &game.target), "destroy target")
	check(render.destroy_debug_grid(&game.renderer, &game.grid), "destroy grid")
	check(render.destroy_material(&game.renderer, &game.material), "destroy material")
	check(render.destroy_mesh(&game.renderer, &game.mesh), "destroy mesh")
	check(render.destroy_pipeline(&game.renderer, &game.pipeline), "destroy pipeline")
	if err := shaders.destroy(&game.shaders); err != .None {
		log.errorf("Destroy shaders: %v", err)
	}
	check(render.destroy(&game.renderer), "destroy renderer")
}

check :: proc(err: render.Error, operation: string) -> bool {
	if err != .None {
		log.errorf("%s: %v", operation, err)
	}

	return err == .None
}

check_particles :: proc(err: particles.Error) -> bool {
	if err != .None {
		log.errorf("Particles: %v", err)
	}

	return err == .None
}
