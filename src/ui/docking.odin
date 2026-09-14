package ui

import "../draw2d"
import "../input"
import "core:math"

Dock_Side :: enum {
	Center,
	Left,
	Right,
	Top,
	Bottom,
}

Dock_Node :: struct {
	alive, central: bool,
	parent:         u32,
	children:       [2]u32,
	axis:           int,
	ratio:          f32,
	windows:        [dynamic]ID,
	active:         ID,
	bounds:         Rect,
}

@(private)
Dock_Drag :: struct {
	node:    u32,
	bounds:  Rect,
	pointer: [2]f64,
}

@(private)
Dock_Target :: struct {
	node:   u32,
	window: ID,
	side:   Dock_Side,
	bounds: Rect,
}

@(private)
new_dock_node :: proc(ctx: ^Context) -> u32 {
	node := Dock_Node {
		alive   = true,
		ratio   = 0.5,
		windows = make([dynamic]ID, ctx.window_order.allocator),
	}
	for &previous, i in ctx.dock_nodes {
		if !previous.alive {
			delete(previous.windows)
			previous = node
			return u32(i + 1)
		}
	}
	append(&ctx.dock_nodes, node)
	return u32(len(ctx.dock_nodes))
}

@(private)
dock_node :: proc(ctx: ^Context, id: u32) -> ^Dock_Node {
	if id == 0 || int(id) > len(ctx.dock_nodes) || !ctx.dock_nodes[id - 1].alive {
		return nil
	}
	return &ctx.dock_nodes[id - 1]
}

@(private)
window_docked :: proc(ctx: ^Context, window: ^Window) -> bool {
	node := dock_node(ctx, window.dock_node)
	return ctx.docking_enabled && node != nil
}

@(private)
dock_root :: proc(ctx: ^Context, id: u32) -> u32 {
	root := id
	for node := dock_node(ctx, root);
	    node != nil && node.parent != 0;
	    node = dock_node(ctx, root) {
		root = node.parent
	}
	return root
}

@(private)
dock_node_visible :: proc(ctx: ^Context, id: u32) -> bool {
	node := dock_node(ctx, id)
	if node == nil {
		return false
	}
	if node.central {
		return true
	}
	if node.children[0] != 0 {
		return dock_node_visible(ctx, node.children[0]) || dock_node_visible(ctx, node.children[1])
	}
	for window in node.windows {
		if window_open(ctx, window) {
			return true
		}
	}
	return false
}

@(private)
dock_minimum :: proc(ctx: ^Context, id: u32) -> [2]f32 {
	node := dock_node(ctx, id)
	if node == nil || !dock_node_visible(ctx, id) {
		return {}
	}
	if node.children[0] != 0 {
		a, b := dock_minimum(ctx, node.children[0]), dock_minimum(ctx, node.children[1])
		if !dock_node_visible(ctx, node.children[0]) {
			return b
		}
		if !dock_node_visible(ctx, node.children[1]) {
			return a
		}
		result := [2]f32{max(a.x, b.x), max(a.y, b.y)}
		result[node.axis] = a[node.axis] + b[node.axis] + dock_divider_size(ctx)
		return result
	}
	minimum := [2]f32{64, 64}
	for id in node.windows {
		if window_open(ctx, id) {
			size := window_minimum_size(ctx, ctx.windows[id].state)
			minimum = {max(minimum.x, size.x), max(minimum.y, size.y)}
		}
	}
	return minimum
}

