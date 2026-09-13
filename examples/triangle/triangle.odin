package game

import "../common"

import "core:log"
import "core:mem"
import "ember:engine"
import "ember:input"
import "ember:rhi"
import "ember:ui"

@(private)
TRIANGLE_SOURCES :: #partial [rhi.Shader_Language][2]rhi.Shader_Source {
	.MSL  = {
		{entry_point = "vertex_main", code = #load("shaders/triangle.metal", string)},
		{entry_point = "fragment_main", code = #load("shaders/triangle.metal", string)},
	},
	.GLSL = {
		{entry_point = "main", code = #load("shaders/triangle.vert", string)},
		{entry_point = "main", code = #load("shaders/triangle.frag", string)},
	},
}

State :: struct {
	surface:  common.Surface,
	overlay:  common.Overlay,
	window:   ui.Window,
	failed:   bool,
	pipeline: rhi.Pipeline_Handle,
	vertices: rhi.Buffer_Handle,
	indices:  rhi.Buffer_Handle,
}

Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {
		window = common.info_window("triangle", 152),
	}
	if !common.init_surface(&game.surface, app.device) ||
	   !common.init_overlay(&game.overlay, app) {
		return false
	}

	device := app.device

	vertices := [3]Vertex {
		{{-0.7, -0.7, 0}, {1, 0.2, 0.1}},
		{{0.7, -0.7, 0}, {0.1, 0.8, 0.3}},
		{{0.0, 0.7, 0}, {0.2, 0.4, 1}},
	}
	indices := [3]u16{0, 1, 2}

	err: rhi.Error
	game.vertices, err = rhi.create_buffer(
		device,
		{size = size_of(vertices), usage = {.Vertex}, label = "triangle vertices"},
		mem.slice_to_bytes(vertices[:]),
	)
	if !check(err, "create vertices") {
		return false
	}

	game.indices, err = rhi.create_buffer(
		device,
		{size = size_of(indices), usage = {.Index}, label = "triangle indices"},
		mem.slice_to_bytes(indices[:]),
	)
	if !check(err, "create indices") {
		return false
	}

	vertex, vertex_error := rhi.create_shader(
		device,
		{
			stage = .Vertex,
			language = rhi.SHADER_LANGUAGE,
			source = TRIANGLE_SOURCES[rhi.SHADER_LANGUAGE][0],
			label = "triangle vertex",
		},
	)
	if !check(vertex_error, "compile vertex shader") {
		return false
	}
	defer check(rhi.destroy_shader(device, vertex), "destroy vertex shader")

	fragment, fragment_error := rhi.create_shader(
		device,
		{
			stage = .Fragment,
			language = rhi.SHADER_LANGUAGE,
			source = TRIANGLE_SOURCES[rhi.SHADER_LANGUAGE][1],
			label = "triangle fragment",
		},
	)
	if !check(fragment_error, "compile fragment shader") {
		return false
	}
	defer check(rhi.destroy_shader(device, fragment), "destroy fragment shader")

	settings := rhi.Pipeline_Settings {
		layout = {
			stride = size_of(Vertex),
			attribute_count = 2,
			attributes = {
				0 = {location = 0, format = .F32x3, offset = u32(offset_of(Vertex, position))},
				1 = {location = 1, format = .F32x3, offset = u32(offset_of(Vertex, color))},
			},
		},
		depth = {test_enabled = true, write_enabled = true, compare = .Less},
		raster = {cull = .Back, winding = .CCW},
	}

	game.pipeline, err = rhi.create_pipeline(
		device,
		{
			vertex_shader = vertex,
			fragment_shader = fragment,
			settings = settings,
			label = "triangle",
		},
	)
	return check(err, "create pipeline")
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	game.failed = !common.info_panel(
		&game.overlay,
		app,
		&game.window,
		"TRIANGLE",
		"Indexed triangle\n320 x 180\n\nF1  Toggle overlay\nEsc Close",
	)
	controls := ui.remaining_input(&game.overlay.interface)
	if input.pressed(&controls, .Escape) {
		engine.request_quit(app)
	}
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	if game.failed || !draw_triangle(app, game) {
		return false
	}

	if !check(common.present_surface(&game.surface, app), "present") {
		return false
	}

	return check(common.draw_overlay(&game.overlay, app), "draw overlay")
}

draw_triangle :: proc(app: ^engine.Context, game: ^State) -> bool {
	device := app.device

	if !check(
		rhi.begin_pass(device, {target = game.surface.target.handle}, common.BACKGROUND),
		"begin pass",
	) {
		return false
	}

	defer check(rhi.end_pass(device), "end pass")
	if !check(rhi.bind_pipeline(device, game.pipeline), "bind pipeline") {
		return false
	}

	if !check(rhi.bind_vertex_buffer(device, game.vertices), "bind vertices") {
		return false
	}

	if !check(rhi.bind_index_buffer(device, game.indices, .U16), "bind indices") {
		return false
	}

	return check(rhi.draw_indexed(device, {index_count = 3, instance_count = 1}), "draw triangle")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata

	if game.pipeline.generation != 0 {
		check(rhi.destroy_pipeline(app.device, game.pipeline), "destroy pipeline")
	}

	if game.indices.generation != 0 {
		check(rhi.destroy_buffer(app.device, game.indices), "destroy indices")
	}

	if game.vertices.generation != 0 {
		check(rhi.destroy_buffer(app.device, game.vertices), "destroy vertices")
	}
	common.destroy_overlay(&game.overlay, app.device)
	common.destroy_surface(&game.surface)
	game^ = {}
}

check :: proc(err: rhi.Error, operation: string) -> bool {
	if err != .None {
		log.errorf("Triangle: %s: %v", operation, err)
	}
	return err == .None
}
