package game

import "core:fmt"
import "core:log"
import "ember:engine"
import "ember:ui"

build_ui :: proc(app: ^engine.Context, game: ^State) -> bool {
	ctx := &game.interface
	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	if !check_ui(ui.begin(ctx, app.input^, size, size)) {
		return false
	}

	defer {
		for len(ctx.scrolls) > 0 {
			if ui.end_scroll(ctx) != .None {
				break
			}
		}

		if ctx.frame_active {
			ui.end(ctx)
		}
	}
	buffer: [128]u8
	body, panel_error := ui.collapsible_panel(
		ctx,
		ui.id("overlay"),
		{{24, 24}, {min(360, max(size.x - 48, 0)), min(432, max(size.y - 48, 0))}},
		fmt.bprintf(buffer[:], "FPS %3.0f", game.fps),
		&game.overlay_expanded,
	)
	if !check_ui(panel_error) {
		return false
	}

	if !game.overlay_expanded {
		return check_ui(ui.end(ctx))
	}

	tabs_rect := ui.Rect{body.position, {body.size.x, min(body.size.y, 28)}}
	_, tabs_error := ui.tabs(ctx, ui.id("tabs"), tabs_rect, {"RENDER", "CAMERA"}, &game.ui_tab)
	if !check_ui(tabs_error) {
		return false
	}

	header_height := min(body.size.y, 36)
	viewport := ui.Rect {
		body.position + [2]f32{0, header_height},
		{body.size.x, body.size.y - header_height},
	}
	content_height: f32 = 336 if game.ui_tab == 0 else 160
	content, scroll_error := ui.begin_scroll(
		ctx,
		ui.id("content"),
		viewport,
		{max(viewport.size.x - 12, 0), content_height},
		&game.ui_scroll[game.ui_tab],
	)
	if !check_ui(scroll_error) {
		return false
	}

	column, layout_error := ui.layout(content, .Column, spacing = 8)
	if !check_ui(layout_error) {
		return false
	}

	if game.ui_tab == 0 {
		if !render_controls(game, &column) {
			return false
		}
	} else if !camera_controls(game, &column) {
		return false
	}

	if !check_ui(ui.end_scroll(ctx)) {
		return false
	}

	return check_ui(ui.end(ctx))
}

render_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.interface
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
	ctx := &game.interface
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