@(private)
layout_dock_node :: proc(ctx: ^Context, id: u32, bounds: Rect) {
	node := dock_node(ctx, id)
	if node == nil {
		return
	}
	node.bounds = bounds
	if node.children[0] != 0 {
		a, b := node.children[0], node.children[1]
		if !dock_node_visible(ctx, a) {
			layout_dock_node(ctx, a, {bounds.position, {}})
			layout_dock_node(ctx, b, bounds)
			return
		}
		if !dock_node_visible(ctx, b) {
			layout_dock_node(ctx, a, bounds)
			layout_dock_node(ctx, b, {bounds.position, {}})
			return
		}
		axis := node.axis
		gap := min(dock_divider_size(ctx), bounds.size[axis])
		space := max(bounds.size[axis] - gap, 0)
		minimum_a, minimum_b := dock_minimum(ctx, a), dock_minimum(ctx, b)
		low, high := minimum_a[axis], space - minimum_b[axis]
		first := space * node.ratio
		if low <= high {
			first = clamp(first, low, high)
		} else {
			first = space * low / max(low + minimum_b[axis], 1)
		}
		first = math.floor(first)
		left, right := bounds, bounds
		left.size[axis] = first
		right.position[axis] += first + gap
		right.size[axis] = space - first
		layout_dock_node(ctx, a, left)
		layout_dock_node(ctx, b, right)
		return
	}

	active_present := false
	for id in node.windows {
		active_present = active_present || id == node.active
	}
	if !active_present || !window_open(ctx, node.active) {
		node.active = 0
		for window in node.windows {
			if window_open(ctx, window) {
				node.active = window
				break
			}
		}
	}
	for id in node.windows {
		if record, exists := ctx.windows[id]; exists && record.state != nil {
			record.state.bounds = bounds
		}
	}
}

@(private)
layout_docks :: proc(ctx: ^Context) {
	if !ctx.docking_enabled {
		return
	}
	if ctx.dock_root == 0 {
		ctx.dock_root = new_dock_node(ctx)
		dock_node(ctx, ctx.dock_root).central = true
	}
	for node, i in ctx.dock_nodes {
		if !node.alive || node.parent != 0 {
			continue
		}
		bounds := node.bounds
		if u32(i + 1) == ctx.dock_root {
			bounds = {{}, ctx.draws.size}
		} else {
			minimum := dock_minimum(ctx, u32(i + 1))
			bounds.size = {max(bounds.size.x, minimum.x), max(bounds.size.y, minimum.y)}
			bounds.position.x = clamp(
				bounds.position.x,
				min(0, window_header_height(ctx) - bounds.size.x),
				max(ctx.draws.size.x - window_header_height(ctx), 0),
			)
			bounds.position.y = clamp(
				bounds.position.y,
				0,
				max(ctx.draws.size.y - window_header_height(ctx), 0),
			)
		}
		layout_dock_node(ctx, u32(i + 1), bounds)
	}
}

@(private)
remove_dock_branch :: proc(ctx: ^Context, id: u32) {
	node := dock_node(ctx, id)
	if node == nil || node.parent == 0 {
		return
	}
	parent_id := node.parent
	parent := dock_node(ctx, parent_id)
	sibling_id := parent.children[1] if parent.children[0] == id else parent.children[0]
	sibling := dock_node(ctx, sibling_id)
	grandparent := parent.parent
	if grandparent == 0 {
		if ctx.dock_root == parent_id {
			ctx.dock_root = sibling_id
		}
	} else {
		ancestor := dock_node(ctx, grandparent)
		ancestor.children[0 if ancestor.children[0] == parent_id else 1] = sibling_id
	}
	sibling.parent = grandparent
	sibling.bounds = parent.bounds
	node.parent = 0
	parent.alive = false
}

undock_window :: proc(ctx: ^Context, window: ^Window) {
	node := dock_node(ctx, window.dock_node)
	if node == nil {
		return
	}
	for id, i in node.windows {
		if id == window.id {
			copy(node.windows[i:], node.windows[i + 1:])
			pop(&node.windows)
			break
		}
	}
	if len(node.windows) == 0 && !node.central {
		remove_dock_branch(ctx, window.dock_node)
		node.alive = false
	}
	window.dock_node = 0
	if valid_rect(window.floating_bounds) &&
	   window.floating_bounds.size.x > 0 &&
	   window.floating_bounds.size.y > 0 {
		window.bounds = window.floating_bounds
	}
	layout_docks(ctx)
}

