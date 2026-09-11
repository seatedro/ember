package game

import "core:log"
import "core:math"
import "ember:camera"
import emath "ember:core/math"
import "ember:engine"
import "ember:geometry"
import "ember:input"
import render "ember:renderer"

State :: struct {
	renderer:  render.Renderer,
	grid:      render.Grid,
	angle:     f32,
	transform: emath.Transform,
	orbit:     camera.Orbit,
	camera:    camera.Camera,
}

init :: proc(app: ^engine.Context, userdata: rawptr) -> bool {
	game := cast(^State)userdata
	game^ = {}
	game.transform = {
		orientation = emath.quaternion_angle_axis(-0.2, {1, 0, 0}),
		scale       = {1.25, 0.75, 1},
	}
	game.orbit = INITIAL_ORBIT
	game.camera = camera.from_orbit(game.orbit)

	err: render.Error
	mesh, mesh_error := geometry.create_sphere()
	if mesh_error != .None {
		log.errorf("Sphere generation failed: %v", mesh_error)
		return false
	}
	defer geometry.destroy_sphere(&mesh)
	game.renderer, err = render.create(app.device, mesh.vertices, mesh.indices)
	if !check(err, "create renderer") {return false}
	game.grid, err = render.create_grid(&game.renderer)
	return check(err, "create grid")
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
	projection := emath.perspective(1.04719755, f32(app.width) / f32(app.height), 0.1, 100)
	if !check(
		render.begin_frame(&game.renderer, game.camera, projection),
		"begin frame",
	) {return false}
	if !check(render.draw_grid(&game.renderer, &game.grid), "draw grid") {return false}
	return check(render.draw(&game.renderer, game.transform), "draw sphere")
}

quit :: proc(app: ^engine.Context, userdata: rawptr) {
	game := cast(^State)userdata
	check(render.destroy_grid(&game.renderer, &game.grid), "destroy grid")
	check(render.destroy(&game.renderer), "destroy renderer")
	game^ = {}
}

check :: proc(err: render.Error, operation: string) -> bool {
	if err != .None {log.errorf("Sphere: %s: %v", operation, err)}
	return err == .None
}
