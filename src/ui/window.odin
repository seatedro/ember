package ui

import "../draw2d"
import "../input"

Window :: struct {
	id:              ID,
	bounds:          Rect,
	minimum_size:    [2]f32,
	open, collapsed: bool,
}

@(private)
Window_Record :: struct {
	state:     ^Window,
	draws:     draw2d.List,
	submitted: bool,
}

@(private)
Window_Edge :: enum {
	Left,
	Right,
	Top,
	Bottom,
}

@(private)
Window_Edges :: bit_set[Window_Edge;u8]

@(private)
Window_Drag :: struct {
	window:  ID,
	bounds:  Rect,
	pointer: [2]f64,
	edges:   Window_Edges,
}

begin_window :: proc(ctx: ^Context, window: ^Window, title: string) -> (Rect, bool, Error) {
	if !ctx.frame_active ||
	   ctx.current_window != 0 ||
	   ctx.in_overlay ||
	   len(ctx.scrolls) != 0 ||
	   len(ctx.draws.clips) != 1 {
		return {}, false, .Invalid_Frame
	}

	if window == nil || window.id == 0 {
		return {}, false, .Invalid_ID
	}

	record, registered := ctx.windows[window.id]
	if !registered || record.state != window || record.submitted {
		return {}, false, .Invalid_Frame
	}

	if !window.open {
		return {}, false, .None
	}

	if _, exists := ctx.seen[window.id]; exists {
		return {}, false, .Duplicate_ID
	}
	ctx.seen[window.id] = true
	ctx.current_window = window.id
	ctx.draws, record.draws = record.draws, ctx.draws
	ctx.windows[window.id] = record
	body_open := false
	defer {
		if !body_open {
			finish_window(ctx)
		}
	}

	header_height := window_header_height(ctx)
	button_width := ctx.style.font_size + ctx.style.padding.x * 2 + ctx.style.border_width * 2
	header := Rect{window.bounds.position, {window.bounds.size.x, header_height}}
	collapse_rect := Rect{header.position, {button_width, header_height}}
	close_rect := Rect {
		header.position + [2]f32{header.size.x - button_width, 0},
		{button_width, header_height},
	}
	collapse, err := interact(ctx, id("collapse", window.id), collapse_rect)
	if err != .None {
		return {}, false, err
	}

	close, close_error := interact(ctx, id("close", window.id), close_rect)
	if close_error != .None {
		return {}, false, close_error
	}

	if close.clicked {
		window.open = false
		return {}, false, .None
	}

	if collapse.clicked {
		window.collapsed = !window.collapsed
	}

	bounds := window_visible_bounds(ctx, window)
	if err = region(ctx, bounds); err != .None {
		return {}, false, err
	}

	focused := ctx.focus_window == window.id
	if err = control_frame(ctx, bounds, {focused = focused}, true); err != .None {
		return {}, false, err
	}

	if focused {
		if err = draw_error(
			draw2d.rectangle(
				&ctx.draws,
				inset_rect(header, {ctx.style.border_width, ctx.style.border_width}),
				ctx.style.hover,
			),
		); err != .None {
			return {}, false, err
		}
	}

	if err = control_text(ctx, collapse_rect, "+" if window.collapsed else "-", true);
	   err != .None {
		return {}, false, err
	}

	if err = control_text(ctx, close_rect, "x", true); err != .None {
		return {}, false, err
	}

	for interaction, i in ([2]Interaction{collapse, close}) {
		if interaction.hovered || interaction.focused {
			rect := collapse_rect if i == 0 else close_rect
			line := Rect {
				rect.position +
				[2]f32{ctx.style.padding.x, rect.size.y - ctx.style.border_width * 3},
				{max(rect.size.x - ctx.style.padding.x * 2, 0), ctx.style.border_width},
			}
			if err = draw_error(draw2d.rectangle(&ctx.draws, line, ctx.style.focus));
			   err != .None {
				return {}, false, err
			}
		}
	}

	title_rect := Rect {
		header.position + [2]f32{button_width, 0},
		{header.size.x - button_width * 2, header_height},
	}
	if err = control_text(ctx, title_rect, title, true); err != .None {
		return {}, false, err
	}

	if window.collapsed {
		return {}, false, .None
	}

	for i in 0 ..< 2 {
		length := f32(4 + i * 4)
		grip := Rect {
			bounds.position + bounds.size - [2]f32{length + 3, 5 + f32(i * 4)},
			{length, 2},
		}
		if err = draw_error(draw2d.rectangle(&ctx.draws, grip, ctx.style.border)); err != .None {
			return {}, false, err
		}
	}

	body := Rect {
		bounds.position + [2]f32{0, header_height},
		{bounds.size.x, bounds.size.y - header_height},
	}
	body = inset_rect(
		body,
		ctx.style.padding + [2]f32{ctx.style.border_width, ctx.style.border_width},
	)
	if err = draw_error(draw2d.push_clip(&ctx.draws, body)); err != .None {
		return {}, false, err
	}

	body_open = true
	return body, true, .None
}

