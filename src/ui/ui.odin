package ui

import "../draw2d"
import "../input"
import "core:time"

ID :: distinct u64

Error :: enum {
	None,
	Invalid_Frame,
	Invalid_ID,
	Duplicate_ID,
	Invalid_Layout,
	Layout_Overflow,
	Allocation_Failed,
	Invalid_Style,
	Invalid_Value,
	Draw_Failed,
}

Interaction :: struct {
	hovered, held, focused, clicked: bool,
}

Capture :: struct {
	mouse, keyboard: bool,
}

Context :: struct {
	docking_enabled:                                          bool,
	restored_order:                                           [dynamic]ID,
	dock_nodes:                                               [dynamic]Dock_Node,
	dock_root:                                                u32,
	dock_drag:                                                Dock_Drag,
	dock_target:                                              Dock_Target,
	cursor:                                                   input.Cursor,
	windows:                                                  map[ID]Window_Record,
	window_order:                                             [dynamic]ID,
	current_window, hover_window, focus_window, popup_window: ID,
	window_drag:                                              Window_Drag,
	overlays:                                                 draw2d.List,
	popup:                                                    ID,
	popup_bounds, popup_anchor:                               Rect,
	popup_index:                                              int,
	popup_offset:                                             f32,
	popup_seen, in_overlay, mouse_blocked:                    bool,
	last_hot:                                                 ID,
	hover_since:                                              time.Tick,
	clipboard:                                                input.Clipboard,
	style:                                                    Style,
	draws:                                                    draw2d.List,
	hot, active, focus:                                       ID,
	capture:                                                  Capture,
	raw_input:                                                input.State,
	pointer, press_pointer:                                   [2]f64,
	mouse_owned:                                              [input.Mouse_Button]bool,
	key_owned:                                                [input.Key]bool,
	previous_order, order:                                    [dynamic]ID,
	seen:                                                     map[ID]bool,
	frame_active:                                             bool,
	pointer_over:                                             bool,
	navigation_used:                                          bool,
	focus_first:                                              bool,
	scrolls:                                                  [dynamic]Scroll_Frame,
	wheel_consumed:                                           bool,
	focus_moved:                                              bool,
}

create :: proc(allocator := context.allocator) -> Context {
	return {
		windows = make(map[ID]Window_Record, allocator),
		dock_nodes = make([dynamic]Dock_Node, allocator),
		restored_order = make([dynamic]ID, allocator),
		window_order = make([dynamic]ID, allocator),
		draws = draw2d.create_list(allocator),
		overlays = draw2d.create_list(allocator),
		previous_order = make([dynamic]ID, allocator),
		order = make([dynamic]ID, allocator),
		seen = make(map[ID]bool, allocator),
		scrolls = make([dynamic]Scroll_Frame, allocator),
	}
}

id :: proc(name: string, parent: ID = 0) -> ID {
	hash := u64(14695981039346656037) ~ u64(parent)
	for byte in transmute([]u8)name {
		hash = (hash ~ u64(byte)) * 1099511628211
	}

	return ID(hash) if hash != 0 else ID(1)
}

