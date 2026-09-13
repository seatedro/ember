package ui

import "../draw2d"
import "../input"
import "core:testing"

@(private)
toolkit_style :: proc(ctx: ^Context, font: ^draw2d.Font) {
	ctx.style = {
		font         = font,
		font_size    = 16,
		padding      = {8, 4},
		border_width = 2,
		thumb_width  = 12,
	}
}

@(test)
test_nested_scroll_and_keyboard_reveal :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	state: input.State
	input.init(&state, true, {40, 40})
	input.record_scroll(&state, {0, -1})
	outer, inner: [2]f32
	testing.expect(t, begin(&ctx, state, {400, 400}, {400, 400}) == .None)
	_, err := begin_scroll(&ctx, id("outer"), {{10, 10}, {200, 200}}, {180, 500}, &outer)
	testing.expect(t, err == .None)
	_, err = begin_scroll(&ctx, id("inner"), {{20, 20}, {100, 100}}, {80, 300}, &inner)
	testing.expect(t, err == .None)
	testing.expect(t, end_scroll(&ctx) == .None && end_scroll(&ctx) == .None)
	testing.expect(t, end(&ctx) == .None)
	testing.expect(t, inner.y == 48 && outer.y == 0 && ctx.capture.mouse)
	inner.y = 200
	testing.expect(t, begin(&ctx, state, {400, 400}, {400, 400}) == .None)
	_, err = begin_scroll(&ctx, id("outer"), {{10, 10}, {200, 200}}, {180, 500}, &outer)
	_, err = begin_scroll(&ctx, id("inner"), {{20, 20}, {100, 100}}, {80, 300}, &inner)
	testing.expect(t, err == .None)
	testing.expect(t, end_scroll(&ctx) == .None && end_scroll(&ctx) == .None)
	testing.expect(t, end(&ctx) == .None)
	testing.expect(t, inner.y == 200 && outer.y == 48)
	input.clear(&state)
	ctx.focus = id("offscreen")
	testing.expect(t, begin(&ctx, state, {400, 400}, {400, 400}) == .None)
	ctx.focus_moved = true
	body, _ := begin_scroll(&ctx, id("outer"), {{10, 10}, {200, 100}}, {180, 500}, &outer)
	_, err = button(&ctx, id("offscreen"), {body.position + [2]f32{0, 400}, {100, 24}}, "BUTTON")
	testing.expect(t, err == .None && outer.y > 300)
	testing.expect(t, end_scroll(&ctx) == .None && end(&ctx) == .None)
}

@(private)
menu_frame :: proc(t: ^testing.T, ctx: ^Context, state: input.State, selected: ^int) -> bool {
	testing.expect(t, begin(ctx, state, {300, 300}, {300, 300}) == .None)
	_, err := dropdown(ctx, id("menu"), {{10, 10}, {180, 24}}, {"ONE", "TWO", "THREE"}, selected)
	testing.expect(t, err == .None)
	clicked, button_error := button(ctx, id("behind"), {{10, 60}, {180, 24}}, "BEHIND")
	testing.expect(t, button_error == .None)
	testing.expect(t, end(ctx) == .None)
	return clicked
}

@(test)
test_dropdown_layering_selection_and_dismissal :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	state: input.State
	input.init(&state, true, {40, 20})
	selected := 0
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	testing.expect(t, !menu_frame(t, &ctx, state, &selected))
	testing.expect(t, ctx.popup == id("menu") && len(ctx.overlays.indices) > 0)
	input.clear(&state)
	input.record_focus(&state, false)
	menu_frame(t, &ctx, state, &selected)
	testing.expect(
		t,
		ctx.popup == id("menu") && ctx.focus == 0 && !ctx.capture.mouse && !ctx.capture.keyboard,
	)
	input.record_focus(&state, true)
	menu_frame(t, &ctx, state, &selected)
	testing.expect(t, ctx.popup == id("menu") && ctx.focus == id("menu"))
	testing.expect(
		t,
		ctx.draws.batches[len(ctx.draws.batches) - 1].first_index >=
		u32(len(ctx.draws.indices) - len(ctx.overlays.indices)),
	)
	input.clear(&state)
	input.record_cursor(&state, {40, 70})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	testing.expect(t, !menu_frame(t, &ctx, state, &selected))
	testing.expect(t, selected == 1 && ctx.popup == 0)
	input.clear(&state)
	input.record_key(&state, .Enter, true)
	menu_frame(t, &ctx, state, &selected)
	input.clear(&state)
	input.record_key(&state, .Enter, false)
	input.record_key(&state, .Down, true)
	menu_frame(t, &ctx, state, &selected)
	testing.expect_value(t, ctx.popup_index, 2)
	input.clear(&state)
	input.record_key(&state, .Down, false)
	input.record_key(&state, .Enter, true)
	menu_frame(t, &ctx, state, &selected)
	testing.expect(t, selected == 2 && ctx.popup == 0)
	input.clear(&state)
	input.record_key(&state, .Enter, false)
	input.record_key(&state, .Down, true)
	menu_frame(t, &ctx, state, &selected)
	input.clear(&state)
	input.record_cursor(&state, {250, 250})
	input.record_mouse_button(&state, .Left, true)
	menu_frame(t, &ctx, state, &selected)
	game := remaining_input(&ctx)
	testing.expect(t, ctx.popup == 0 && !input.mouse_down(&game, .Left))
}

