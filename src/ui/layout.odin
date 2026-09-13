package ui

import "../draw2d"
import "core:math"

Rect :: draw2d.Rect

Axis :: enum {
	Row,
	Column,
}

Layout :: struct {
	bounds:          Rect,
	axis:            Axis,
	spacing, cursor: f32,
}

layout :: proc(bounds: Rect, axis: Axis, padding: f32 = 0, spacing: f32 = 0) -> (Layout, Error) {
	if !valid_rect(bounds) ||
	   !finite(padding) ||
	   padding < 0 ||
	   !finite(spacing) ||
	   spacing < 0 ||
	   axis < .Row ||
	   axis > .Column {
		return {}, .Invalid_Layout
	}

	inset := [2]f32{min(padding, bounds.size.x / 2), min(padding, bounds.size.y / 2)}
	return {
			bounds = {position = bounds.position + inset, size = bounds.size - inset * 2},
			axis = axis,
			spacing = spacing,
		},
		.None
}

next :: proc(layout: ^Layout, extent: f32) -> (Rect, Error) {
	if !finite(extent) ||
	   extent < 0 ||
	   !valid_rect(layout.bounds) ||
	   !finite(layout.cursor) ||
	   layout.cursor < 0 ||
	   !finite(layout.spacing) ||
	   layout.spacing < 0 {
		return {}, .Invalid_Layout
	}

	axis := int(layout.axis)
	if axis < 0 || axis > 1 {
		return {}, .Invalid_Layout
	}

	available := max(layout.bounds.size[axis] - layout.cursor, 0)
	if layout.cursor > layout.bounds.size[axis] || extent > available {
		return {}, .Layout_Overflow
	}

	next_cursor := layout.cursor + extent + layout.spacing
	if !finite(next_cursor) {
		return {}, .Invalid_Layout
	}

	rect := layout.bounds
	rect.position[axis] += layout.cursor
	rect.size[axis] = extent
	layout.cursor = next_cursor
	return rect, .None
}

@(private)
finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

@(private)
valid_rect :: proc(rect: Rect) -> bool {
	for i in 0 ..< 2 {
		if !finite(rect.position[i]) ||
		   !finite(rect.size[i]) ||
		   rect.size[i] < 0 ||
		   !finite(rect.position[i] + rect.size[i]) {
			return false
		}
	}

	return true
}

@(private)
contains :: proc(rect: Rect, position: [2]f64) -> bool {
	return(
		position.x >= f64(rect.position.x) &&
		position.y >= f64(rect.position.y) &&
		position.x < f64(rect.position.x + rect.size.x) &&
		position.y < f64(rect.position.y + rect.size.y) \
	)
}
