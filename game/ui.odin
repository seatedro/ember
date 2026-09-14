package game

import "core:fmt"
import "core:log"
import "ember:engine"
import "ember:input"
import "ember:ui"

build_ui :: proc(app: ^engine.Context, game: ^State) -> bool {
	ctx := &game.overlay.interface
	if input.pressed(app.input, .F5) {
		reset_ui_layout(game)
	}
	if input.pressed(app.input, .F1) {
		game.physics_window.open = !game.physics_window.open
	}

	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	windows := ui_windows(game)
	if !check_ui(ui.begin(ctx, app.input^, size, size, windows[:])) {
		return false
	}

	buffer: [128]u8
	title := fmt.bprintf(buffer[:], "PHYSICS  FPS %3.0f", game.overlay.fps)
	if game.physics_window.collapsed {
		title = fmt.bprintf(buffer[:], "FPS %3.0f", game.overlay.fps)
	}
	ok := build_physics_window(game, title)
	ok = check_ui(ui.end(ctx)) && ok
	if app.elapsed_time >= game.next_ui_save {
		save_ui_layout(game)
		game.next_ui_save = app.elapsed_time + 1
	}
	return ok
}

build_physics_window :: proc(game: ^State, title: string) -> bool {
	ctx := &game.overlay.interface
	body, visible, window_error := ui.begin_window(ctx, &game.physics_window, title)
	if !check_ui(window_error) {
		return false
	}
	if !visible {
		return true
	}

	tab_rect := ui.Rect{body.position, {body.size.x, 28}}
	changed, tab_error := ui.tabs(
		ctx,
		ui.id("physics-tabs"),
		tab_rect,
		{"MOTION", "QUERIES"},
		&game.physics_tab,
	)
	if !check_ui(tab_error) {
		check_ui(ui.end_window(ctx))
		return false
	}
	if changed {
		game.ui_scroll = {}
	}
	body.position.y += 36
	body.size.y = max(body.size.y - 36, 0)

	content, scroll_error := ui.begin_scroll(
		ctx,
		ui.id("physics-content"),
		body,
		{max(body.size.x - 12, 0), 360 if game.physics_tab == 1 else 280},
		&game.ui_scroll,
	)
	if !check_ui(scroll_error) {
		check_ui(ui.end_window(ctx))
		return false
	}

	column, layout_error := ui.layout(content, .Column, spacing = 8)
	controls := query_controls if game.physics_tab == 1 else physics_controls
	ok := check_ui(layout_error) && controls(game, &column)
	ok = check_ui(ui.end_scroll(ctx)) && ok
	return check_ui(ui.end_window(ctx)) && ok
}

check_ui :: proc(err: ui.Error) -> bool {
	if err != .None {
		log.errorf("UI: %v", err)
	}

	return err == .None
}
