package game

import "../common"
import "core:log"
import "core:math"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import render "ember:renderer"
import "ember:shaders"
import "ember:ui"

State :: struct {
	normal_map:                                                render.Texture,
	normal_mapping:                                            bool,
	shadow:                                                    render.Shadow_Map,
	shadow_settings:                                           render.Shadow_Settings,
	ground_mesh:                                               render.Mesh,
	ground_material:                                           render.Material,
	renderer:                                                  render.Renderer,
	overlay:                                                   common.Overlay,
	ui_failed:                                                 bool,
	render_window:                                             ui.Window,
	camera_window:                                             ui.Window,
	bloom_window:                                              ui.Window,
	lighting_window:                                           ui.Window,
	point_enabled, directional_enabled:                        bool,
	light_azimuth, light_elevation, light_intensity, emission: f32,
	ui_scroll:                                                 [4][2]f32,
	tone_mapping:                                              int,
	note:                                                      ui.Text_Edit,
	preview:                                                   render.Texture,
	shaders:                                                   shaders.Library,
	draws:                                                     render.Draw_List,
	mesh:                                                      render.Mesh,
	pipeline:                                                  render.Pipeline,
	materials:                                                 [2]render.Material,
	texture:                                                   render.Texture,
	presentation:                                              render.Presentation,
	bloom:                                                     render.Bloom,
	bloom_settings:                                            render.Bloom_Settings,
	bloom_enabled:                                             bool,
	bloom_strength:                                            f32,
	target:                                                    common.Pixel_Target,
	orbit:                                                     camera.Orbit,
	angle:                                                     f32,
	batching, paused:                                          bool,
	last_stats:                                                render.Draw_Stats,
	next_report:                                               f64,
	exposure:                                                  f32,
}

MATERIAL_COLORS :: [2][4]f32{{0.12, 0.4, 0.75, 1}, {0.85, 0.3, 0.08, 1}}

INITIAL_ORBIT :: camera.Orbit {
	pitch    = 0.6,
	distance = 58,
}
state: State