dock_window :: proc(
	ctx: ^Context,
	window: ^Window,
	target: ID = 0,
	side: Dock_Side = .Center,
) -> Error {
	if !ctx.docking_enabled ||
	   window == nil ||
	   !window_open(ctx, window.id) ||
	   side < .Center ||
	   side > .Bottom ||
	   target == window.id {
		return .Invalid_Layout
	}
	layout_docks(ctx)
	target_node := ctx.dock_root
	if target != 0 {
		record, exists := ctx.windows[target]
		if !exists || record.state == nil {
			return .Invalid_ID
		}
		if record.state.dock_node == 0 {
			target_node = new_dock_node(ctx)
			node := dock_node(ctx, target_node)
			node.bounds = record.state.bounds
			append(&node.windows, target)
			node.active = target
			record.state.floating_bounds = record.state.bounds
			record.state.dock_node = target_node
		} else {
			target_node = record.state.dock_node
		}
	}
	if window.dock_node == target_node {
		return .None
	}
	if side == .Center && dock_node(ctx, target_node).children[0] != 0 {
		return .Invalid_Layout
	}
	floating := window.bounds
	if window.dock_node != 0 {
		undock_window(ctx, window)
		floating = window.bounds
	}
	if target == 0 {
		target_node = ctx.dock_root
	}
	window.floating_bounds = floating
	window.collapsed = false

	leaf := target_node
	if side != .Center {
		leaf = new_dock_node(ctx)
		parent_id := new_dock_node(ctx)
		node := dock_node(ctx, target_node)
		parent := dock_node(ctx, parent_id)
		parent.parent, parent.bounds = node.parent, node.bounds
		parent.axis = 0 if side == .Left || side == .Right else 1
		parent.ratio = 0.3 if target == 0 else 0.5
		first := side == .Left || side == .Top
		if !first && target == 0 {
			parent.ratio = 0.7
		}
		parent.children = {leaf, target_node} if first else {target_node, leaf}
		if node.parent == 0 {
			if ctx.dock_root == target_node {
				ctx.dock_root = parent_id
			}
		} else {
			ancestor := dock_node(ctx, node.parent)
			ancestor.children[0 if ancestor.children[0] == target_node else 1] = parent_id
		}
		node.parent = parent_id
		dock_node(ctx, leaf).parent = parent_id
	}
	node := dock_node(ctx, leaf)
	append(&node.windows, window.id)
	node.active = window.id
	window.dock_node = leaf
	ctx.focus_window, ctx.focus = window.id, 0
	clear(&ctx.previous_order)
	layout_docks(ctx)
	raise_window(ctx, window.id)
	return .None
}

@(private)
dock_divider_size :: proc(ctx: ^Context) -> f32 {
	return max(6, ctx.style.border_width * 3)
}

@(private)
dock_divider :: proc(ctx: ^Context, node: ^Dock_Node) -> Rect {
	rect := node.bounds
	first := dock_node(ctx, node.children[0])
	rect.position[node.axis] = first.bounds.position[node.axis] + first.bounds.size[node.axis]
	rect.size[node.axis] = dock_divider_size(ctx)
	return rect
}

@(private)
dock_tab_rect :: proc(ctx: ^Context, node: ^Dock_Node, index: int) -> Rect {
	count := 0
	for id in node.windows {
		if window_open(ctx, id) {
			count += 1
		}
	}
	header := window_header_height(ctx)
	width := max((node.bounds.size.x - header * 2) / f32(max(count, 1)), 0)
	return {node.bounds.position + [2]f32{header + f32(index) * width, 0}, {width, header}}
}

