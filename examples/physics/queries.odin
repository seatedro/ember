package game

import "../common"

import "core:fmt"
import emath "ember:core/math"
import "ember:physics"
import render "ember:renderer"
import "ember:ui"

QUERY_DISPLACEMENT :: emath.Vec3{10, 0, 0}
OBSTACLE_CATEGORY :: u32(2)

Query_Mode :: enum {
	Ray,
	Shape_Cast,
	Overlap,
}

Query_Shape :: enum {
	Sphere,
	Box,
	Capsule,
}

Queries :: struct {
	mode:          Query_Mode,
	shape:         Query_Shape,
	origin:        emath.Vec3,
	include_probe: bool,
	result:        Query_Result,
}

// Rewritten by every run_query.
Query_Result :: struct {
	hit:      physics.Query_Hit,
	found:    bool,
	overlaps: [8]physics.Overlap_Hit,
	total:    int,
}

init_queries :: proc(game: ^State) -> bool {
	world := &game.world.physics
	obstacles := [2]struct {
		shape:       physics.Shape,
		position:    emath.Vec3,
		orientation: emath.Quaternion,
	} {
		{physics.Box{{0.8, 1.3, 0.8}}, {3, 0, -2}, emath.quaternion_angle_axis(0.35, {0, 1, 0})},
		{physics.Capsule{0.6, 0.9}, {-3, 0, 2}, 1},
	}
	for obstacle in obstacles {
		body, err := physics.create_body(
			world,
			{
				motion = .Static,
				state = {position = obstacle.position, orientation = obstacle.orientation},
			},
		)
		if !check_physics(err) {
			return false
		}

		_, err = physics.create_collider(
			world,
			body,
			obstacle.shape,
			filter = {category = OBSTACLE_CATEGORY, mask = 0xffff_ffff},
		)
		if !check_physics(err) {
			return false
		}
	}
	return true
}

query_shape :: proc(shape: Query_Shape) -> physics.Shape {
	switch shape {
	case .Sphere:
		return physics.Sphere{0.5}
	case .Box:
		return physics.Box{{0.5, 0.5, 0.5}}
	case .Capsule:
		return physics.Capsule{0.4, 0.5}
	}
	return nil
}

run_query :: proc(game: ^State) -> bool {
	queries := &game.queries
	world := &game.world.physics
	filter := physics.ALL_QUERIES
	if !queries.include_probe {
		filter.collision.mask = OBSTACLE_CATEGORY
	}

	result := &queries.result
	result^ = {}
	err: physics.Error
	switch queries.mode {
	case .Ray:
		result.hit, result.found, err = physics.cast_ray(
			world,
			queries.origin,
			QUERY_DISPLACEMENT,
			filter,
		)
	case .Shape_Cast:
		result.hit, result.found, err = physics.cast_shape(
			world,
			query_shape(queries.shape),
			queries.origin,
			1,
			QUERY_DISPLACEMENT,
			filter,
		)
	case .Overlap:
		_, result.total, err = physics.overlap_shape(
			world,
			query_shape(queries.shape),
			queries.origin,
			1,
			result.overlaps[:],
			filter,
		)
	}
	return check_physics(err)
}

query_lines :: proc(game: ^State) -> bool {
	queries := &game.queries
	result := queries.result
	// Queries see the last simulation state, so draw their debug shapes from it
	// too.
	if !check_physics(physics.debug_world(&game.world.physics, emit_collider_line, game)) {
		return false
	}

	origin := queries.origin
	shape := query_shape(queries.shape)
	if queries.mode != .Overlap {
		emit_line(game, origin, origin + QUERY_DISPLACEMENT, {0.6, 0.4, 0.8})
	}
	if queries.mode != .Ray &&
	   !check_physics(physics.debug_shape(shape, origin, 1, emit_query_shape, game)) {
		return false
	}

	if result.found {
		emit_marker(game, result.hit.position, result.hit.normal, {0.3, 1, 0.4})
		if queries.mode == .Shape_Cast &&
		   !check_physics(
				   physics.debug_shape(
					   shape,
					   origin + QUERY_DISPLACEMENT * result.hit.fraction,
					   1,
					   emit_query_shape,
					   game,
				   ),
			   ) {
			return false
		}
	}
	return common.check(game.line_error, "build query lines")
}