end_window :: proc(ctx: ^Context) -> Error {
	if !ctx.frame_active ||
	   ctx.current_window == 0 ||
	   ctx.in_overlay ||
	   len(ctx.scrolls) != 0 ||
	   len(ctx.draws.clips) != 2 {
		return .Invalid_Frame
	}

	if err := draw_error(draw2d.pop_clip(&ctx.draws)); err != .None {
		return err
	}

	finish_window(ctx)
	return .None
}

@(private)
finish_window :: proc(ctx: ^Context) {
	record := ctx.windows[ctx.current_window]
	ctx.draws, record.draws = record.draws, ctx.draws
	record.submitted = true
	ctx.windows[ctx.current_window] = record
	ctx.current_window = 0
}

@(private)
prepare_windows :: proc(ctx: ^Context, windows: []^Window) -> Error {
	if len(windows) > 0 {
		if err := validate_style(&ctx.style); err != .None {
			return err
		}
	}

	for window, i in windows {
		if window == nil || window.id == 0 {
			return .Invalid_ID
		}

		if !valid_rect(window.bounds) || !valid_rect({size = window.minimum_size}) {
			return .Invalid_Layout
		}

		for previous in windows[:i] {
			if previous.id == window.id {
				return .Duplicate_ID
			}
		}
	}

	for id, record in ctx.windows {
		updated := record
		updated.state = nil
		updated.submitted = false
		ctx.windows[id] = updated
	}

	new_window: ID
	for window in windows {
		record, exists := ctx.windows[window.id]
		if !exists {
			new_window = window.id if window.open else new_window
			record.draws = draw2d.create_list(ctx.window_order.allocator)
			if _, err := append(&ctx.window_order, window.id); err != nil {
				draw2d.destroy_list(&record.draws)
				return .Allocation_Failed
			}
		}

		record.state = window
		err := draw_error(draw2d.reset(&record.draws, ctx.draws.size))
		ctx.windows[window.id] = record
		if err != .None {
			return err
		}

		minimum := window_minimum_size(ctx, window)
		for axis in 0 ..< 2 {
			window.bounds.size[axis] = max(window.bounds.size[axis], minimum[axis])
		}
		keep_window_reachable(ctx, window)
	}

	for i := len(ctx.window_order) - 1; i >= 0; i -= 1 {
		id := ctx.window_order[i]
		record := ctx.windows[id]
		if record.state == nil {
			draw2d.destroy_list(&record.draws)
			delete_key(&ctx.windows, id)
			copy(ctx.window_order[i:], ctx.window_order[i + 1:])
			pop(&ctx.window_order)
		}
	}

	previous_focus := ctx.focus_window
	if ctx.focus_window != 0 && !window_open(ctx, ctx.focus_window) {
		ctx.focus_window = 0
		for i := len(ctx.window_order) - 1; i >= 0; i -= 1 {
			if window_open(ctx, ctx.window_order[i]) {
				ctx.focus_window = ctx.window_order[i]
				break
			}
		}
	}

	if new_window != 0 {
		ctx.focus_window = new_window
	}

	if ctx.focus_window != previous_focus {
		ctx.focus = 0
		clear(&ctx.previous_order)
	}

	if ctx.popup_window != 0 && !window_open(ctx, ctx.popup_window) {
		ctx.popup = 0
		ctx.popup_window = 0
	}

	return .None
}

@(private)
update_window_input :: proc(ctx: ^Context) {
	ctx.hover_window = 0
	if !ctx.raw_input.focused || !ctx.raw_input.mouse_position_valid {
		ctx.window_drag = {}
		return
	}

	if input.mouse_pressed(&ctx.raw_input, .Left) && !ctx.mouse_blocked && ctx.popup == 0 {
		pressed_window := window_at(ctx, ctx.press_pointer)
		if ctx.focus_window != pressed_window {
			ctx.focus_window = pressed_window
			clear(&ctx.previous_order)
		}
		if pressed_window != 0 {
			raise_window(ctx, pressed_window)
			window := ctx.windows[pressed_window].state
			ctx.pointer_over = true
			edges := window_edges(ctx, window, ctx.press_pointer)
			header := Rect {
				window.bounds.position,
				{window.bounds.size.x, window_header_height(ctx)},
			}
			button_width :=
				ctx.style.font_size + ctx.style.padding.x * 2 + ctx.style.border_width * 2
			title := Rect {
				header.position + [2]f32{button_width, 0},
				{header.size.x - button_width * 2, header.size.y},
			}
			if edges != {} || contains(title, ctx.press_pointer) {
				ctx.window_drag = {window.id, window.bounds, ctx.press_pointer, edges}
				ctx.active = 0
				ctx.mouse_owned[.Left] = true
			}
		}
	}

	if ctx.window_drag.window != 0 {
		if window_open(ctx, ctx.window_drag.window) &&
		   (input.mouse_down(&ctx.raw_input, .Left) ||
				   input.mouse_released(&ctx.raw_input, .Left)) {
			window := ctx.windows[ctx.window_drag.window].state
			delta := [2]f32 {
				f32(ctx.pointer.x - ctx.window_drag.pointer.x),
				f32(ctx.pointer.y - ctx.window_drag.pointer.y),
			}
			bounds := ctx.window_drag.bounds
			edges := ctx.window_drag.edges
			minimum := window_minimum_size(ctx, window)
			if edges == {} {
				bounds.position += delta
			} else {
				for axis in 0 ..< 2 {
					near := Window_Edge.Left if axis == 0 else Window_Edge.Top
					far := Window_Edge.Right if axis == 0 else Window_Edge.Bottom
					if near in edges {
						end := bounds.position[axis] + bounds.size[axis]
						bounds.position[axis] = min(
							bounds.position[axis] + delta[axis],
							end - minimum[axis],
						)
						bounds.size[axis] = end - bounds.position[axis]
					} else if far in edges {
						bounds.size[axis] = max(bounds.size[axis] + delta[axis], minimum[axis])
					}
				}
			}
			window.bounds = bounds
			keep_window_reachable(ctx, window)
			ctx.pointer_over = true
			ctx.mouse_owned[.Left] = true
		} else {
			ctx.window_drag = {}
		}
	}

	ctx.hover_window = window_at(ctx, ctx.pointer)

	if input.mouse_released(&ctx.raw_input, .Left) && ctx.window_drag.window != 0 {
		ctx.window_drag = {}
		ctx.mouse_blocked = true
	}
}

