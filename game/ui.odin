package game

import "core:fmt"
import "core:log"
import "ember:engine"
import "ember:input"
import render "ember:renderer"
import "ember:ui"

build_ui :: proc(app: ^engine.Context, game: ^State) -> bool {
	ctx := &game.overlay.interface
	if input.pressed(app.input, .F1) {
		game.render_window.open = !game.render_window.open
	}

	if input.pressed(app.input, .F2) {
		game.camera_window.open = !game.camera_window.open
	}

	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	if input.pressed(app.input, .F3) {
		game.bloom_window.open = !game.bloom_window.open
	}

	if input.pressed(app.input, .F4) {
		game.lighting_window.open = !game.lighting_window.open
	}

	windows := [4]^ui.Window {
		&game.render_window,
		&game.camera_window,
		&game.bloom_window,
		&game.lighting_window,
	}
	if !check_ui(ui.begin(ctx, app.input^, size, size, windows[:])) {
		return false
	}

	buffer: [128]u8
	title := fmt.bprintf(buffer[:], "FPS %3.0f", game.overlay.fps)
	if !game.render_window.collapsed {
		title = fmt.bprintf(buffer[:], "RENDER  FPS %3.0f", game.overlay.fps)
	}

	ok := build_window(game, &game.render_window, title, 0, 336, render_controls)
	ok = build_window(game, &game.camera_window, "CAMERA", 1, 160, camera_controls) && ok
	ok = build_window(game, &game.bloom_window, "BLOOM", 2, 192, bloom_controls) && ok
	ok =
		build_window(
			game,
			&game.lighting_window,
			"LIGHTING",
			3,
			376,
			shading_controls,
			{"LIGHTS", "MATERIALS"},
			&game.lighting_tab,
		) &&
		ok
	return check_ui(ui.end(ctx)) && ok
}

build_window :: proc(
	game: ^State,
	window: ^ui.Window,
	title: string,
	scroll_index: int,
	content_height: f32,
	controls: proc(_: ^State, _: ^ui.Layout) -> bool,
	tabs: []string = nil,
	selected_tab: ^int = nil,
) -> bool {
	ctx := &game.overlay.interface
	body, visible, window_error := ui.begin_window(ctx, window, title)
	if !check_ui(window_error) {
		return false
	}

	if !visible {
		return true
	}

	if len(tabs) != 0 {
		rect := ui.Rect{body.position, {body.size.x, 28}}
		changed, err := ui.tabs(ctx, ui.id("tabs", window.id), rect, tabs, selected_tab)
		if !check_ui(err) {
			check_ui(ui.end_window(ctx))
			return false
		}
		if changed {
			game.ui_scroll[scroll_index] = {}
		}
		body.position.y += 36
		body.size.y = max(body.size.y - 36, 0)
	}

	content, scroll_error := ui.begin_scroll(
		ctx,
		ui.id("content", window.id),
		body,
		{max(body.size.x - 12, 0), content_height},
		&game.ui_scroll[scroll_index],
	)
	if !check_ui(scroll_error) {
		check_ui(ui.end_window(ctx))
		return false
	}

	column, layout_error := ui.layout(content, .Column, spacing = 8)
	ok := check_ui(layout_error) && controls(game, &column)
	ok = check_ui(ui.end_scroll(ctx)) && ok
	return check_ui(ui.end_window(ctx)) && ok
}

render_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 44)
	if !check_ui(err) {
		return false
	}

	stats := game.draws.stats
	buffer: [128]u8
	value := fmt.bprintf(
		buffer[:],
		"SUBMITTED %3d\nVISIBLE   %3d\nDRAWS     %3d",
		stats.submitted,
		stats.visible,
		stats.draw_calls,
	)
	if !check_ui(ui.label(ctx, rect, value)) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}

	changed, control_error := ui.checkbox(ctx, ui.id("batching"), rect, "BATCHING", &game.batching)
	if !check_ui(control_error) ||
	   !check_ui(ui.tooltip(ctx, ui.id("batching"), "Combine matching meshes")) {
		return false
	}

	if changed {
		game.next_report = 0
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}

	_, control_error = ui.checkbox(ctx, ui.id("pause"), rect, "PAUSED", &game.paused)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 48)
	if !check_ui(err) {
		return false
	}

	_, control_error = ui.slider(
		ctx,
		ui.id("exposure"),
		rect,
		"EXPOSURE",
		&game.exposure,
		0,
		4,
		step = 0.05,
	)
	if !check_ui(control_error) ||
	   !check_ui(ui.tooltip(ctx, ui.id("exposure"), "Brightness before tone mapping")) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) || !check_ui(ui.label(ctx, rect, "TONE MAPPING")) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) {
		return false
	}

	_, control_error = ui.dropdown(
		ctx,
		ui.id("tone-mapping"),
		rect,
		{"REINHARD", "ACES FITTED"},
		&game.tone_mapping,
	)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 24)
	if !check_ui(err) || !check_ui(ui.label(ctx, rect, "NOTE")) {
		return false
	}

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}

	_, control_error = ui.text_field(ctx, ui.id("note"), rect, &game.note)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 32)
	if !check_ui(err) || !check_ui(ui.image(ctx, {rect.position, {32, 32}}, game.preview.handle)) {
		return false
	}

	return check_ui(
		ui.label(
			ctx,
			{rect.position + [2]f32{40, 0}, {max(rect.size.x - 40, 0), rect.size.y}},
			"CLIP TEST 0123456789",
		),
	)
}