@(private)
update_dock_input :: proc(ctx: ^Context) -> bool {
	if !ctx.docking_enabled || !ctx.raw_input.focused || !ctx.raw_input.mouse_position_valid {
		ctx.dock_drag = {}
		return false
	}
	if ctx.dock_drag.node != 0 {
		node := dock_node(ctx, ctx.dock_drag.node)
		if node != nil &&
		   (input.mouse_down(&ctx.raw_input, .Left) ||
				   input.mouse_released(&ctx.raw_input, .Left)) {
			axis := node.axis
			space := max(node.bounds.size[axis] - dock_divider_size(ctx), 1)
			node.ratio = clamp(
				f32(ctx.pointer[axis] - f64(node.bounds.position[axis])) / space,
				0.01,
				0.99,
			)
			layout_docks(ctx)
			ctx.cursor = .Resize_Horizontal if axis == 0 else .Resize_Vertical
			ctx.pointer_over = true
			ctx.mouse_owned[.Left] = true
			ctx.mouse_blocked = true
		}
		if !input.mouse_down(&ctx.raw_input, .Left) {
			ctx.dock_drag = {}
		}
		return true
	}
	if ctx.focus_window != 0 &&
	   window_open(ctx, ctx.focus_window) &&
	   (input.down(&ctx.raw_input, .Left_Control) || input.down(&ctx.raw_input, .Right_Control)) {
		node := dock_node(ctx, ctx.windows[ctx.focus_window].state.dock_node)
		if node != nil &&
		   (input.pressed(&ctx.raw_input, .Page_Up) || input.pressed(&ctx.raw_input, .Page_Down)) {
			direction := -1 if input.pressed(&ctx.raw_input, .Page_Up) else 1
			selected := 0
			for id, i in node.windows {
				if id == node.active {
					selected = i
					break
				}
			}
			for offset in 1 ..= len(node.windows) {
				index := (selected + direction * offset + len(node.windows)) % len(node.windows)
				if window_open(ctx, node.windows[index]) {
					node.active = node.windows[index]
					ctx.focus_window, ctx.focus = node.active, 0
					ctx.popup, ctx.popup_window = 0, 0
					clear(&ctx.previous_order)
					ctx.navigation_used = true
					ctx.key_owned[.Page_Up] = input.pressed(&ctx.raw_input, .Page_Up)
					ctx.key_owned[.Page_Down] = input.pressed(&ctx.raw_input, .Page_Down)
					break
				}
			}
		}
	}
	if ctx.window_drag.window != 0 || ctx.popup != 0 || ctx.active != 0 {
		return false
	}
	hit := ctx.press_pointer if input.mouse_pressed(&ctx.raw_input, .Left) else ctx.pointer
	for &node, i in ctx.dock_nodes {
		if !node.alive ||
		   node.children[0] == 0 ||
		   !dock_node_visible(ctx, node.children[0]) ||
		   !dock_node_visible(ctx, node.children[1]) {
			continue
		}
		if contains(dock_divider(ctx, &node), hit) && window_at(ctx, hit) == 0 {
			ctx.cursor = .Resize_Horizontal if node.axis == 0 else .Resize_Vertical
			ctx.pointer_over = true
			if input.mouse_pressed(&ctx.raw_input, .Left) {
				ctx.dock_drag = {
					node = u32(i + 1),
				}
				ctx.mouse_owned[.Left] = true
				ctx.mouse_blocked = true
				return update_dock_input(ctx)
			}
			return true
		}
	}
	if input.mouse_pressed(&ctx.raw_input, .Left) && !ctx.mouse_blocked {
		window_id := window_at(ctx, ctx.press_pointer)
		if window_id != 0 {
			window := ctx.windows[window_id].state
			node := dock_node(ctx, window.dock_node)
			if node != nil && window_edges(ctx, window, ctx.press_pointer) == {} {
				grip := Rect {
					node.bounds.position,
					{window_header_height(ctx), window_header_height(ctx)},
				}
				if contains(grip, ctx.press_pointer) {
					ctx.window_drag = {
						window         = window.id,
						group          = window.dock_node,
						grab_offset    = {
							window_header_height(ctx) * 0.5,
							window_header_height(ctx) * 0.5,
						},
						bounds         = node.bounds,
						pointer        = ctx.press_pointer,
						pending_undock = true,
					}
					ctx.mouse_owned[.Left] = true
					raise_window(ctx, window.id)
					return true
				}
				index := 0
				for id in node.windows {
					if !window_open(ctx, id) {
						continue
					}
					if contains(dock_tab_rect(ctx, node, index), ctx.press_pointer) {
						node.active = id
						ctx.focus_window, ctx.focus = id, 0
						ctx.popup, ctx.popup_window = 0, 0
						clear(&ctx.previous_order)
						raise_window(ctx, id)
						ctx.window_drag = {
							window         = id,
							bounds         = window.bounds,
							pointer        = ctx.press_pointer,
							pending_undock = true,
						}
						ctx.mouse_owned[.Left] = true
						return true
					}
					index += 1
				}
			}
		}
	}
	return false
}