@(private)
window_at :: proc(ctx: ^Context, pointer: [2]f64) -> ID {
	for i := len(ctx.window_order) - 1; i >= 0; i -= 1 {
		id := ctx.window_order[i]
		if window_open(ctx, id) {
			bounds := window_visible_bounds(ctx, ctx.windows[id].state)
			margin := window_resize_margin(ctx)
			if contains(
				{
					bounds.position - [2]f32{margin, margin},
					bounds.size + [2]f32{margin * 2, margin * 2},
				},
				pointer,
			) {
				return id
			}
		}
	}

	return 0
}

@(private)
window_edges :: proc(ctx: ^Context, window: ^Window, pointer: [2]f64) -> Window_Edges {
	if window.collapsed {
		return {}
	}

	bounds := window.bounds
	margin := window_resize_margin(ctx)
	edges: Window_Edges
	if abs(pointer.x - f64(bounds.position.x)) <= f64(margin) {
		edges += {.Left}
	} else if abs(pointer.x - f64(bounds.position.x + bounds.size.x)) <= f64(margin) {
		edges += {.Right}
	}

	if abs(pointer.y - f64(bounds.position.y)) <= f64(margin) {
		edges += {.Top}
	} else if abs(pointer.y - f64(bounds.position.y + bounds.size.y)) <= f64(margin) {
		edges += {.Bottom}
	}

	return edges
}

@(private)
raise_window :: proc(ctx: ^Context, id: ID) {
	for value, i in ctx.window_order {
		if value == id {
			copy(ctx.window_order[i:], ctx.window_order[i + 1:])
			ctx.window_order[len(ctx.window_order) - 1] = id
			break
		}
	}
}

@(private)
window_open :: proc(ctx: ^Context, id: ID) -> bool {
	record, exists := ctx.windows[id]
	return exists && record.state != nil && record.state.open
}

@(private)
window_visible_bounds :: proc(ctx: ^Context, window: ^Window) -> Rect {
	bounds := window.bounds
	if window.collapsed {
		bounds.size.y = window_header_height(ctx)
	}

	return bounds
}

@(private)
window_header_height :: proc(ctx: ^Context) -> f32 {
	return ctx.style.font_size + 2 * (ctx.style.padding.y + ctx.style.border_width)
}

@(private)
window_resize_margin :: proc(ctx: ^Context) -> f32 {
	return max(ctx.style.border_width, 4)
}

@(private)
window_minimum_size :: proc(ctx: ^Context, window: ^Window) -> [2]f32 {
	button_width := ctx.style.font_size + ctx.style.padding.x * 2 + ctx.style.border_width * 2
	return {
		max(window.minimum_size.x, button_width * 2 + ctx.style.font_size * 4),
		max(window.minimum_size.y, window_header_height(ctx) + ctx.style.border_width * 2),
	}
}

@(private)
keep_window_reachable :: proc(ctx: ^Context, window: ^Window) {
	header := window_header_height(ctx)
	window.bounds.position.x = clamp(
		window.bounds.position.x,
		min(0, header - window.bounds.size.x),
		max(ctx.draws.size.x - header, 0),
	)
	window.bounds.position.y = clamp(
		window.bounds.position.y,
		0,
		max(ctx.draws.size.y - header, 0),
	)
}

@(private)
compose_windows :: proc(ctx: ^Context) -> Error {
	for id in ctx.window_order {
		record := ctx.windows[id]
		if record.submitted && record.state.open {
			if err := draw_error(draw2d.append_list(&ctx.draws, &record.draws)); err != .None {
				return err
			}
		}
	}

	return .None
}