begin :: proc(
	ctx: ^Context,
	state: input.State,
	size, input_size: [2]f32,
	windows: []^Window = nil,
) -> Error {
	if ctx.frame_active ||
	   !valid_rect({size = size}) ||
	   !valid_rect({size = input_size}) ||
	   size.x <= 0 ||
	   size.y <= 0 ||
	   input_size.x <= 0 ||
	   input_size.y <= 0 {
		return .Invalid_Frame
	}

	if state.text_failed {
		return .Allocation_Failed
	}

	if draw2d.reset(&ctx.draws, size) != .None || draw2d.reset(&ctx.overlays, size) != .None {
		return .Allocation_Failed
	}

	clear(&ctx.scrolls)
	ctx.wheel_consumed = false
	ctx.focus_moved = false
	clear(&ctx.order)
	clear(&ctx.seen)
	ctx.raw_input = state
	ctx.pointer =
		state.mouse_position *
		[2]f64{f64(size.x) / f64(input_size.x), f64(size.y) / f64(input_size.y)}
	ctx.press_pointer =
		state.mouse_press_position[.Left] *
		[2]f64{f64(size.x) / f64(input_size.x), f64(size.y) / f64(input_size.y)}
	ctx.cursor = .Arrow
	ctx.hot = 0
	ctx.pointer_over = false
	ctx.navigation_used = false
	ctx.focus_first = false
	ctx.capture = {}
	ctx.popup_seen = false
	ctx.mouse_blocked = false
	if err := prepare_windows(ctx, windows); err != .None {
		return err
	}
	ctx.frame_active = true

	if !state.focused {
		ctx.active, ctx.focus = 0, 0
		ctx.window_drag = {}
		ctx.dock_drag = {}
		ctx.dock_target = {}
		ctx.hover_window = 0
		ctx.mouse_owned = {}
		ctx.key_owned = {}
		return .None
	}

	for button, key in state.keys {
		if !button.down && !button.released && !button.pressed {
			ctx.key_owned[key] = false
		}
	}

	for button, key in state.mouse_buttons {
		if !button.down && !button.released && !button.pressed {
			ctx.mouse_owned[key] = false
		}
	}

	if input.mouse_pressed(&ctx.raw_input, .Left) {
		ctx.focus = 0
		if ctx.popup != 0 &&
		   !contains(ctx.popup_bounds, ctx.pointer) &&
		   !contains(ctx.popup_anchor, ctx.pointer) {
			ctx.popup = 0
			ctx.mouse_blocked = true
			ctx.pointer_over = true
		}
	}

	update_window_input(ctx)

	if input.pressed(&ctx.raw_input, .Escape) && ctx.popup != 0 {
		ctx.popup = 0
		ctx.navigation_used = true
	} else if input.pressed(&ctx.raw_input, .Escape) && ctx.focus != 0 {
		ctx.focus = 0
		ctx.navigation_used = true
	}

	if key_action(ctx, .Tab) {
		ctx.popup = 0
		ctx.focus_moved = true
		ctx.navigation_used = len(ctx.previous_order) > 0
		ctx.focus_first = len(ctx.previous_order) == 0
		if len(ctx.previous_order) > 0 {
			index := -1
			for previous, i in ctx.previous_order {
				if previous == ctx.focus {
					index = i
					break
				}
			}

			reverse := .Shift in input.key_modifiers(&ctx.raw_input, .Tab)
			if reverse {
				index = len(ctx.previous_order) if index < 0 else index
				index = (index + len(ctx.previous_order) - 1) % len(ctx.previous_order)
			} else {
				index = (index + 1) % len(ctx.previous_order)
			}

			ctx.focus = ctx.previous_order[index]
		}
	}

	return .None
}

region :: proc(ctx: ^Context, rect: Rect) -> Error {
	if !ctx.frame_active || !valid_rect(rect) || len(ctx.draws.clips) == 0 {
		return .Invalid_Frame
	}

	if pointer_inside(ctx, rect) {
		ctx.pointer_over = true
	}

	return .None
}

interact :: proc(ctx: ^Context, widget: ID, rect: Rect, enabled := true) -> (Interaction, Error) {
	if !ctx.frame_active || !valid_rect(rect) || len(ctx.draws.clips) == 0 {
		return {}, .Invalid_Frame
	}

	if widget == 0 {
		return {}, .Invalid_ID
	}

	if _, exists := ctx.seen[widget]; exists {
		return {}, .Duplicate_ID
	}

	ctx.seen[widget] = enabled
	if !enabled {
		return {}, .None
	}

	keyboard_window := ctx.current_window == ctx.focus_window
	if keyboard_window {
		if _, err := append(&ctx.order, widget); err != nil {
			return {}, .Allocation_Failed
		}
	}

	if !ctx.raw_input.focused ||
	   ctx.window_drag.window != 0 ||
	   ctx.mouse_blocked ||
	   (ctx.popup != 0 && ctx.popup != widget && !ctx.in_overlay) {
		return {}, .None
	}

	if ctx.focus_first && keyboard_window {
		ctx.focus = widget
		ctx.focus_first = false
		ctx.navigation_used = true
	}

	inside := pointer_inside(ctx, rect)
	ctx.pointer_over = ctx.pointer_over || inside
	if inside && ctx.hot == 0 && (ctx.active == 0 || ctx.active == widget) {
		ctx.hot = widget
	}

	hovered := ctx.hot == widget
	if hovered && input.mouse_pressed(&ctx.raw_input, .Left) && ctx.active == 0 {
		ctx.active = widget
		ctx.focus = widget
		ctx.mouse_owned[.Left] = true
	}

	clicked := false
	held := ctx.active == widget && input.mouse_down(&ctx.raw_input, .Left)
	if ctx.active == widget && input.mouse_released(&ctx.raw_input, .Left) {
		clicked = hovered
		ctx.active = 0
	}

	focused := ctx.focus == widget && keyboard_window
	if focused && ctx.focus_moved {
		reveal_focused(ctx, rect)
	}
	if focused &&
	   (input.pressed(&ctx.raw_input, .Enter) || input.pressed(&ctx.raw_input, .Space)) {
		clicked = true
	}

	return {hovered = hovered, held = held, focused = focused, clicked = clicked}, .None
}