@(private)
find_dock_target :: proc(ctx: ^Context, moving: ID) -> Dock_Target {
	if !ctx.docking_enabled ||
	   input.down(&ctx.raw_input, .Left_Shift) ||
	   input.down(&ctx.raw_input, .Right_Shift) {
		return {}
	}
	point := ctx.pointer
	for side in ([4]Dock_Side{.Left, .Right, .Top, .Bottom}) {
		axis := 0 if side == .Left || side == .Right else 1
		near := side == .Left || side == .Top
		if point[axis] >= 0 &&
		   point[axis] <= f64(ctx.draws.size[axis]) &&
		   (point[axis] < 24 if near else point[axis] > f64(ctx.draws.size[axis] - 24)) {
			bounds := Rect{{}, ctx.draws.size}
			bounds.size[axis] *= 0.3
			if !near {
				bounds.position[axis] = ctx.draws.size[axis] - bounds.size[axis]
			}
			return {node = ctx.dock_root, side = side, bounds = bounds}
		}
	}
	for layer := 1; layer >= 0; layer -= 1 {
		for i := len(ctx.window_order) - 1; i >= 0; i -= 1 {
			id := ctx.window_order[i]
			if window_layer(ctx, ctx.windows[id].state) != layer {
				continue
			}
			if id == moving ||
			   !window_open(ctx, id) ||
			   (ctx.window_drag.group != 0 &&
					   dock_root(ctx, ctx.windows[id].state.dock_node) == ctx.window_drag.group) {
				continue
			}
			window := ctx.windows[id].state
			if window_docked(ctx, window) && dock_node(ctx, window.dock_node).active != id {
				continue
			}
			bounds := window_visible_bounds(ctx, window)
			if !contains(bounds, point) {
				continue
			}
			local := [2]f32{f32(point.x) - bounds.position.x, f32(point.y) - bounds.position.y}
			side := Dock_Side.Center
			if local.y < window_header_height(ctx) {
				side = .Center
			} else if local.x < bounds.size.x * 0.25 {
				side = .Left
			} else if local.x > bounds.size.x * 0.75 {
				side = .Right
			} else if local.y < bounds.size.y * 0.25 {
				side = .Top
			} else if local.y > bounds.size.y * 0.75 {
				side = .Bottom
			}
			if side != .Center {
				axis := 0 if side == .Left || side == .Right else 1
				bounds.size[axis] *= 0.5
				if side == .Right || side == .Bottom {
					bounds.position[axis] += bounds.size[axis]
				}
			}
			return {node = window.dock_node, window = id, side = side, bounds = bounds}
		}
	}
	return {}
}

@(private)
draw_dock_header :: proc(ctx: ^Context, window: ^Window) -> Error {
	node := dock_node(ctx, window.dock_node)
	header := window_header_height(ctx)
	if err := control_text(ctx, {node.bounds.position, {header, header}}, "=", true);
	   err != .None {
		return err
	}
	index := 0
	for id in node.windows {
		if !window_open(ctx, id) {
			continue
		}
		rect := dock_tab_rect(ctx, node, index)
		record := ctx.windows[id]
		if id == node.active {
			if err := draw_error(
				draw2d.rectangle(&ctx.draws, inset_rect(rect, {2, 2}), ctx.style.hover),
			); err != .None {
				return err
			}
		}
		if err := control_text(ctx, rect, record.title, true); err != .None {
			return err
		}
		index += 1
	}
	close_rect := Rect {
		node.bounds.position + [2]f32{node.bounds.size.x - header, 0},
		{header, header},
	}
	clicked, err := button(ctx, id("dock-close", window.id), close_rect, "x")
	if clicked {
		window.open = false
	}
	return err
}

