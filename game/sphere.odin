package game

import "core:log"
import "core:math"
import "core:mem"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import "ember:rhi"

State :: struct {
	pipeline:    rhi.Pipeline_Handle,
	vertices:    rhi.Buffer_Handle,
	indices:     rhi.Buffer_Handle,
	uniforms:    rhi.Buffer_Handle,
	index_count: u32,
	angle:       f32,
	transform:   emath.Transform,
	orbit:       camera.Orbit,
	camera:      camera.Camera,
	grid:        Grid,
}

// mvp means model-view-projection.
// Two column-major mat4 values match the shader's std140 Per_Object block.
Per_Object :: struct {
	mvp:     emath.Mat4,
	normals: emath.Mat4,
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {}
	// Unequal scale makes the normal transformation visible in the demo.
	game.transform = {
		orientation = emath.quaternion_angle_axis(-0.2, {1, 0, 0}),
		scale       = {1.25, 0.75, 1},
	}
	game.orbit = INITIAL_ORBIT
	game.camera = camera.from_orbit(game.orbit)
	device := app.device

	mesh, mesh_error := geometry.create_sphere()
	if mesh_error != .None {
		log.errorf("Sphere generation failed: %v", mesh_error)
		return false
	}
	defer geometry.destroy_sphere(&mesh)
	game.index_count = u32(len(mesh.indices))

	vertex_bytes := mem.slice_to_bytes(mesh.vertices)
	index_bytes := mem.slice_to_bytes(mesh.indices)
	err: rhi.Error
	game.vertices, err = rhi.create_buffer(
		device,
		{size = u64(len(vertex_bytes)), usage = {.Vertex}, label = "sphere vertices"},
		vertex_bytes,
	)
	if !check(err, "create vertices") {
		return false
	}

	game.indices, err = rhi.create_buffer(
		device,
		{size = u64(len(index_bytes)), usage = {.Index}, label = "sphere indices"},
		index_bytes,
	)
	if !check(err, "create indices") {
		return false
	}

	game.uniforms, err = rhi.create_buffer(
		device,
		{size = size_of(Per_Object), usage = {.Uniform}, label = "sphere transforms"},
	)
	if !check(err, "create uniforms") {
		return false
	}

	vertex, vertex_error := rhi.create_shader(
		device,
		{stage = .Vertex, source = #load("../shaders/sphere.vert"), label = "sphere vertex"},
	)
	if !check(vertex_error, "compile vertex shader") {
		return false
	}
	defer check(rhi.destroy_shader(device, vertex), "destroy vertex shader")

	fragment, fragment_error := rhi.create_shader(
		device,
		{stage = .Fragment, source = #load("../shaders/sphere.frag"), label = "sphere fragment"},
	)
	if !check(fragment_error, "compile fragment shader") {
		return false
	}
	defer check(rhi.destroy_shader(device, fragment), "destroy fragment shader")

	settings := rhi.Pipeline_Settings {
		layout = {
			stride = size_of(geometry.Sphere_Vertex),
			attribute_count = 2,
			attributes = {
				0 = {
					location = 0,
					format = .F32x3,
					offset = u32(offset_of(geometry.Sphere_Vertex, position)),
				},
				1 = {
					location = 1,
					format = .F32x3,
					offset = u32(offset_of(geometry.Sphere_Vertex, normal)),
				},
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
			uniform_blocks = {{name = "Per_Object", binding = 0}},
			label = "sphere",
		},
	)
	if !check(err, "create pipeline") {
		return false
	}
	return create_grid(&game.grid, device)
}

update :: proc(app: ^engine.Context, userdata: rawptr, dt: f32) {
	game := cast(^State)userdata
	update_camera(game, app)
	if input.pressed(app.input, .Escape) {
		engine.request_quit(app)
	}
	game.angle += dt * 0.05
	if game.angle >= 2 * math.PI {
		game.angle -= 2 * math.PI
	}
	game.transform.orientation =
		emath.quaternion_angle_axis(game.angle, {0, 1, 0}) *
		emath.quaternion_angle_axis(-0.2, {1, 0, 0})
}

draw :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	device := app.device

	model := emath.transform_matrix(game.transform)
	view := camera.view_matrix(game.camera)
	projection := emath.perspective(1.04719755, f32(app.width) / f32(app.height), 0.1, 100)
	data := [1]Per_Object {
		{mvp = projection * view * model, normals = emath.normal_matrix(game.transform)},
	}

	if !check(
		rhi.update_buffer(device, game.uniforms, 0, mem.slice_to_bytes(data[:])),
		"update transforms",
	) {
		return false
	}

	rhi.clear(device, {0.1, 0.1, 0.1, 1}, 1)
	if !draw_grid(&game.grid, device, projection * view) {
		return false
	}
	if !check(rhi.bind_pipeline(device, game.pipeline), "bind pipeline") {
		return false
	}

	if !check(rhi.bind_vertex_buffer(device, game.vertices), "bind vertices") {
		return false
	}

	if !check(rhi.bind_index_buffer(device, game.indices, .U32), "bind indices") {
		return false
	}

	if !check(rhi.bind_uniform_buffer(device, 0, game.uniforms), "bind uniforms") {
		return false
	}

	return check(rhi.draw_indexed(device, {index_count = game.index_count}), "draw sphere")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	destroy_grid(&game.grid, app.device)

	if game.pipeline.generation != 0 {
		check(rhi.destroy_pipeline(app.device, game.pipeline), "destroy pipeline")
	}

	if game.uniforms.generation != 0 {
		check(rhi.destroy_buffer(app.device, game.uniforms), "destroy uniforms")
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
		log.errorf("Sphere: %s: %v", operation, err)
	}
	return err == .None
}