camera_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 48)
	if !check_ui(err) {
		return false
	}

	_, control_error := ui.slider(
		ctx,
		ui.id("distance"),
		rect,
		"DISTANCE",
		&game.orbit.distance,
		3,
		100,
		step = 1,
	)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 48)
	if !check_ui(err) {
		return false
	}

	_, control_error = ui.slider(
		ctx,
		ui.id("pitch"),
		rect,
		"PITCH",
		&game.orbit.pitch,
		-1.45,
		1.45,
		step = 0.05,
	)
	if !check_ui(control_error) {
		return false
	}

	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}

	clicked, button_error := ui.button(ctx, ui.id("reset-camera"), rect, "RESET CAMERA")
	if !check_ui(button_error) {
		return false
	}

	if clicked {
		game.orbit = INITIAL_ORBIT
	}

	return true
}

check_ui :: proc(err: ui.Error) -> bool {
	if err != .None {
		log.errorf("UI: %v", err)
	}

	return err == .None
}

bloom_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	rect, err := ui.next(column, 24)
	if !check_ui(err) {
		return false
	}

	_, control_error := ui.checkbox(
		ctx,
		ui.id("bloom-enabled"),
		rect,
		"ENABLED",
		&game.bloom_enabled,
	)
	if !check_ui(control_error) {
		return false
	}

	for control in ([3]struct {
			name, label: string,
			value:       ^f32,
			high:        f32,
		} {
			{"bloom-threshold", "THRESHOLD", &game.bloom_settings.threshold, 4},
			{"bloom-softness", "SOFTNESS", &game.bloom_settings.softness, 1},
			{"bloom-strength", "STRENGTH", &game.bloom_strength, 1},
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
			0,
			control.high,
			step = 0.01,
			enabled = game.bloom_enabled,
		)
		if !check_ui(control_error) {
			return false
		}
	}
	return true
}

lighting_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	for control in ([2]struct {
			name, label: string,
			value:       ^bool,
		} {
			{"directional-enabled", "DIRECTIONAL", &game.directional_enabled},
			{"point-enabled", "POINT", &game.point_enabled},
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

	for control in ([3]struct {
			name, label: string,
			value:       ^f32,
			low, high:   f32,
		} {
			{"light-intensity", "INTENSITY", &game.light_intensity, 0, 8},
			{"light-azimuth", "AZIMUTH", &game.light_azimuth, -3.14, 3.14},
			{"light-elevation", "ELEVATION", &game.light_elevation, -1.57, 1.57},
		}) {
		rect, err := ui.next(column, 48)
		if !check_ui(err) {
			return false
		}

		_, control_error := ui.slider(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
			control.low,
			control.high,
			step = 0.05,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	rect, err := ui.next(column, 24)
	if !check_ui(err) {
		return false
	}
	_, control_error := ui.checkbox(
		ctx,
		ui.id("shadows"),
		rect,
		"SHADOWS",
		&game.shadow_settings.enabled,
	)
	if !check_ui(control_error) {
		return false
	}
	for control in ([2]struct {
			name, label: string,
			value:       ^f32,
		} {
			{"shadow-bias", "BIAS", &game.shadow_settings.bias},
			{"shadow-slope-bias", "SLOPE BIAS", &game.shadow_settings.slope_bias},
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
			0,
			0.01,
			step = 0.0001,
			precision = 4,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	return true
}
