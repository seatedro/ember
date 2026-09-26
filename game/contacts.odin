package game

import "core:fmt"
import "core:math"
import emath "ember:core/math"
import "ember:physics"
import render "ember:renderer"
import "ember:ui"

FLOOR_TOP :: f32(-3.5)
PADDLE_HALF :: emath.Vec3{0.3, 1.2, 2}
SENSOR_POSITION :: emath.Vec3{0, -2, 4.5}

init_contacts :: proc(game: ^State) -> bool {
	world := &game.world.physics
	game.probe_friction, game.probe_restitution = 0.5, 0.15
	if !apply_probe_material(game) {
		return false
	}

	floor, err := physics.create_body(
		world,
		{motion = .Static, state = {position = {0, FLOOR_TOP - 0.5, 0}, orientation = 1}},
	)
	if !check_physics(err) {
		return false
	}
	_, err = physics.create_collider(world, floor, physics.Box{{8, 0.5, 8}})
	if !check_physics(err) {
		return false
	}

	game.paddle, err = physics.create_body(
		world,
		{motion = .Kinematic, state = {position = paddle_position(0), orientation = 1}},
	)
	if !check_physics(err) {
		return false
	}
	_, err = physics.create_collider(world, game.paddle, physics.Box{PADDLE_HALF})
	if !check_physics(err) {
		return false
	}

	zone, zone_error := physics.create_body(
		world,
		{motion = .Static, state = {position = SENSOR_POSITION, orientation = 1}},
	)
	if !check_physics(zone_error) {
		return false
	}
	game.sensor, err = physics.create_collider(
		world,
		zone,
		physics.Box{{1.5, 1.5, 1.5}},
		sensor = true,
	)
	return check_physics(err)
}

paddle_position :: proc(time: f32) -> emath.Vec3 {
	return {5 * math.sin(time * 0.8), FLOOR_TOP + PADDLE_HALF.y, 0}
}

update_contacts :: proc(game: ^State, dt: f32) -> bool {
	world := &game.world.physics
	if game.gravity &&
	   !check_physics(physics.add_force(world, game.probe_body, {0, -9.81 * PROBE_MASS, 0})) {
		return false
	}
	if game.paddle_moving {
		game.paddle_time += dt
		return check_physics(
			physics.move_kinematic(world, game.paddle, paddle_position(game.paddle_time), 1),
		)
	}
	return true
}

apply_probe_material :: proc(game: ^State) -> bool {
	material := physics.Collider_Material {
		friction    = game.probe_friction,
		restitution = game.probe_restitution,
	}
	for collider in game.probe_colliders {
		if !check_physics(physics.set_collider_material(&game.world.physics, collider, material)) {
			return false
		}
	}
	return true
}

// Runs after the step, so the events match the state the step just produced.
read_contacts :: proc(game: ^State) {
	world := &game.world.physics
	for event in physics.contact_events(world) {
		if event.sensor {
			if event.collider_a == game.sensor || event.collider_b == game.sensor {
				game.colliders_in_sensor += 1 if event.kind == .Begin else -1
			}
			continue
		}
		switch event.kind {
		case .Begin:
			game.contact_begins += 1
		case .End:
			game.contact_ends += 1
		}
	}

	buffer: [64]physics.Contact
	written, _ := physics.contacts(world, buffer[:])
	for contact in buffer[:written] {
		game.peak_impulse = max(game.peak_impulse, contact.impulse)
	}
}

reset_contacts :: proc(game: ^State) -> bool {
	game.paddle_time = 0
	game.contact_begins, game.contact_ends = 0, 0
	game.peak_impulse = 0
	game.colliders_in_sensor = 0
	return check_physics(
		physics.move_kinematic(&game.world.physics, game.paddle, paddle_position(0), 1),
	)
}

contact_lines :: proc(game: ^State) -> bool {
	render.clear_debug_lines(&game.debug_lines)
	game.debug_error = .None
	if !check_physics(physics.debug_world(&game.world.physics, emit_body_line, game)) {
		return false
	}

	buffer: [64]physics.Contact
	written, _ := physics.contacts(&game.world.physics, buffer[:])
	for contact in buffer[:written] {
		color := [3]f32{1, 0.85, 0.2} if contact.sensor else [3]f32{0.3, 1, 0.4}
		for axis in 0 ..< 3 {
			delta: emath.Vec3
			delta[axis] = 0.12
			emit_query_line(game, contact.position - delta, contact.position + delta, color)
		}
		if !contact.sensor {
			emit_query_line(game, contact.position, contact.position + contact.normal * 0.6, color)
		}
	}
	return check(game.debug_error, "build contact lines")
}

emit_body_line :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	game := cast(^State)userdata
	color := [3]f32{0.4, 0.5, 0.6}
	if collider == game.sensor {
		color = {1, 0.85, 0.2} if game.colliders_in_sensor > 0 else {0.6, 0.5, 0.25}
	}
	emit_query_line(game, a, b, color)
}

contact_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	for control in ([2]struct {
			name, label: string,
			value:       ^bool,
		} {
			{"gravity", "GRAVITY (9.81 M/S2)", &game.gravity},
			{"paddle", "MOVE PADDLE", &game.paddle_moving},
		}) {
		rect, err := ui.next(column, 24)
		if !check_ui(err) {
			return false
		}
		_, control_error := ui.checkbox(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	for control in ([2]struct {
			name, label: string,
			value:       ^f32,
		} {
			{"probe-friction", "PROBE FRICTION", &game.probe_friction},
			{"probe-restitution", "PROBE RESTITUTION", &game.probe_restitution},
		}) {
		rect, err := ui.next(column, 48)
		if !check_ui(err) {
			return false
		}
		changed, control_error := ui.slider(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
			0,
			1,
			step = 0.05,
		)
		if !check_ui(control_error) || (changed && !apply_probe_material(game)) {
			return false
		}
	}

	rect, err := ui.next(column, 72)
	if !check_ui(err) {
		return false
	}
	buffer: [192]u8
	_, total := physics.contacts(&game.world.physics, nil)
	text := fmt.bprintf(
		buffer[:],
		"CONTACTS %d\nBEGIN %d  END %d\nPEAK IMPULSE %.2f NS\n%s",
		total,
		game.contact_begins,
		game.contact_ends,
		game.peak_impulse,
		"IN SENSOR" if game.colliders_in_sensor > 0 else "OUTSIDE SENSOR",
	)
	if !check_ui(ui.label(ctx, rect, text)) {
		return false
	}

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	reset, reset_error := ui.button(ctx, ui.id("contacts-reset"), rect, "RESET SIMULATION")
	if !check_ui(reset_error) {
		return false
	}
	if reset {
		reset_simulation(game)
	}
	return true
}
