package game

import "core:fmt"
import emath "ember:core/math"
import "ember:physics"
import render "ember:renderer"
import "ember:ui"

init_queries :: proc(game: ^State) -> bool {
	world := &game.world.physics
	_, err := physics.create_collider(world, game.probe_body, physics.Sphere{1.4})
	if !check_physics(err) {
		return false
	}
	_, err = physics.create_collider(
		world,
		game.probe_body,
		physics.Sphere{0.3},
		local_pose = {position = {2, 0, 0}, orientation = 1},
	)
	if !check_physics(err) {
		return false
	}
	obstacles := [2]struct {
		shape: physics.Shape,
		pose:  emath.Pose,
	} {
		{
			physics.Box{{0.8, 1.3, 0.8}},
			{position = {3, 0, -2}, orientation = emath.quaternion_angle_axis(0.35, {0, 1, 0})},
		},
		{physics.Capsule{0.6, 0.9}, {position = {-3, 0, 2}, orientation = 1}},
	}
	for obstacle in obstacles {
		body, error := physics.create_body(
			world,
			{motion = .Static, state = {pose = obstacle.pose}},
		)
		if !check_physics(error) {
			return false
		}
		_, err = physics.create_collider(
			world,
			body,
			obstacle.shape,
			filter = {category = 2, mask = 0xffff_ffff},
		)
		if !check_physics(err) {
			return false
		}
	}
	return true
}

query_shape :: proc(game: ^State) -> physics.Shape {
	switch game.query_shape {
	case 1:
		return physics.Box{{0.5, 0.5, 0.5}}
	case 2:
		return physics.Capsule{0.4, 0.5}
	}
	return physics.Sphere{0.5}
}

update_queries :: proc(game: ^State) -> bool {
	world := &game.world.physics
	filter := physics.ALL_QUERIES
	if !game.query_probe {
		filter.collision.mask = 2
	}
	origin := emath.Vec3{game.query_x, game.query_y, game.query_z}
	displacement := emath.Vec3{10, 0, 0}
	game.query_hit, game.query_found, game.query_total = {}, false, 0
	err: physics.Error
	switch game.query_mode {
	case 0:
		game.query_hit, game.query_found, err = physics.cast_ray(
			world,
			origin,
			displacement,
			filter,
		)
	case 1:
		game.query_hit, game.query_found, err = physics.cast_shape(
			world,
			query_shape(game),
			{position = origin, orientation = 1},
			displacement,
			filter,
		)
	case 2:
		_, game.query_total, err = physics.overlap_shape(
			world,
			query_shape(game),
			{position = origin, orientation = 1},
			game.query_overlaps[:],
			filter,
		)
	}
	return check_physics(err)
}

query_lines :: proc(game: ^State) -> bool {
	render.clear_debug_lines(&game.debug_lines)
	game.debug_error = .None
	// Queries use the last simulation pose, so their debug geometry uses it too.
	if !check_physics(physics.debug_world(&game.world.physics, emit_collider_line, game)) {
		return false
	}
	origin := emath.Vec3{game.query_x, game.query_y, game.query_z}
	displacement := emath.Vec3{10, 0, 0}
	if game.query_mode != 2 {
		emit_query_line(game, origin, origin + displacement, {0.6, 0.4, 0.8})
	}
	if game.query_mode != 0 {
		if !check_physics(
			physics.debug_shape(
				query_shape(game),
				{position = origin, orientation = 1},
				emit_query_shape,
				game,
			),
		) {
			return false
		}
	}
	if game.query_found {
		hit := game.query_hit
		emit_query_line(game, hit.position, hit.position + hit.normal, {0.3, 1, 0.4})
		for axis in 0 ..< 3 {
			delta: emath.Vec3
			delta[axis] = 0.12
			emit_query_line(game, hit.position - delta, hit.position + delta, {0.3, 1, 0.4})
		}
		if game.query_mode == 1 {
			if !check_physics(
				physics.debug_shape(
					query_shape(game),
					{position = origin + displacement * hit.fraction, orientation = 1},
					emit_query_shape,
					game,
				),
			) {
				return false
			}
		}
	}
	return check(game.debug_error, "build query lines")
}

emit_collider_line :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	game := cast(^State)userdata
	hit := game.query_found && game.query_hit.collider == collider
	for overlap in game.query_overlaps[:min(game.query_total, len(game.query_overlaps))] {
		hit = hit || overlap.collider == collider
	}
	color: [3]f32 = {0.4, 0.5, 0.6}
	if hit {
		color = {0.3, 1, 0.4}
	}
	emit_query_line(game, a, b, color)
}

emit_query_shape :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	emit_query_line(cast(^State)userdata, a, b, {0.65, 0.45, 1})
}

emit_query_line :: proc(game: ^State, a, b: emath.Vec3, color: [3]f32) {
	if game.debug_error == .None {
		game.debug_error = render.add_debug_line(&game.debug_lines, a, b, color)
	}
}

query_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	_, control_error := ui.dropdown(
		ctx,
		ui.id("query-mode"),
		rect,
		{"RAY", "SHAPE CAST", "OVERLAP"},
		&game.query_mode,
	)
	if !check_ui(control_error) {
		return false
	}
	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	_, control_error = ui.dropdown(
		ctx,
		ui.id("query-shape"),
		rect,
		{"SPHERE", "BOX", "CAPSULE"},
		&game.query_shape,
		enabled = game.query_mode != 0,
	)
	if !check_ui(control_error) {
		return false
	}
	for control in ([3]struct {
			name, label: string,
			value:       ^f32,
		} {
			{"query-x", "START X", &game.query_x},
			{"query-y", "HEIGHT", &game.query_y},
			{"query-z", "DEPTH", &game.query_z},
		}) {
		rect, err = ui.next(column, 48)
		if !check_ui(err) {
			return false
		}
		_, control_error = ui.slider(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
			-5,
			5,
			step = 0.1,
		)
		if !check_ui(control_error) {
			return false
		}
	}
	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}
	_, control_error = ui.checkbox(
		ctx,
		ui.id("query-probe"),
		rect,
		"INCLUDE MOVING BODY",
		&game.query_probe,
	)
	if !check_ui(control_error) {
		return false
	}
	rect, err = ui.next(column, 48)
	if !check_ui(err) || !update_queries(game) {
		return false
	}
	buffer: [128]u8
	text := "NO HIT"
	if game.query_mode == 2 {
		text = fmt.bprintf(buffer[:], "OVERLAPS %d", game.query_total)
	} else if game.query_found {
		text = fmt.bprintf(
			buffer[:],
			"DISTANCE %.3f M\nNORMAL\n%.2f %.2f %.2f",
			game.query_hit.fraction * 10,
			game.query_hit.normal.x,
			game.query_hit.normal.y,
			game.query_hit.normal.z,
		)
		if game.query_hit.started_overlapping {
			text = "STARTING IN CONTACT"
		}
	}
	return check_ui(ui.label(ctx, rect, text))
}