configure :: proc() -> engine.Config {
	return {
		title = "Ember - Instancing",
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
		batching = true,
		normal_mapping = true,
		render_window = {
			id = ui.id("render-window"),
			bounds = {{24, 24}, {360, 400}},
			minimum_size = {240, 160},
			open = true,
		},
		camera_window = {
			id = ui.id("camera-window"),
			bounds = {{408, 24}, {300, 200}},
			minimum_size = {220, 160},
			open = true,
		},
		bloom_window = {
			id = ui.id("bloom-window"),
			bounds = {{408, 248}, {300, 236}},
			minimum_size = {220, 160},
			open = true,
		},
		lighting_window = {
			id = ui.id("lighting-window"),
			bounds = {{736, 24}, {312, 352}},
			minimum_size = {264, 160},
			open = true,
		},
		shadow_settings = {enabled = true, bias = 0.0003, slope_bias = 0.001},
		directional_enabled = true,
		light_azimuth = 2.1,
		light_elevation = 0.9,
		light_intensity = 2.5,
		emission = 2,
		bloom_enabled = true,
		bloom_settings = {threshold = 1, softness = 0.5},
		bloom_strength = 0.5,
		exposure = 1,
	}
	err: render.Error
	game.renderer, err = render.create(app.device)
	if !check(err, "create renderer") {
		return false
	}

	if !common.init_overlay(&game.overlay, app) {
		return false
	}

	note_error: ui.Error
	game.note, note_error = ui.create_text_edit("Hello, world!")
	if !check_ui(note_error) {
		return false
	}

	game.preview, err = render.create_texture(
		&game.renderer,
		{width = 2, height = 2, format = .RGBA8, filter = .Nearest},
		{239, 207, 125, 255, 127, 99, 135, 255, 127, 99, 135, 255, 239, 207, 125, 255},
	)
	if !check(err, "create overlay image") {
		return false
	}

	game.draws = render.create_draw_list()
	game.shaders = shaders.create(app.device)
	shader, shader_error := render.load_builtin_shader(&game.shaders, .Lit_Shadowed)
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
		{{name = "albedo_texture", binding = 0}, {name = "normal_texture", binding = 1}},
		lighting = true,
		shadows = true,
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

	game.normal_map, err = create_dimple_normal_map(&game.renderer)
	if !check(err, "create normal map") {
		return false
	}

	for color, i in MATERIAL_COLORS {
		game.materials[i], err = render.create_lit_material(
			&game.renderer,
			shader,
			render.Lit_Parameters {
				tint = color,
				emission = game.emission if i == 1 else 0,
				use_normal_map = b32(game.normal_mapping),
			},
			game.texture,
			game.normal_map,
		)
		if !check(err, "create material") {
			return false
		}
	}

	game.shadow, err = render.create_shadow_map(&game.renderer, &game.shaders, 2048)
	if !check(err, "create shadow map") {
		return false
	}
	quad := geometry.create_quad()
	game.ground_mesh, err = render.create_mesh(
		&game.renderer,
		quad.vertices[:],
		quad.indices[:],
		render.VERTEX_LAYOUT,
		quad.bounds,
	)
	if !check(err, "create ground") {
		return false
	}
	game.ground_material, err = render.create_lit_material(
		&game.renderer,
		shader,
		render.Lit_Parameters{tint = {0.25, 0.28, 0.32, 1}},
		game.texture,
	)
	if !check(err, "create ground material") {
		return false
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

	game.target, err = common.create_pixel_target(&game.renderer, &game.shaders)
	if !check(err, "create pixel target") {
		return false
	}

	game.bloom, err = render.create_bloom(&game.renderer, &game.shaders)
	if !check(err, "create bloom") {
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

	if input.pressed(&game_input, .B) {
		game.batching = !game.batching
		game.next_report = 0
	}

	if input.pressed(&game_input, .Space) {
		game.paused = !game.paused
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

	if !game.paused {
		game.angle += dt * 0.3
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.ui_failed {
		return false
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

	lights := [1]render.Point_Light {
		{position = {-15, 30, 20}, color = {1, 0.9, 0.8}, intensity = 6, range = 130},
	}
	directional_lights := [1]render.Directional_Light {
		{
			direction = {
				math.cos(game.light_azimuth) * math.cos(game.light_elevation),
				math.sin(game.light_elevation),
				math.sin(game.light_azimuth) * math.cos(game.light_elevation),
			},
			color = {1, 0.95, 0.85},
			intensity = game.light_intensity,
		},
	}
	if !check(
		render.add_draw(
			&game.draws,
			{
				pipeline = game.pipeline,
				mesh = game.ground_mesh,
				material = game.ground_material,
				transform = {
					position = {0, -2.5, 0},
					orientation = emath.quaternion_angle_axis(-math.PI / 2, {1, 0, 0}),
					scale = {34, 34, 1},
				},
			},
		),
		"submit ground",
	) {
		return false
	}

	if !check(
		render.draw_directional_shadow(
			&game.renderer,
			&game.shadow,
			&game.draws,
			directional_lights[0],
			{half_size = {48, 48}, depth = 140},
		),
		"draw shadow map",
	) {
		return false
	}

	if !check(
		render.begin_pass(&game.renderer, {target = &game.target.world}, common.BACKGROUND),
		"begin pass",
	) {
		return false
	}

	shadow_settings := game.shadow_settings
	shadow_settings.enabled = shadow_settings.enabled && game.directional_enabled
	draw_error := render.draw_list(
		&game.renderer,
		&game.draws,
		camera.from_orbit(game.orbit),
		emath.perspective(
			math.PI / 3,
			f32(game.target.world.width) / f32(game.target.world.height),
			0.1,
			200,
		),
		{
			shadow = &game.shadow,
			shadow_settings = shadow_settings,
			point_lights = lights[:1 if game.point_enabled else 0],
			directional_lights = directional_lights[:1 if game.directional_enabled else 0],
		},
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

	if !check(common.resolve_pixels(&game.renderer, &game.target), "resolve pixels") {
		return false
	}

	bloom_texture: render.Texture
	if game.bloom_enabled && game.bloom_strength > 0 {
		err: render.Error
		bloom_texture, err = render.apply_bloom(
			&game.renderer,
			&game.bloom,
			game.target.pixels,
			game.bloom_settings,
		)
		if !check(err, "apply bloom") {
			return false
		}
	}

	if !check(
		render.present(
			&game.renderer,
			&game.presentation,
			game.target.pixels.color,
			render.pixel_viewport(common.RESOLUTION, {app.width, app.height}),
			{
				exposure = game.exposure,
				tone_mapping = render.Tone_Mapping(game.tone_mapping),
				bloom_strength = game.bloom_strength if game.bloom_enabled else 0,
			},
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
	check(render.destroy_shadow_map(&game.renderer, &game.shadow), "destroy shadow map")
	check(
		render.destroy_material(&game.renderer, &game.ground_material),
		"destroy ground material",
	)
	check(render.destroy_mesh(&game.renderer, &game.ground_mesh), "destroy ground")
	common.destroy_overlay(&game.overlay, app.device)
	ui.destroy_text_edit(&game.note)
	check(render.destroy_texture(&game.renderer, &game.preview), "destroy overlay image")
	check(render.destroy_presentation(&game.renderer, &game.presentation), "destroy presentation")
	check(render.destroy_bloom(&game.renderer, &game.bloom), "destroy bloom")

	common.destroy_pixel_target(&game.renderer, &game.target)
	for &material in game.materials {
		check(render.destroy_material(&game.renderer, &material), "destroy material")
	}

	check(render.destroy_texture(&game.renderer, &game.normal_map), "destroy normal map")
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