emit_collider_line :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	game := cast(^State)userdata
	result := &game.queries.result
	hit := result.found && result.hit.collider == collider
	for overlap in result.overlaps[:min(result.total, len(result.overlaps))] {
		hit = hit || overlap.collider == collider
	}
	emit_line(game, a, b, {0.3, 1, 0.4} if hit else {0.4, 0.5, 0.6})
}

emit_query_shape :: proc(a, b: emath.Vec3, collider: physics.Collider_Handle, userdata: rawptr) {
	emit_line(cast(^State)userdata, a, b, {0.65, 0.45, 1})
}

// A small cross at position, with a line along normal when there is one.
emit_marker :: proc(game: ^State, position, normal: emath.Vec3, color: [3]f32) {
	for axis in 0 ..< 3 {
		delta: emath.Vec3
		delta[axis] = 0.12
		emit_line(game, position - delta, position + delta, color)
	}
	if normal != {} {
		emit_line(game, position, position + normal, color)
	}
}

// Keeps the first error; query_lines and contact_lines report it.
emit_line :: proc(game: ^State, a, b: emath.Vec3, color: [3]f32) {
	if game.line_error == .None {
		game.line_error = render.add_debug_line(&game.lines, a, b, color)
	}
}

query_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	queries := &game.queries
	ctx := &game.overlay.interface
	dropdowns := [2]struct {
		name:     string,
		items:    []string,
		selected: ^int,
		enabled:  bool,
	} {
		{"query-mode", {"RAY", "SHAPE CAST", "OVERLAP"}, (^int)(&queries.mode), true},
		{
			"query-shape",
			{"SPHERE", "BOX", "CAPSULE"},
			(^int)(&queries.shape),
			queries.mode != .Ray,
		},
	}
	for dropdown in dropdowns {
		rect, err := ui.next(column, 28)
		if !common.check_ui(err) {
			return false
		}
		_, control_error := ui.dropdown(
			ctx,
			ui.id(dropdown.name),
			rect,
			dropdown.items,
			dropdown.selected,
			enabled = dropdown.enabled,
		)
		if !common.check_ui(control_error) {
			return false
		}
	}

	sliders := [3]struct {
		name, label: string,
		value:       ^f32,
	} {
		{"query-x", "START X", &queries.origin.x},
		{"query-y", "HEIGHT", &queries.origin.y},
		{"query-z", "DEPTH", &queries.origin.z},
	}
	for slider in sliders {
		rect, err := ui.next(column, 48)
		if !common.check_ui(err) {
			return false
		}
		_, control_error := ui.slider(
			ctx,
			ui.id(slider.name),
			rect,
			slider.label,
			slider.value,
			-5,
			5,
			step = 0.1,
		)
		if !common.check_ui(control_error) {
			return false
		}
	}

	rect, err := ui.next(column, 24)
	if !common.check_ui(err) {
		return false
	}
	_, control_error := ui.checkbox(
		ctx,
		ui.id("query-probe"),
		rect,
		"INCLUDE MOVING BODY",
		&queries.include_probe,
	)
	if !common.check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 48)
	if !common.check_ui(err) {
		return false
	}
	buffer: [128]u8
	return common.check_ui(ui.label(ctx, rect, query_summary(queries^, buffer[:])))
}

@(private = "file")
query_summary :: proc(queries: Queries, buffer: []u8) -> string {
	result := queries.result
	switch {
	case queries.mode == .Overlap:
		return fmt.bprintf(buffer[:], "OVERLAPS %d", result.total)
	case !result.found:
		return "NO HIT"
	case result.hit.started_overlapping:
		return "STARTING IN CONTACT"
	}
	return fmt.bprintf(
		buffer,
		"DISTANCE %.3f M\nNORMAL\n%.2f %.2f %.2f",
		result.hit.fraction * emath.length(QUERY_DISPLACEMENT),
		result.hit.normal.x,
		result.hit.normal.y,
		result.hit.normal.z,
	)
}
