package ui

import "../draw2d"
import "../input"
import "core:testing"

@(private)
window_frame :: proc(
	t: ^testing.T,
	ctx: ^Context,
	state: input.State,
	windows: []^Window,
) -> [2]bool {
	testing.expect(t, begin(ctx, state, {800, 600}, {800, 600}, windows) == .None)
	clicked: [2]bool
	for i := len(windows) - 1; i >= 0; i -= 1 {
		window := windows[i]
		body, visible, err := begin_window(ctx, window, "WINDOW")
		testing.expect(t, err == .None)
		if visible {
			clicked[i], err = button(
				ctx,
				id("child", window.id),
				{body.position, {body.size.x, 24}},
				"CHILD",
			)
			testing.expect(t, err == .None)
			testing.expect(
				t,
				draw2d.rectangle(&ctx.draws, {body.position, {1, 1}}, {f32(i), 0, 0, 1}) == .None,
			)
			testing.expect(t, end_window(ctx) == .None)
		}
	}

	testing.expect(t, end(ctx) == .None)
	return clicked
}

@(test)
test_window_overlap_stacking_and_focus :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	a := Window {
		id     = id("a"),
		bounds = {{10, 10}, {200, 200}},
		open   = true,
	}
	b := Window {
		id     = id("b"),
		bounds = {{60, 10}, {200, 200}},
		open   = true,
	}
	windows := [2]^Window{&a, &b}
	state: input.State
	input.init(&state, true, {90, 60})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	clicked := window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !clicked[0] && clicked[1] && ctx.capture.mouse)
	testing.expect_value(t, ctx.draws.vertices[len(ctx.draws.vertices) - 1].color.x, f32(1))
	testing.expect_value(t, ctx.focus, id("child", b.id))

	input.clear(&state)
	input.record_cursor(&state, {30, 100})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, ctx.draws.vertices[len(ctx.draws.vertices) - 1].color.x, f32(0))
	testing.expect_value(t, ctx.focus_window, a.id)
	input.clear(&state)
	input.record_key(&state, .Tab, true)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, ctx.focus, id("collapse", a.id))
	testing.expect_value(t, len(ctx.previous_order), 3)

	input.clear(&state)
	input.record_key(&state, .Tab, false)
	input.record_cursor(&state, {190, 24})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	clicked = window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !a.open && b.open && !clicked[1] && ctx.capture.mouse)
	input.clear(&state)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, ctx.focus_window, b.id)
	testing.expect(t, ctx.focus == 0)
}

@(test)
test_window_drag_resize_and_focus_loss :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	window := Window {
		id           = id("window"),
		bounds       = {{10, 10}, {200, 200}},
		minimum_size = {180, 120},
		open         = true,
	}
	windows := [1]^Window{&window}
	state: input.State
	input.init(&state, true, {100, 24})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {300, 124})
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds.position, [2]f32{210, 110})
	testing.expect_value(t, window.bounds.size, [2]f32{200, 200})
	testing.expect(t, ctx.capture.mouse)
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, ctx.capture.mouse && ctx.window_drag.window == 0)

	input.clear(&state)
	input.record_cursor(&state, {410, 310})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {220, 120})
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds, Rect{{210, 110}, {180, 120}})

	input.clear(&state)
	input.record_cursor(&state, {210, 170})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {150, 170})
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds, Rect{{150, 110}, {240, 120}})
	input.record_cursor(&state, {500, 170})
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds, Rect{{210, 110}, {180, 120}})
	input.clear(&state)
	input.record_focus(&state, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, ctx.window_drag.window == 0 && !ctx.capture.mouse)
	input.record_focus(&state, true)
	input.record_cursor(&state, {0, 0})
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds, Rect{{210, 110}, {180, 120}})

	input.clear(&state)
	input.record_cursor(&state, {280, 124})
	input.record_mouse_button(&state, .Left, true)
	input.record_cursor(&state, {380, 224})
	input.record_mouse_button(&state, .Left, false)
	clicked := window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, window.bounds, Rect{{310, 210}, {180, 120}})
	testing.expect(t, !clicked[0] && ctx.capture.mouse && ctx.window_drag.window == 0)

}

@(test)
test_window_collapse_reopen_and_removal :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	window := Window {
		id     = id("window"),
		bounds = {{10, 10}, {200, 200}},
		open   = true,
	}
	windows := [1]^Window{&window}
	state: input.State
	input.init(&state, true, {26, 24})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, window.collapsed && window.bounds.size.y == 200)
	input.clear(&state)
	input.record_cursor(&state, {90, 60})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !ctx.capture.mouse)
	input.clear(&state)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, ctx.focus_window, ID(0))

	input.clear(&state)
	input.record_mouse_button(&state, .Left, false)
	window.open = false
	window_frame(t, &ctx, state, windows[:])
	window.open = true
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, window.collapsed && window.bounds == Rect{{10, 10}, {200, 200}})
	window_frame(t, &ctx, state, nil)
	testing.expect(t, len(ctx.windows) == 0 && len(ctx.window_order) == 0)
	testing.expect_value(t, ctx.focus_window, ID(0))
}

@(test)
test_control_drag_owns_controls_and_moves_tab_groups :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	ctx.docking_enabled = true
	a := Window {
		id     = id("a"),
		bounds = {{100, 100}, {240, 200}},
		open   = true,
	}
	b := Window {
		id     = id("b"),
		bounds = {{500, 300}, {240, 200}},
		open   = true,
	}
	windows := [2]^Window{&a, &b}
	state: input.State
	input.init(&state, true, {130, 145})
	input.record_key(&state, .Left_Control, true)
	input.record_mouse_button(&state, .Left, true)
	clicked := window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !clicked[0] && ctx.active == 0 && ctx.capture.mouse)
	input.clear(&state)
	input.record_key(&state, .Left_Control, false)
	input.record_cursor(&state, {230, 245})
	input.record_mouse_button(&state, .Left, false)
	clicked = window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !clicked[0] && ctx.capture.mouse)
	testing.expect_value(t, a.bounds, Rect{{200, 200}, {240, 200}})

	input.clear(&state)
	input.record_key(&state, .Right_Control, true)
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	clicked = window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !clicked[0] && ctx.active == 0)
	testing.expect(t, dock_window(&ctx, &b, a.id) == .None)
	input.clear(&state)
	input.record_cursor(&state, {200, 300})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {240, 340})
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, a.bounds, Rect{{240, 240}, {240, 200}})
	testing.expect_value(t, a.bounds, b.bounds)
	testing.expect(t, a.dock_node == b.dock_node && dock_node(&ctx, a.dock_node).active == b.id)

	testing.expect(t, dock_window(&ctx, &a, side = .Left) == .None)
	testing.expect(t, dock_window(&ctx, &b, a.id) == .None)
	b.open = false
	input.clear(&state)
	input.record_cursor(&state, {40, 45})
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {500, 200})
	input.record_mouse_button(&state, .Left, false)
	clicked = window_frame(t, &ctx, state, windows[:])
	testing.expect(t, !clicked[0] && ctx.capture.mouse && !layout_busy(&ctx))
	testing.expect(t, a.dock_node == b.dock_node && dock_root(&ctx, a.dock_node) != ctx.dock_root)
	testing.expect_value(t, a.bounds.position, [2]f32{460, 155})
	testing.expect(t, !b.open && dock_node(&ctx, a.dock_node).active == a.id)
}
