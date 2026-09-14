package game

import "core:fmt"
import "core:log"
import emath "ember:core/math"
import "ember:physics"
import render "ember:renderer"
import "ember:scene"
import "ember:ui"

PROBE_POSE :: emath.Pose {
	position    = {0, 0, 0},
	orientation = 1,
}

init_physics :: proc(game: ^State) -> bool {
	scene_error: scene.Error
	game.world, scene_error = scene.create(2)
	if !check_scene(scene_error) {
		return false
	}

	game.probe, scene_error = scene.create_object(&game.world, emath.pose_matrix(PROBE_POSE))
	if !check_scene(scene_error) {
		return false
	}
	game.probe_marker, scene_error = scene.create_object(
		&game.world,
		emath.transform_matrix({position = {2, 0, 0}, orientation = 1, scale = {0.3, 0.3, 0.3}}),
		game.probe,
	)
	if !check_scene(scene_error) {
		return false
	}

	err: physics.Error
	game.probe_body, err = physics.create_body(
		&game.world.physics,
		{state = {pose = PROBE_POSE}, mass = physics.sphere_mass(2, 1.4)},
	)
	if !check_physics(err) {
		return false
	}
	return check_scene(scene.bind_body(&game.world, game.probe, game.probe_body))
}

update_physics :: proc(game: ^State, dt: f32) {
	world := &game.world.physics
	if game.probe_thrust && !check_physics(physics.add_force(world, game.probe_body, {0, 2, 0})) {
		game.physics_failed = true
	}
	if game.probe_impulse {
		game.physics_failed =
			!check_physics(physics.add_impulse(world, game.probe_body, {2, 0, 0}, {0, 1, 0})) ||
			game.physics_failed
		game.probe_impulse = false
	}
	if game.probe_spin {
		game.physics_failed =
			!check_physics(physics.add_angular_impulse(world, game.probe_body, {0, 2, 0})) ||
			game.physics_failed
		game.probe_spin = false
	}
	game.physics_failed = !check_physics(physics.step(world, dt)) || game.physics_failed
}

reset_physics :: proc(game: ^State) {
	game.probe_thrust, game.probe_impulse, game.probe_spin = false, false, false
	game.physics_failed = !check_physics(
		physics.teleport(&game.world.physics, game.probe_body, PROBE_POSE, clear_velocity = true),
	)
}

draw_physics :: proc(game: ^State) -> bool {
	for object, index in ([2]scene.Object{game.probe, game.probe_marker}) {
		model, ok := scene.world_transform(&game.world, object, game.simulation.interpolation)
		if !ok {
			return false
		}
		if index == 0 {
			model *= emath.transform_matrix({orientation = 1, scale = {1.4, 1.4, 1.4}})
		}
		if !check(
			render.add_draw(
				&game.draws,
				{
					pipeline = game.pipeline,
					mesh = game.mesh,
					material = game.materials[1 - index],
					transform = model,
				},
			),
			"submit physics body",
		) {
			return false
		}
	}
	return true
}

physics_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 60)
	state, ok := physics.body_state(&game.world.physics, game.probe_body)
	if !check_ui(err) || !ok {
		return false
	}
	buffer: [192]u8
	text := fmt.bprintf(
		buffer[:],
		"MASS 2 KG\nSPEED %.2f M/S\nSPIN %.2f RAD/S\nHEIGHT %.2f M",
		emath.length(state.velocity),
		emath.length(state.angular_velocity),
		state.pose.position.y,
	)
	if !check_ui(ui.label(ctx, rect, text)) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}
	_, control_error := ui.checkbox(
		ctx,
		ui.id("probe-thrust"),
		rect,
		"THRUST UP (2 N)",
		&game.probe_thrust,
	)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	push, push_error := ui.button(ctx, ui.id("probe-impulse"), rect, "IMPULSE +X / OFF CENTER")
	if !check_ui(push_error) {
		return false
	}
	game.probe_impulse = game.probe_impulse || push

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	spin, spin_error := ui.button(ctx, ui.id("probe-spin"), rect, "ANGULAR IMPULSE +Y")
	if !check_ui(spin_error) {
		return false
	}
	game.probe_spin = game.probe_spin || spin

	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}
	_, control_error = ui.checkbox(
		ctx,
		ui.id("probe-pause"),
		rect,
		"PAUSED",
		&game.simulation.paused,
	)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	reset, reset_error := ui.button(ctx, ui.id("probe-reset"), rect, "RESET SIMULATION")
	if !check_ui(reset_error) {
		return false
	}
	if reset {
		reset_simulation(game)
	}
	return true
}

check_physics :: proc(err: physics.Error) -> bool {
	if err != .None {
		log.errorf("Physics: %v", err)
	}
	return err == .None
}

check_scene :: proc(err: scene.Error) -> bool {
	if err != .None {
		log.errorf("Scene: %v", err)
	}
	return err == .None
}
