package game

import "core:log"
import "core:mem"
import "ember:engine"
import "ember:rhi"

State :: struct {
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
	game^ = {}
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
		{stage = .Vertex, source = #load("shaders/triangle.vert"), label = "triangle vertex"},
	)
	if !check(vertex_error, "compile vertex shader") {
		return false
	}
	defer check(rhi.destroy_shader(device, vertex), "destroy vertex shader")

	fragment, fragment_error := rhi.create_shader(
		device,
		{stage = .Fragment, source = #load("shaders/triangle.frag"), label = "triangle fragment"},
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

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	device := app.device

	rhi.clear(device, {0.1, 0.1, 0.1, 1}, 1)
	if !check(rhi.bind_pipeline(device, game.pipeline), "bind pipeline") {
		return false
	}

	if !check(rhi.bind_vertex_buffer(device, game.vertices), "bind vertices") {
		return false
	}

	if !check(rhi.bind_index_buffer(device, game.indices, .U16), "bind indices") {
		return false
	}

	return check(rhi.draw_indexed(device, {index_count = 3}), "draw triangle")
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
	game^ = {}
}

check :: proc(err: rhi.Error, operation: string) -> bool {
	if err != .None {
		log.errorf("Triangle: %s: %v", operation, err)
	}
	return err == .None
}