@(private)
compose_docks :: proc(ctx: ^Context, root: u32) -> Error {
	if !ctx.docking_enabled {
		return .None
	}
	for &node, i in ctx.dock_nodes {
		if dock_root(ctx, u32(i + 1)) != root {
			continue
		}
		if node.alive &&
		   node.children[0] != 0 &&
		   dock_node_visible(ctx, node.children[0]) &&
		   dock_node_visible(ctx, node.children[1]) {
			color :=
				ctx.style.focus if ctx.dock_drag.node != 0 && dock_node(ctx, ctx.dock_drag.node) == &node else ctx.style.border
			if err := draw_error(draw2d.rectangle(&ctx.draws, dock_divider(ctx, &node), color));
			   err != .None {
				return err
			}
		}
	}
	return .None
}

@(private)
draw_dock_preview :: proc(ctx: ^Context) -> Error {
	if ctx.dock_target.node == 0 && ctx.dock_target.window == 0 {
		return .None
	}
	color := ctx.style.focus
	color.a = 0.25
	if err := draw_error(draw2d.rectangle(&ctx.draws, ctx.dock_target.bounds, color));
	   err != .None {
		return err
	}
	b := ctx.dock_target.bounds
	w := ctx.style.border_width
	for rect in ([4]Rect {
			{b.position, {b.size.x, w}},
			{b.position + [2]f32{0, b.size.y - w}, {b.size.x, w}},
			{b.position, {w, b.size.y}},
			{b.position + [2]f32{b.size.x - w, 0}, {w, b.size.y}},
		}) {
		if err := draw_error(draw2d.rectangle(&ctx.draws, rect, ctx.style.focus)); err != .None {
			return err
		}
	}
	return .None
}

@(private)
reorder_dock_tab :: proc(ctx: ^Context, node: ^Dock_Node, moving: ID) {
	source, destination := -1, -1
	visible := 0
	for id, i in node.windows {
		if id == moving {
			source = i
		}
		if window_open(ctx, id) {
			if contains(dock_tab_rect(ctx, node, visible), ctx.pointer) {
				destination = i
			}
			visible += 1
		}
	}
	if source < 0 || destination < 0 || source == destination {
		return
	}
	if source < destination {
		copy(node.windows[source:destination], node.windows[source + 1:destination + 1])
	} else {
		for i := source; i > destination; i -= 1 {
			node.windows[i] = node.windows[i - 1]
		}
	}
	node.windows[destination] = moving
}

@(private)
detach_dock_group :: proc(ctx: ^Context, id: u32) {
	node := dock_node(ctx, id)
	if dock_root(ctx, id) == ctx.dock_root {
		size := dock_minimum(ctx, id)
		for member in node.windows {
			if record, exists := ctx.windows[member]; exists {
				floating := record.state.floating_bounds.size
				size = {max(size.x, floating.x), max(size.y, floating.y)}
			}
		}
		node.bounds.size = size
	}
	if node.central {
		replacement := new_dock_node(ctx)
		node = dock_node(ctx, id)
		center := dock_node(ctx, replacement)
		center.central, center.parent = true, node.parent
		if node.parent == 0 {
			ctx.dock_root = replacement
		} else {
			parent := dock_node(ctx, node.parent)
			parent.children[0 if parent.children[0] == id else 1] = replacement
		}
		node.central, node.parent = false, 0
	} else {
		remove_dock_branch(ctx, id)
	}
	layout_docks(ctx)
}

@(private)
dock_group :: proc(ctx: ^Context, group: u32, target: Dock_Target) {
	node := dock_node(ctx, group)
	members := make([]ID, len(node.windows), ctx.window_order.allocator)
	defer delete(members, ctx.window_order.allocator)
	copy(members, node.windows[:])
	destination := target.window
	side := target.side
	for id in members {
		record, exists := ctx.windows[id]
		if !exists {
			continue
		}
		was_open := record.state.open
		record.state.open = true
		err := dock_window(ctx, record.state, destination, side)
		record.state.open = was_open
		if err != .None {
			break
		}
		destination, side = id, .Center
	}
}
