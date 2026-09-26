package game

import "../common"

import "core:fmt"
import "core:math"
import emath "ember:core/math"
import "ember:physics"
import "ember:ui"

FLOOR_TOP :: f32(-3.5)
PADDLE_HALF :: emath.Vec3{0.3, 1.2, 2}
SENSOR_POSITION :: emath.Vec3{0, -2, 4.5}
GRAVITY :: f32(9.81)

Contacts :: struct {
	paddle:                physics.Body_Handle,
	sensor:                physics.Collider_Handle,
	gravity, move_paddle:  bool,
	paddle_time:           f32,
	friction, restitution: f32,
	// Counted from contact events since the last reset.
	begins, ends:          int,
	colliders_in_sensor:   int,
	peak_impulse:          f32,
}

init_contacts :: proc(game: ^State) -> bool {
	contacts := &game.contacts
	world := &game.world.physics
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

	contacts.paddle, err = physics.create_body(
		world,
		{motion = .Kinematic, state = {position = paddle_position(0), orientation = 1}},
	)
	if !check_physics(err) {
		return false
	}
	_, err = physics.create_collider(world, contacts.paddle, physics.Box{PADDLE_HALF})
	if !check_physics(err) {
		return false
	}

	zone: physics.Body_Handle
	zone, err = physics.create_body(
		world,
		{motion = .Static, state = {position = SENSOR_POSITION, orientation = 1}},
	)
	if !check_physics(err) {
		return false
	}
	contacts.sensor, err = physics.create_collider(
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
	contacts := &game.contacts
	world := &game.world.physics
	if contacts.gravity &&
	   !check_physics(physics.add_force(world, game.motion.body, {0, -GRAVITY * PROBE_MASS, 0})) {
		return false
	}
	if !contacts.move_paddle {
		return true
	}

	contacts.paddle_time += dt
	return check_physics(
		physics.move_kinematic(world, contacts.paddle, paddle_position(contacts.paddle_time), 1),
	)
}

apply_probe_material :: proc(game: ^State) -> bool {
	material := physics.Collider_Material {
		friction    = game.contacts.friction,
		restitution = game.contacts.restitution,
	}
	for collider in game.motion.colliders {
		if !check_physics(physics.set_collider_material(&game.world.physics, collider, material)) {
			return false
		}
	}
	return true
}

// Runs after the step, so the events match the state the step just produced.
read_contacts :: proc(game: ^State) {
	contacts := &game.contacts
	world := &game.world.physics
	for event in physics.contact_events(world) {
		if event.sensor {
			if event.collider_a == contacts.sensor || event.collider_b == contacts.sensor {
				contacts.colliders_in_sensor += 1 if event.kind == .Begin else -1
			}
			continue
		}
		switch event.kind {
		case .Begin:
			contacts.begins += 1
		case .End:
			contacts.ends += 1
		}
	}

	buffer: [64]physics.Contact
	written, _ := physics.contacts(world, buffer[:])
	for contact in buffer[:written] {
		contacts.peak_impulse = max(contacts.peak_impulse, contact.impulse)
	}
}

reset_contacts :: proc(game: ^State) -> bool {
	contacts := &game.contacts
	contacts.paddle_time = 0
	contacts.begins, contacts.ends = 0, 0
	contacts.colliders_in_sensor = 0
	contacts.peak_impulse = 0
	return check_physics(
		physics.move_kinematic(&game.world.physics, contacts.paddle, paddle_position(0), 1),
	)
}

contact_lines :: proc(game: ^State) -> bool {
	if !check_physics(physics.debug_world(&game.world.physics, emit_body_line, game)) {
		return false
	}

	buffer: [64]physics.Contact
	written, _ := physics.contacts(&game.world.physics, buffer[:])
	for contact in buffer[:written] {
		if contact.sensor {
			emit_marker(game, contact.position, {}, {1, 0.85, 0.2})
		} else {
			emit_marker(game, contact.position, contact.normal * 0.6, {0.3, 1, 0.4})
		}
	}
	return common.check(game.line_error, "build contact lines")
}

emit_body_line :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	game := cast(^State)userdata
	color := [3]f32{0.4, 0.5, 0.6}
	if collider == game.contacts.sensor {
		color = {1, 0.85, 0.2} if game.contacts.colliders_in_sensor > 0 else {0.6, 0.5, 0.25}
	}
	emit_line(game, a, b, color)
}

contact_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	contacts := &game.contacts
	ctx := &game.overlay.interface
	checkboxes := [2]struct {
		name, label: string,
		value:       ^bool,
	} {
		{"gravity", "GRAVITY (9.81 M/S2)", &contacts.gravity},
		{"paddle", "MOVE PADDLE", &contacts.move_paddle},
	}
	for checkbox in checkboxes {
		rect, err := ui.next(column, 24)
		if !common.check_ui(err) {
			return false
		}
		_, control_error := ui.checkbox(
			ctx,
			ui.id(checkbox.name),
			rect,
			checkbox.label,
			checkbox.value,
		)
		if !common.check_ui(control_error) {
			return false
		}
	}

	sliders := [2]struct {
		name, label: string,
		value:       ^f32,
	} {
		{"probe-friction", "PROBE FRICTION", &contacts.friction},
		{"probe-restitution", "PROBE RESTITUTION", &contacts.restitution},
	}
	for slider in sliders {
		rect, err := ui.next(column, 48)
		if !common.check_ui(err) {
			return false
		}
		changed, control_error := ui.slider(
			ctx,
			ui.id(slider.name),
			rect,
			slider.label,
			slider.value,
			0,
			1,
			step = 0.05,
		)
		if !common.check_ui(control_error) || (changed && !apply_probe_material(game)) {
			return false
		}
	}

	rect, err := ui.next(column, 72)
	if !common.check_ui(err) {
		return false
	}
	buffer: [192]u8
	_, total := physics.contacts(&game.world.physics, nil)
	text := fmt.bprintf(
		buffer[:],
		"CONTACTS %d\nBEGIN %d  END %d\nPEAK IMPULSE %.2f NS\n%s",
		total,
		contacts.begins,
		contacts.ends,
		contacts.peak_impulse,
		"IN SENSOR" if contacts.colliders_in_sensor > 0 else "OUTSIDE SENSOR",
	)
	return(
		common.check_ui(ui.label(ctx, rect, text)) &&
		reset_button(game, column, "contacts-reset") \
	)
}
