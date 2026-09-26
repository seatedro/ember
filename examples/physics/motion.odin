package game

import "../common"

import "core:fmt"
import "core:log"
import emath "ember:core/math"
import "ember:physics"
import render "ember:renderer"
import "ember:scene"
import "ember:ui"

PROBE_POSITION :: emath.Vec3{0, 0, 0}
PROBE_MASS :: f32(2)
PROBE_RADIUS :: f32(1.4)
MARKER_POSITION :: emath.Vec3{2, 0, 0}
MARKER_RADIUS :: f32(0.3)

// The probe is the one dynamic body. The small sphere fixed to its side makes
// its rotation visible.
Motion :: struct {
	probe, marker: scene.Object,
	body:          physics.Body_Handle,
	colliders:     [2]physics.Collider_Handle,
	thrust:        bool,
	// Set by the panel, spent by the next physics step.
	push, spin:    bool,
}

init_motion :: proc(game: ^State) -> bool {
	motion := &game.motion
	scene_error: scene.Error
	motion.probe, scene_error = scene.create_object(
		&game.world,
		emath.rigid_matrix(PROBE_POSITION, 1),
	)
	if !check_scene(scene_error) {
		return false
	}

	motion.marker, scene_error = scene.create_object(
		&game.world,
		emath.transform_matrix(
			{
				position = MARKER_POSITION,
				orientation = 1,
				scale = MARKER_RADIUS * emath.Vec3{1, 1, 1},
			},
		),
		motion.probe,
	)
	if !check_scene(scene_error) {
		return false
	}

	world := &game.world.physics
	err: physics.Error
	motion.body, err = physics.create_body(
		world,
		{
			state = {position = PROBE_POSITION, orientation = 1},
			mass = physics.sphere_mass(PROBE_MASS, PROBE_RADIUS),
		},
	)
	if !check_physics(err) {
		return false
	}

	motion.colliders[0], err = physics.create_collider(
		world,
		motion.body,
		physics.Sphere{PROBE_RADIUS},
	)
	if !check_physics(err) {
		return false
	}

	motion.colliders[1], err = physics.create_collider(
		world,
		motion.body,
		physics.Sphere{MARKER_RADIUS},
		local_position = MARKER_POSITION,
	)
	return(
		check_physics(err) &&
		check_scene(scene.bind_body(&game.world, motion.probe, motion.body)) \
	)
}

apply_motion :: proc(game: ^State) -> bool {
	motion := &game.motion
	world := &game.world.physics
	ok := true
	if motion.thrust {
		ok = check_physics(physics.add_force(world, motion.body, {0, 2, 0})) && ok
	}
	if motion.push {
		ok = check_physics(physics.add_impulse(world, motion.body, {2, 0, 0}, {0, 1, 0})) && ok
		motion.push = false
	}
	if motion.spin {
		ok = check_physics(physics.add_angular_impulse(world, motion.body, {0, 2, 0})) && ok
		motion.spin = false
	}
	return ok
}

reset_motion :: proc(game: ^State) -> bool {
	motion := &game.motion
	motion.thrust, motion.push, motion.spin = false, false, false
	return check_physics(
		physics.teleport(
			&game.world.physics,
			motion.body,
			PROBE_POSITION,
			1,
			clear_velocity = true,
		),
	)
}

draw_probe :: proc(game: ^State) -> bool {
	parts := [2]struct {
		object: scene.Object,
		scale:  f32,
	}{{game.motion.probe, PROBE_RADIUS}, {game.motion.marker, 1}}
	for part, i in parts {
		model, ok := scene.world_transform(&game.world, part.object, game.simulation.interpolation)
		if !ok {
			return false
		}

		model *= emath.transform_matrix(
			{orientation = 1, scale = part.scale * emath.Vec3{1, 1, 1}},
		)
		if !common.check(
			render.add_draw(
				&game.draws,
				{
					pipeline = game.pipeline,
					mesh = game.mesh,
					material = game.materials[1 - i],
					transform = model,
				},
			),
			"submit probe",
		) {
			return false
		}
	}
	return true
}

motion_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	motion := &game.motion
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 60)
	state, ok := physics.body_state(&game.world.physics, motion.body)
	if !common.check_ui(err) || !ok {
		return false
	}

	buffer: [192]u8
	text := fmt.bprintf(
		buffer[:],
		"MASS %.0f KG\nSPEED %.2f M/S\nSPIN %.2f RAD/S\nHEIGHT %.2f M",
		PROBE_MASS,
		emath.length(state.velocity),
		emath.length(state.angular_velocity),
		state.position.y,
	)
	if !common.check_ui(ui.label(ctx, rect, text)) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !common.check_ui(err) {
		return false
	}
	_, control_error := ui.checkbox(
		ctx,
		ui.id("probe-thrust"),
		rect,
		"THRUST UP (2 N)",
		&motion.thrust,
	)
	if !common.check_ui(control_error) {
		return false
	}

	buttons := [2]struct {
		name, label: string,
		requested:   ^bool,
	} {
		{"probe-push", "IMPULSE +X / OFF CENTER", &motion.push},
		{"probe-spin", "ANGULAR IMPULSE +Y", &motion.spin},
	}
	for button in buttons {
		rect, err = ui.next(column, 28)
		if !common.check_ui(err) {
			return false
		}
		pressed, button_error := ui.button(ctx, ui.id(button.name), rect, button.label)
		if !common.check_ui(button_error) {
			return false
		}
		button.requested^ = button.requested^ || pressed
	}

	rect, err = ui.next(column, 24)
	if !common.check_ui(err) {
		return false
	}
	_, control_error = ui.checkbox(
		ctx,
		ui.id("probe-pause"),
		rect,
		"PAUSED",
		&game.simulation.paused,
	)
	return common.check_ui(control_error) && reset_button(game, column, "motion-reset")
}

reset_button :: proc(game: ^State, column: ^ui.Layout, name: string) -> bool {
	rect, err := ui.next(column, 28)
	if !common.check_ui(err) {
		return false
	}
	reset, reset_error := ui.button(&game.overlay.interface, ui.id(name), rect, "RESET SIMULATION")
	if !common.check_ui(reset_error) {
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
