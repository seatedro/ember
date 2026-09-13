package game

import "core:fmt"
import "core:log"
import "ember:engine"
import "ember:input"
import "ember:particles"
import "ember:ui"

build_ui :: proc(app: ^engine.Context, game: ^State) -> bool {
	ctx := &game.interface
	if input.pressed(app.input, .F1) {
		game.window.open = !game.window.open
	}

	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	if !check_ui(ui.begin(ctx, app.input^, size, size, {&game.window})) {
		return false
	}

	buffer: [128]u8
	title := fmt.bprintf(buffer[:], "PARTICLES  FPS %3.0f", game.fps)
	if game.window.collapsed {
		title = fmt.bprintf(buffer[:], "FPS %3.0f", game.fps)
	}
	body, visible, err := ui.begin_window(ctx, &game.window, title)
	ok := check_ui(err)
	if visible && ok {
		content, scroll_error := ui.begin_scroll(
			ctx,
			ui.id("particle-controls"),
			body,
			{max(body.size.x - 12, 0), 564},
			&game.scroll,
		)
		ok = check_ui(scroll_error)
		if ok {
			column, layout_error := ui.layout(content, .Column, spacing = 8)
			ok = check_ui(layout_error) && controls(game, &column)
			ok = check_ui(ui.end_scroll(ctx)) && ok
		}

		ok = check_ui(ui.end_window(ctx)) && ok
	}

	return check_ui(ui.end(ctx)) && ok
}

controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.interface
	rect, err := ui.next(column, 44)
	buffer: [128]u8
	stats := fmt.bprintf(
		buffer[:],
		"ALIVE %4d / %d\nREPLACED %d\nDRAWS %d",
		game.emitter.count,
		CAPACITY,
		game.emitter.replaced,
		game.billboards.stats.draw_calls,
	)
	if !check_ui(err) || !check_ui(ui.label(ctx, rect, stats)) {
		return false
	}
	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	changed, control_error := ui.dropdown(
		ctx,
		ui.id("preset"),
		rect,
		{"THRUSTER", "BURST"},
		&game.preset,
	)
	if !check_ui(control_error) {
		return false
	}

	if changed {
		set_preset(game)
	}
	rect, err = ui.next(column, 28)
	if !check_ui(err) {
		return false
	}
	_, control_error = ui.dropdown(ctx, ui.id("blend"), rect, {"ALPHA", "ADDITIVE"}, &game.blend)
	if !check_ui(control_error) {
		return false
	}

	for control in ([3]struct {
			name, label: string,
			value:       ^bool,
		} {
			{"pause", "PAUSED", &game.emitter.paused},
			{"emit", "EMITTING", &game.emitter.emitting},
			{"bloom", "BLOOM", &game.bloom_enabled},
		}) {
		rect, err = ui.next(column, 24)
		if !check_ui(err) {
			return false
		}
		_, control_error = ui.checkbox(
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
			high:        f32,
		} {
			{"rate", "RATE / SECOND", &game.emitter.settings.rate, 4000},
			{"size", "BIRTH SIZE", &game.emitter.settings.size[0], 0.5},
			{"strength", "BLOOM STRENGTH", &game.bloom_strength, 1},
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
			step = control.high / 100,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	for label, i in ([3]string{"EMIT 1200", "RESET SEED 42", "RESET CAMERA"}) {
		rect, err = ui.next(column, 28)
		if !check_ui(err) {
			return false
		}
		clicked, button_error := ui.button(ctx, ui.id(label), rect, label)
		if !check_ui(button_error) {
			return false
		}

		if clicked {
			switch i {
			case 0:
				game.failed = !check_particles(particles.emit(&game.emitter, 1200))
			case 1:
				restart(game)
			case 2:
				game.orbit = INITIAL_ORBIT
			}
		}
	}
	rect, err = ui.next(column, 60)
	return(
		check_ui(err) &&
		check_ui(
			ui.label(ctx, rect, "SPACE: PAUSE\nR: RESET / F1: PANEL\nDRAG: ORBIT\nWHEEL: ZOOM"),
		) \
	)
}

check_ui :: proc(err: ui.Error) -> bool {
	if err != .None {
		log.errorf("UI: %v", err)
	}

	return err == .None
}
