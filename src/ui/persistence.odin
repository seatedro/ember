package ui

import "core:encoding/json"
import "core:mem"

@(private)
Saved_Window :: struct {
	id:                      ID,
	bounds, floating_bounds: Rect,
	open, collapsed:         bool,
	dock_node:               u32,
}

@(private)
Saved_Layout :: struct {
	version: int,
	root:    u32,
	windows: []Saved_Window,
	nodes:   []Dock_Node,
}

layout_busy :: proc(ctx: ^Context) -> bool {
	return ctx.window_drag.window != 0 || ctx.dock_drag.node != 0
}

encode_layout :: proc(ctx: ^Context, allocator := context.allocator) -> ([]u8, Error) {
	if ctx.frame_active {
		return nil, .Invalid_Frame
	}
	windows := make([]Saved_Window, len(ctx.window_order), allocator)
	defer delete(windows, allocator)
	for id, i in ctx.window_order {
		window := ctx.windows[id].state
		windows[i] = {
			window.id,
			window.bounds,
			window.floating_bounds,
			window.open,
			window.collapsed,
			window.dock_node,
		}
	}
	data, err := json.marshal(
		Saved_Layout{1, ctx.dock_root, windows, ctx.dock_nodes[:]},
		{pretty = true},
		allocator,
	)
	if err != nil {
		delete(data, allocator)
		return nil, .Invalid_Layout
	}
	return data, .None
}

reset_layout :: proc(ctx: ^Context, windows: []^Window) -> Error {
	if ctx.frame_active {
		return .Invalid_Frame
	}
	for window in windows {
		if window == nil {
			return .Invalid_ID
		}
	}
	for window in windows {
		if window.dock_node != 0 &&
		   valid_rect(window.floating_bounds) &&
		   window.floating_bounds.size.x > 0 &&
		   window.floating_bounds.size.y > 0 {
			window.bounds = window.floating_bounds
		}
		window.dock_node = 0
	}
	for node in ctx.dock_nodes {
		delete(node.windows)
	}
	clear(&ctx.dock_nodes)
	clear(&ctx.restored_order)
	ctx.dock_root = 0
	ctx.window_drag, ctx.dock_drag, ctx.dock_target = {}, {}, {}
	ctx.focus, ctx.focus_window, ctx.active, ctx.popup, ctx.popup_window = 0, 0, 0, 0, 0
	clear(&ctx.previous_order)
	return .None
}

decode_layout :: proc(ctx: ^Context, data: []u8, windows: []^Window) -> Error {
	if ctx.frame_active {
		return .Invalid_Frame
	}
	for window, i in windows {
		if window == nil || window.id == 0 {
			return .Invalid_ID
		}
		for previous in windows[:i] {
			if previous.id == window.id {
				return .Duplicate_ID
			}
		}
	}
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	layout: Saved_Layout
	if len(data) > 4 * 1024 * 1024 ||
	   json.unmarshal(data, &layout, allocator = allocator) != nil ||
	   !validate_saved_layout(layout, allocator) {
		return .Invalid_Layout
	}

	reset_layout(ctx, windows)
	ctx.dock_root = layout.root
	for saved in layout.nodes {
		node := saved
		node.windows = make([dynamic]ID, ctx.window_order.allocator)
		for id in saved.windows {
			for window in windows {
				if window.id == id {
					append(&node.windows, id)
					break
				}
			}
		}
		append(&ctx.dock_nodes, node)
	}
	for saved in layout.windows {
		for window in windows {
			if window.id != saved.id {
				continue
			}
			window.bounds, window.floating_bounds = saved.bounds, saved.floating_bounds
			window.open, window.collapsed, window.dock_node =
				saved.open, saved.collapsed, saved.dock_node
			append(&ctx.restored_order, window.id)
			break
		}
	}
	return .None
}

@(private)
validate_saved_layout :: proc(layout: Saved_Layout, allocator: mem.Allocator) -> bool {
	if layout.version != 1 ||
	   len(layout.nodes) > 1024 ||
	   len(layout.windows) > 4096 ||
	   int(layout.root) > len(layout.nodes) {
		return false
	}
	windows := make(map[ID]Saved_Window, allocator)
	for window in layout.windows {
		if window.id == 0 ||
		   window.id in windows ||
		   !valid_rect(window.bounds) ||
		   !valid_rect(window.floating_bounds) ||
		   int(window.dock_node) > len(layout.nodes) {
			return false
		}
		windows[window.id] = window
	}
	members := make(map[ID]bool, allocator)
	central_count := 0
	for node, i in layout.nodes {
		if !node.alive {
			if len(node.windows) != 0 {
				return false
			}
			continue
		}
		if !valid_rect(node.bounds) ||
		   int(node.parent) > len(layout.nodes) ||
		   node.axis < 0 ||
		   node.axis > 1 ||
		   !(node.ratio > 0 && node.ratio < 1) {
			return false
		}
		is_leaf := node.children == [2]u32{}
		if !is_leaf {
			if node.children[0] == 0 ||
			   node.children[1] == 0 ||
			   node.children[0] == node.children[1] ||
			   len(node.windows) != 0 ||
			   node.central {
				return false
			}
			for child in node.children {
				if int(child) > len(layout.nodes) ||
				   !layout.nodes[child - 1].alive ||
				   layout.nodes[child - 1].parent != u32(i + 1) {
					return false
				}
			}
		}
		if node.parent != 0 {
			parent := layout.nodes[node.parent - 1]
			if !parent.alive ||
			   (parent.children[0] != u32(i + 1) && parent.children[1] != u32(i + 1)) {
				return false
			}
		}
		root := u32(i + 1)
		depth := 0
		for layout.nodes[root - 1].parent != 0 {
			root = layout.nodes[root - 1].parent
			depth += 1
			if int(root) > len(layout.nodes) || depth > 64 {
				return false
			}
		}
		if node.central {
			central_count += 1
			if root != layout.root {
				return false
			}
		}
		for id in node.windows {
			window, exists := windows[id]
			if !exists || id in members || window.dock_node != u32(i + 1) {
				return false
			}
			members[id] = true
		}
		if node.active != 0 {
			found := false
			for id in node.windows {
				found = found || id == node.active
			}
			if !found {
				return false
			}
		}
	}
	for window in layout.windows {
		if window.dock_node != 0 && !(window.id in members) {
			return false
		}
	}
	if layout.root != 0 {
		return(
			central_count == 1 &&
			layout.nodes[layout.root - 1].alive &&
			layout.nodes[layout.root - 1].parent == 0 \
		)
	}
	return central_count == 0
}