@(private)
edit_frame :: proc(
	t: ^testing.T,
	ctx: ^Context,
	state: input.State,
	text: ^Text_Edit,
) -> Text_Result {
	testing.expect(t, begin(ctx, state, {300, 100}, {300, 100}) == .None)
	result, err := text_field(ctx, id("text"), {{10, 10}, {180, 28}}, text)
	testing.expect(t, err == .None)
	testing.expect(t, end(ctx) == .None)
	return result
}

@(test)
test_text_utf8_selection_repeat_undo_and_capture :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	text, err := create_text_edit("café")
	testing.expect(t, err == .None)
	defer destroy_text_edit(&text)
	state: input.State
	input.init(&state, true, {250, 80})
	defer input.destroy(&state)
	ctx.focus = id("text")
	input.record_key(&state, .Backspace, true)
	testing.expect(t, edit_frame(t, &ctx, state, &text).changed)
	testing.expect_value(t, text_value(&text), "caf")
	input.clear(&state)
	input.record_repeat(&state, .Backspace)
	edit_frame(t, &ctx, state, &text)
	testing.expect_value(t, text_value(&text), "ca")
	input.clear(&state)
	input.record_key(&state, .Backspace, false)
	input.record_text(&state, 'é')
	edit_frame(t, &ctx, state, &text)
	testing.expect_value(t, text_value(&text), "caé")
	game := remaining_input(&ctx)
	testing.expect_value(t, len(game.text), 0)
	input.clear(&state)
	shortcut: input.Key = .Left_Control
	when ODIN_OS == .Darwin {
		shortcut = .Left_Super
	}
	input.record_key(&state, shortcut, true)
	input.record_key(&state, .A, true)
	input.record_key(&state, .A, false)
	input.record_key(&state, shortcut, false)
	edit_frame(t, &ctx, state, &text)
	input.clear(&state)
	input.record_key(&state, shortcut, false)
	input.record_key(&state, .A, false)
	input.record_text(&state, 'λ')
	edit_frame(t, &ctx, state, &text)
	testing.expect_value(t, text_value(&text), "λ")
	input.clear(&state)
	input.record_key(&state, shortcut, true)
	input.record_key(&state, .Z, true)
	edit_frame(t, &ctx, state, &text)
	testing.expect_value(t, text_value(&text), "café")
	input.clear(&state)
	input.record_key(&state, shortcut, false)
	input.record_key(&state, .Z, false)
	input.record_key(&state, .Enter, true)
	testing.expect(t, edit_frame(t, &ctx, state, &text).submitted && ctx.focus == 0)
	game = remaining_input(&ctx)
	testing.expect(t, !input.pressed(&game, .Enter))
	testing.expect(t, set_text(&text, "new\ntext") == .None)
	testing.expect_value(t, text_value(&text), "newtext")
}

@(test)
test_tabs_move_once_and_tooltips_draw_last :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	state: input.State
	input.init(&state, true, {250, 80})
	selected := 0
	ctx.focus = index_id(id("tabs"), 0)
	input.record_key(&state, .Right, true)
	testing.expect(t, begin(&ctx, state, {300, 100}, {300, 100}) == .None)
	changed, err := tabs(
		&ctx,
		id("tabs"),
		{{10, 10}, {240, 24}},
		{"ONE", "TWO", "THREE"},
		&selected,
	)
	testing.expect(t, err == .None && changed && selected == 1)
	testing.expect(t, end(&ctx) == .None)
	input.clear(&state)
	input.record_cursor(&state, {20, 20})
	testing.expect(t, begin(&ctx, state, {300, 100}, {300, 100}) == .None)
	_, err = button(&ctx, id("hint"), {{10, 10}, {100, 24}}, "HINT")
	testing.expect(t, err == .None)
	testing.expect(t, tooltip(&ctx, id("hint"), "HELP", delay = 0) == .None)
	testing.expect(t, len(ctx.overlays.indices) > 0)
	testing.expect(t, end(&ctx) == .None)
}
