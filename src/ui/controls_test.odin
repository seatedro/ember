package ui

import "../draw2d"
import "../input"
import "core:testing"

@(private)
control_test_font :: proc() -> draw2d.Font {
	font := draw2d.Font {
		texture = {generation = 1},
		em_size = 1,
		line_height = 1,
	}
	font.glyphs = make(map[rune]draw2d.Glyph)
	font.glyphs['?'] = {
		advance = 1,
	}
	return font
}

@(private)
slider_frame :: proc(
	t: ^testing.T,
	ctx: ^Context,
	state: input.State,
	value: ^f32,
	enabled := true,
) -> bool {
	testing.expect(t, begin(ctx, state, {200, 100}, {400, 200}) == .None)
	changed, err := slider(
		ctx,
		id("slider"),
		{{20, 20}, {100, 24}},
		"VALUE",
		value,
		0,
		4,
		step = 0.25,
		enabled = enabled,
	)
	testing.expect(t, err == .None)
	testing.expect(t, end(ctx) == .None)
	return changed
}

@(test)
test_slider_drag_keyboard_and_disabled :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	ctx.style = {
		font         = &font,
		font_size    = 16,
		padding      = {8, 4},
		border_width = 2,
		thumb_width  = 8,
	}
	state: input.State
	input.init(&state, true, {140, 76})
	value: f32 = 1
	input.record_mouse_button(&state, .Left, true)
	testing.expect(t, slider_frame(t, &ctx, state, &value))
	testing.expect_value(t, value, f32(2))
	input.clear(&state)
	input.record_cursor(&state, {390, 180})
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(4))
	game := remaining_input(&ctx)
	testing.expect(t, !input.mouse_down(&game, .Left))
	input.clear(&state)
	input.record_cursor(&state, {0, 180})
	input.record_mouse_button(&state, .Left, false)
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(0))
	testing.expect(t, ctx.capture.mouse && ctx.active == 0)
	input.clear(&state)
	input.record_key(&state, .Right, true)
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(0.25))
	game = remaining_input(&ctx)
	testing.expect(t, !input.pressed(&game, .Right))
	input.clear(&state)
	testing.expect(t, !slider_frame(t, &ctx, state, &value))
	input.record_key(&state, .End, true)
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(4))
	input.clear(&state)
	input.record_key(&state, .Home, true)
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(0))
	input.clear(&state)
	input.record_cursor(&state, {140, 76})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	slider_frame(t, &ctx, state, &value)
	testing.expect_value(t, value, f32(2))
	input.clear(&state)
	input.record_cursor(&state, {230, 76})
	input.record_mouse_button(&state, .Left, true)
	testing.expect(t, !slider_frame(t, &ctx, state, &value, enabled = false))
	testing.expect_value(t, value, f32(2))
	testing.expect(t, ctx.focus == 0 && ctx.active == 0)
}

@(test)
test_checkbox_label_and_control_errors :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	ctx.style = {
		font         = &font,
		font_size    = 16,
		padding      = {8, 4},
		border_width = 2,
		thumb_width  = 8,
	}
	state: input.State
	input.init(&state, true, {90, 30})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	testing.expect(t, begin(&ctx, state, {200, 100}, {200, 100}) == .None)
	checked := false
	changed, err := checkbox(&ctx, id("check"), {{20, 20}, {100, 24}}, "LABEL", &checked)
	testing.expect(t, err == .None && changed && checked)
	testing.expect(t, end(&ctx) == .None)
	input.clear(&state)
	input.record_key(&state, .Space, true)
	testing.expect(t, begin(&ctx, state, {200, 100}, {200, 100}) == .None)
	changed, err = checkbox(&ctx, id("check"), {{20, 20}, {100, 24}}, "LABEL", &checked)
	testing.expect(t, err == .None && changed && !checked)
	value: f32 = 1
	_, err = slider(&ctx, id("invalid"), {{0, 0}, {10, 10}}, "", &value, 1, 1)
	testing.expect(t, err == .Invalid_Value && value == 1)
	_, err = checkbox(&ctx, id("nil"), {{0, 0}, {10, 10}}, "", nil)
	testing.expect(t, err == .Invalid_Value)
	_, err = button(&ctx, id("missing-glyph"), {{0, 0}, {10, 10}}, "x")
	testing.expect(t, err == .None)
	delete_key(&font.glyphs, '?')
	_, err = button(&ctx, id("failed-text"), {{0, 0}, {10, 10}}, "x")
	testing.expect(t, err == .Draw_Failed)
	testing.expect_value(t, len(ctx.draws.clips), 1)
	ctx.style.font = nil
	_, err = button(&ctx, id("invalid-style"), {{0, 0}, {10, 10}}, "")
	testing.expect(t, err == .Invalid_Style)
	testing.expect(t, end(&ctx) == .None)
}

@(private)
panel_frame :: proc(
	t: ^testing.T,
	ctx: ^Context,
	state: input.State,
	expanded, checked: ^bool,
) -> Rect {
	testing.expect(t, begin(ctx, state, {200, 150}, {200, 150}) == .None)
	body, err := collapsible_panel(ctx, id("panel"), {{10, 10}, {180, 120}}, "FPS 60", expanded)
	testing.expect(t, err == .None)
	if expanded^ {
		_, checkbox_error := checkbox(
			ctx,
			id("child"),
			{body.position, {body.size.x, 24}},
			"CHILD",
			checked,
		)
		testing.expect(t, checkbox_error == .None)
	}

	testing.expect(t, end(ctx) == .None)
	return body
}

@(test)
test_collapsed_panel_input_and_focus :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	ctx.style = {
		font         = &font,
		font_size    = 16,
		padding      = {8, 4},
		border_width = 2,
		thumb_width  = 8,
	}
	state: input.State
	input.init(&state, true, {150, 100})
	expanded, checked := true, true
	body := panel_frame(t, &ctx, state, &expanded, &checked)
	testing.expect(t, body.size.y > 0 && ctx.capture.mouse && len(ctx.previous_order) == 2)
	input.record_cursor(&state, {30, 20})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	body = panel_frame(t, &ctx, state, &expanded, &checked)
	testing.expect(t, !expanded && checked && ctx.capture.mouse)
	testing.expect_value(t, body, Rect{})
	testing.expect_value(t, len(ctx.previous_order), 1)
	input.clear(&state)
	input.record_cursor(&state, {150, 100})
	input.record_mouse_button(&state, .Left, true)
	panel_frame(t, &ctx, state, &expanded, &checked)
	game := remaining_input(&ctx)
	testing.expect(t, !ctx.capture.mouse && input.mouse_down(&game, .Left))
	input.clear(&state)
	input.record_mouse_button(&state, .Left, false)
	panel_frame(t, &ctx, state, &expanded, &checked)
	input.clear(&state)
	input.record_key(&state, .Tab, true)
	panel_frame(t, &ctx, state, &expanded, &checked)
	testing.expect_value(t, ctx.focus, id("panel"))
	input.clear(&state)
	input.record_key(&state, .Tab, false)
	input.record_key(&state, .Enter, true)
	panel_frame(t, &ctx, state, &expanded, &checked)
	testing.expect(t, expanded && checked && len(ctx.previous_order) == 2)
	input.clear(&state)
	input.record_key(&state, .Enter, false)
	input.record_key(&state, .Tab, true)
	panel_frame(t, &ctx, state, &expanded, &checked)
	testing.expect_value(t, ctx.focus, id("child"))
}
