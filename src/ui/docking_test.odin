package ui

import "../input"
import "core:encoding/json"
import "core:testing"

@(test)
test_docking_drag_split_group_and_restore :: proc(t: ^testing.T) {
	font := control_test_font()
	defer delete(font.glyphs)
	ctx := create()
	defer destroy(&ctx)
	toolkit_style(&ctx, &font)
	ctx.docking_enabled = true
	a := Window {
		id     = id("a"),
		bounds = {{300, 80}, {240, 200}},
		open   = true,
	}
	b := Window {
		id     = id("b"),
		bounds = {{400, 300}, {240, 200}},
		open   = true,
	}
	windows := [2]^Window{&a, &b}
	state: input.State
	input.init(&state, true, {700, 580})
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, dock_window(&ctx, &a, side = .Left) == .None)
	initial := a.bounds.size.x
	split := dock_divider(&ctx, dock_node(&ctx, ctx.dock_root))
	input.record_cursor(&state, {f64(split.position.x + 2), 540})
	input.record_mouse_button(&state, .Left, true)
	input.record_cursor(&state, {350, 540})
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, a.bounds.size.x > initial && a.bounds.size.x == 350 && ctx.capture.mouse)
	testing.expect(t, dock_window(&ctx, &b, a.id) == .None)
	testing.expect(t, a.dock_node == b.dock_node && dock_node(&ctx, a.dock_node).active == b.id)
	input.clear(&state)
	window_frame(t, &ctx, state, windows[:])
	data, err := encode_layout(&ctx)
	defer delete(data)
	testing.expect(t, err == .None)
	bounds := a.bounds
	testing.expect(t, reset_layout(&ctx, windows[:]) == .None)
	testing.expect(t, decode_layout(&ctx, data, windows[:]) == .None)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, a.bounds == bounds && a.dock_node == b.dock_node)
	testing.expect_value(t, dock_node(&ctx, b.dock_node).active, b.id)
	tab := dock_tab_rect(&ctx, dock_node(&ctx, b.dock_node), 1)
	input.record_cursor(&state, {f64(tab.position.x + tab.size.x * 0.5), 10})
	input.record_mouse_button(&state, .Left, true)
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_key(&state, .Left_Control, true)
	input.record_key(&state, .Page_Up, true)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, dock_node(&ctx, a.dock_node).active, a.id)
	testing.expect(t, ctx.capture.keyboard)
	input.clear(&state)
	input.record_key(&state, .Page_Up, false)
	input.record_key(&state, .Page_Down, true)
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, dock_node(&ctx, b.dock_node).active, b.id)
	input.clear(&state)
	input.record_key(&state, .Page_Down, false)
	input.record_key(&state, .Left_Control, false)

	input.record_cursor(&state, {8, 20})
	input.record_mouse_button(&state, .Left, true)
	input.record_cursor(&state, {430, 250})
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, dock_root(&ctx, a.dock_node) != ctx.dock_root && a.dock_node == b.dock_node)
	testing.expect_value(t, a.bounds, b.bounds)
	input.clear(&state)
	point := a.bounds.position + a.bounds.size
	input.record_cursor(&state, {f64(point.x), f64(point.y)})
	input.record_mouse_button(&state, .Left, true)
	input.record_cursor(&state, {f64(point.x - 70), f64(point.y - 80)})
	input.record_mouse_button(&state, .Left, false)
	old := a.bounds.size
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, a.bounds.size.x < old.x && a.bounds == b.bounds)
	node := dock_node(&ctx, a.dock_node)
	active_tab := dock_tab_rect(&ctx, node, 1)
	input.clear(&state)
	input.record_cursor(
		&state,
		{f64(active_tab.position.x + active_tab.size.x * 0.5), f64(active_tab.position.y + 10)},
	)
	input.record_mouse_button(&state, .Left, true)
	window_frame(t, &ctx, state, windows[:])
	input.clear(&state)
	input.record_cursor(&state, {100, 400})
	input.record_mouse_button(&state, .Left, false)
	window_frame(t, &ctx, state, windows[:])
	testing.expect(t, b.dock_node == 0 && a.dock_node != 0)
	testing.expect_value(t, dock_node(&ctx, a.dock_node).active, a.id)
	testing.expect(t, ctx.windows[a.id].submitted)
	testing.expect(t, dock_window(&ctx, &b, a.id) == .None)
	undock_window(&ctx, &a)
	testing.expect(t, a.dock_node == 0 && b.dock_node != 0)
	b.open = false
	window_frame(t, &ctx, state, windows[:])
	b.open = true
	window_frame(t, &ctx, state, windows[:])
	testing.expect_value(t, dock_node(&ctx, b.dock_node).active, b.id)
	testing.expect(t, decode_layout(&ctx, data, windows[:1]) == .None)
	input.clear(&state)
	window_frame(t, &ctx, state, windows[:1])
	testing.expect_value(t, dock_node(&ctx, a.dock_node).active, a.id)
	reduced, reduced_error := encode_layout(&ctx)
	defer delete(reduced)
	testing.expect(t, reduced_error == .None && decode_layout(&ctx, reduced, windows[:1]) == .None)
}

@(test)
test_layout_rejects_cycles_without_changing_windows :: proc(t: ^testing.T) {
	ctx := create()
	defer destroy(&ctx)
	window := Window {
		id     = id("window"),
		bounds = {{10, 20}, {300, 200}},
		open   = true,
	}
	original := window
	windows := [1]^Window{&window}
	nodes := [4]Dock_Node {
		{alive = true, parent = 2, children = {2, 3}, ratio = 0.5},
		{alive = true, parent = 1, children = {1, 4}, ratio = 0.5},
		{alive = true, parent = 1, ratio = 0.5},
		{alive = true, parent = 2, ratio = 0.5},
	}
	data, err := json.marshal(Saved_Layout{version = 1, root = 1, nodes = nodes[:]})
	defer delete(data)
	testing.expect(t, err == nil)
	testing.expect(t, decode_layout(&ctx, data, windows[:]) == .Invalid_Layout)
	testing.expect_value(t, window, original)
	testing.expect_value(t, len(ctx.dock_nodes), 0)
}