end :: proc(ctx: ^Context) -> Error {
	if !ctx.frame_active {
		return .Invalid_Frame
	}

	if ctx.in_overlay || ctx.current_window != 0 {
		return .Invalid_Frame
	}

	if ctx.popup != 0 && !ctx.popup_seen {
		if ctx.focus == ctx.popup {
			ctx.focus = 0
		}
		ctx.popup = 0
	}

	if ctx.hot != ctx.last_hot {
		ctx.hover_since = time.tick_now()
		ctx.last_hot = ctx.hot
	}

	ctx.frame_active = false
	if !ctx.seen[ctx.active] ||
	   (!input.mouse_down(&ctx.raw_input, .Left) && !input.mouse_pressed(&ctx.raw_input, .Left)) {
		ctx.active = 0
	}

	if !ctx.seen[ctx.focus] {
		ctx.focus = 0
	}

	unowned_drag := false
	for button, key in ctx.raw_input.mouse_buttons {
		if button.pressed {
			ctx.mouse_owned[key] = ctx.pointer_over
		}

		if button.down || button.released || button.pressed {
			ctx.capture.mouse = ctx.capture.mouse || ctx.mouse_owned[key]
			unowned_drag = unowned_drag || !ctx.mouse_owned[key]
		}
	}

	ctx.capture.mouse =
		ctx.raw_input.focused && (ctx.capture.mouse || (ctx.pointer_over && !unowned_drag))
	ctx.capture.keyboard = ctx.raw_input.focused && (ctx.focus != 0 || ctx.navigation_used)
	for button, key in ctx.raw_input.keys {
		if button.pressed {
			ctx.key_owned[key] = ctx.capture.keyboard
		}
	}

	ctx.previous_order, ctx.order = ctx.order, ctx.previous_order
	if len(ctx.draws.clips) != 1 || len(ctx.scrolls) != 0 {
		return .Invalid_Frame
	}

	if err := compose_docks(ctx, ctx.dock_root); err != .None {
		return err
	}
	if err := compose_windows(ctx); err != .None {
		return err
	}

	if err := draw_dock_preview(ctx); err != .None {
		return err
	}
	return draw_error(draw2d.append_list(&ctx.draws, &ctx.overlays))
}

remaining_input :: proc(ctx: ^Context) -> input.State {
	state := ctx.raw_input
	if ctx.capture.mouse {
		state.mouse_buttons = {}
		state.mouse_delta = {}
		state.scroll_delta = {}
	} else {
		for owned, key in ctx.mouse_owned {
			if owned {
				state.mouse_buttons[key] = {}
			}
		}
	}

	if ctx.capture.keyboard {
		state.keys = {}
		state.text = {}
		state.text_failed = false
	} else {
		for owned, key in ctx.key_owned {
			if owned {
				state.keys[key] = {}
			}
		}
	}

	return state
}

destroy :: proc(ctx: ^Context) {
	for _, record in ctx.windows {
		delete(record.title, ctx.window_order.allocator)
		list := record.draws
		draw2d.destroy_list(&list)
	}
	for node in ctx.dock_nodes {
		delete(node.windows)
	}
	delete(ctx.dock_nodes)
	delete(ctx.restored_order)
	delete(ctx.windows)
	delete(ctx.window_order)
	draw2d.destroy_list(&ctx.draws)
	draw2d.destroy_list(&ctx.overlays)
	delete(ctx.order)
	delete(ctx.previous_order)
	delete(ctx.seen)
	delete(ctx.scrolls)
	ctx^ = {}
}

@(private)
pointer_inside :: proc(ctx: ^Context, rect: Rect) -> bool {
	return(
		(ctx.in_overlay || ctx.current_window == ctx.hover_window) &&
		ctx.raw_input.focused &&
		ctx.raw_input.mouse_position_valid &&
		contains(rect, ctx.pointer) &&
		contains(ctx.draws.clips[len(ctx.draws.clips) - 1], ctx.pointer) \
	)
}

@(private)
key_action :: proc(ctx: ^Context, key: input.Key) -> bool {
	return input.pressed(&ctx.raw_input, key) || ctx.raw_input.keys[key].repeated
}
