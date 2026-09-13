package ui

import "../draw2d"
import "../input"
import "../rhi"
import "core:time"

label :: proc(ctx: ^Context, rect: Rect, value: string, enabled := true) -> Error {
	if !ctx.frame_active || !valid_rect(rect) {
		return .Invalid_Frame
	}

	if err := validate_style(&ctx.style); err != .None {
		return err
	}

	return control_text(ctx, rect, value, enabled)
}

image :: proc(
	ctx: ^Context,
	rect: Rect,
	texture: rhi.Texture_Handle,
	tint: [4]f32 = {1, 1, 1, 1},
) -> Error {
	if !ctx.frame_active {
		return .Invalid_Frame
	}

	return draw_error(draw2d.quad(&ctx.draws, rect, texture, tint))
}

tabs :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	items: []string,
	selected: ^int,
	enabled := true,
) -> (
	bool,
	Error,
) {
	if selected == nil || len(items) == 0 || selected^ < 0 || selected^ >= len(items) {
		return false, .Invalid_Value
	}

	if !valid_rect(rect) {
		return false, .Invalid_Layout
	}

	if err := validate_style(&ctx.style); err != .None {
		return false, err
	}

	previous := selected^
	if enabled && !ctx.mouse_blocked && ctx.popup == 0 {
		for i in 0 ..< len(items) {
			if ctx.focus == index_id(widget, i) {
				direction := int(key_action(ctx, .Right)) - int(key_action(ctx, .Left))
				if direction != 0 {
					selected^ = (i + direction + len(items)) % len(items)
					ctx.focus = index_id(widget, selected^)
				}
				break
			}
		}
	}
	width := rect.size.x / f32(len(items))
	for name, i in items {
		tab_id := index_id(widget, i)
		bounds := Rect{rect.position + [2]f32{f32(i) * width, 0}, {width, rect.size.y}}
		interaction, err := interact(ctx, tab_id, bounds, enabled)
		if err != .None {
			return false, err
		}

		if interaction.clicked {
			selected^ = i
		}

		if err = control_text(ctx, bounds, name, enabled); err != .None {
			return false, err
		}

		if i == selected^ || interaction.focused || interaction.hovered {
			color := ctx.style.focus if interaction.focused else ctx.style.border
			if !enabled {
				color = ctx.style.disabled
			}

			line := Rect {
				bounds.position + [2]f32{0, max(bounds.size.y - ctx.style.border_width, 0)},
				{bounds.size.x, min(bounds.size.y, ctx.style.border_width)},
			}
			if err = draw_error(draw2d.rectangle(&ctx.draws, line, color)); err != .None {
				return false, err
			}
		}
	}

	return previous != selected^, .None
}

dropdown :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	items: []string,
	selected: ^int,
	enabled := true,
) -> (
	bool,
	Error,
) {
	if selected == nil || len(items) == 0 || selected^ < 0 || selected^ >= len(items) {
		return false, .Invalid_Value
	}

	if err := validate_style(&ctx.style); err != .None {
		return false, err
	}

	was_open := ctx.popup == widget
	interaction, err := interact(ctx, widget, rect, enabled)
	if err != .None {
		return false, err
	}

	if !enabled && was_open {
		ctx.popup = 0
	}

	previous := selected^
	if interaction.clicked {
		if was_open {
			if input.pressed(&ctx.raw_input, .Enter) || input.pressed(&ctx.raw_input, .Space) {
				selected^ = clamp(ctx.popup_index, 0, len(items) - 1)
			}
			ctx.popup = 0
		} else {
			ctx.popup = widget
			ctx.popup_index = selected^
			ctx.popup_offset = 0
		}
	} else if interaction.focused &&
	   !was_open &&
	   (key_action(ctx, .Down) || key_action(ctx, .Up)) {
		ctx.popup = widget
		ctx.popup_index = selected^
		ctx.popup_offset = 0
	}

	if err = control_frame(ctx, rect, interaction, enabled); err != .None {
		return false, err
	}

	text_rect := rect
	icon_width := ctx.style.font_size + ctx.style.padding.x * 2 + ctx.style.border_width * 2
	text_rect.size.x = max(rect.size.x - icon_width, 0)
	if err = control_text(ctx, text_rect, items[selected^], enabled); err != .None {
		return false, err
	}

	arrow_rect := Rect {
		rect.position + [2]f32{text_rect.size.x, 0},
		{rect.size.x - text_rect.size.x, rect.size.y},
	}
	if err = control_text(ctx, arrow_rect, "-" if ctx.popup == widget else "+", enabled);
	   err != .None {
		return false, err
	}

	if ctx.popup != widget {
		return previous != selected^, .None
	}

	ctx.popup_seen = true
	if ctx.raw_input.focused {
		ctx.focus = widget
	}
	ctx.popup_anchor = rect
	old_index := ctx.popup_index
	ctx.popup_index = clamp(
		ctx.popup_index + int(key_action(ctx, .Down)) - int(key_action(ctx, .Up)),
		0,
		len(items) - 1,
	)
	if key_action(ctx, .Home) {
		ctx.popup_index = 0
	}
	if key_action(ctx, .End) {
		ctx.popup_index = len(items) - 1
	}

	row_height := max(rect.size.y, ctx.style.font_size + ctx.style.padding.y * 2)
	below := max(ctx.draws.size.y - rect.position.y - rect.size.y, 0)
	above := max(rect.position.y, 0)
	content_height := row_height * f32(len(items))
	use_above := content_height > below && above > below
	popup_height := min(content_height, above if use_above else below)
	bounds := Rect {
		{
			clamp(rect.position.x, 0, max(ctx.draws.size.x - rect.size.x, 0)),
			rect.position.y - popup_height if use_above else rect.position.y + rect.size.y,
		},
		{min(rect.size.x, ctx.draws.size.x), popup_height},
	}
	ctx.popup_bounds = bounds
	ctx.popup_offset = clamp(ctx.popup_offset, 0, max(content_height - popup_height, 0))
	if ctx.raw_input.mouse_position_valid && contains(bounds, ctx.pointer) {
		ctx.pointer_over = true
		ctx.popup_offset = clamp(
			ctx.popup_offset - f32(ctx.raw_input.scroll_delta.y) * row_height * 3,
			0,
			max(content_height - popup_height, 0),
		)
		ctx.wheel_consumed = true
	}

	if old_index != ctx.popup_index || !was_open {
		ctx.popup_offset = clamp(
			ctx.popup_offset,
			max(f32(ctx.popup_index + 1) * row_height - popup_height, 0),
			f32(ctx.popup_index) * row_height,
		)
	}

	if err = begin_overlay(ctx); err != .None {
		return false, err
	}

	defer {
		end_overlay(ctx)
	}
	if err = control_frame(ctx, bounds, {}, true); err != .None {
		return false, err
	}

	if err = draw_error(
		draw2d.push_clip(
			&ctx.draws,
			inset_rect(bounds, {ctx.style.border_width, ctx.style.border_width}),
		),
	); err != .None {
		return false, err
	}

	defer {
		draw2d.pop_clip(&ctx.draws)
	}
	for name, i in items {
		row := Rect {
			bounds.position + [2]f32{0, f32(i) * row_height - ctx.popup_offset},
			{bounds.size.x, row_height},
		}
		hovered := pointer_inside(ctx, row)
		if hovered {
			if ctx.raw_input.mouse_delta != ([2]f64{}) ||
			   input.mouse_pressed(&ctx.raw_input, .Left) {
				ctx.popup_index = i
			}
			if input.mouse_released(&ctx.raw_input, .Left) &&
			   (ctx.mouse_owned[.Left] || input.mouse_pressed(&ctx.raw_input, .Left)) &&
			   was_open {
				selected^ = i
				ctx.popup = 0
				ctx.mouse_blocked = true
			}
		}

		if i == ctx.popup_index {
			if err = draw_error(draw2d.rectangle(&ctx.draws, row, ctx.style.hover)); err != .None {
				return false, err
			}
		}

		if err = control_text(ctx, row, name, true); err != .None {
			return false, err
		}
	}

	return previous != selected^, .None
}

tooltip :: proc(
	ctx: ^Context,
	widget: ID,
	value: string,
	delay: time.Duration = 500 * time.Millisecond,
) -> Error {
	if !ctx.frame_active {
		return .Invalid_Frame
	}

	if ctx.hot != widget ||
	   ctx.active != 0 ||
	   ctx.popup != 0 ||
	   (delay > 0 &&
			   (ctx.last_hot != widget ||
					   time.tick_diff(ctx.hover_since, time.tick_now()) < delay)) {
		return .None
	}

	if err := validate_style(&ctx.style); err != .None {
		return err
	}

	size, measure_error := draw2d.measure_text(ctx.style.font, value, ctx.style.font_size)
	if measure_error != .None {
		return draw_error(measure_error)
	}

	size += ctx.style.padding * 2 + [2]f32{ctx.style.border_width * 2, ctx.style.border_width * 2}
	position := [2]f32{f32(ctx.pointer.x) + 12, f32(ctx.pointer.y) + 20}
	for axis in 0 ..< 2 {
		size[axis] = min(size[axis], ctx.draws.size[axis])
		position[axis] = clamp(position[axis], 0, ctx.draws.size[axis] - size[axis])
	}

	if err := begin_overlay(ctx); err != .None {
		return err
	}

	defer {
		end_overlay(ctx)
	}
	bounds := Rect{position, size}
	if err := control_frame(ctx, bounds, {}, true); err != .None {
		return err
	}

	return control_text(
		ctx,
		inset_rect(bounds, {ctx.style.border_width, ctx.style.border_width}),
		value,
		true,
	)
}

@(private)
index_id :: proc(parent: ID, index: int) -> ID {
	value := u64(parent) ~ (u64(index + 1) * 1099511628211)
	return ID(value) if value != 0 else ID(index + 1)
}

@(private)
begin_overlay :: proc(ctx: ^Context) -> Error {
	if !ctx.frame_active || ctx.in_overlay {
		return .Invalid_Frame
	}

	ctx.draws, ctx.overlays = ctx.overlays, ctx.draws
	ctx.in_overlay = true
	return .None
}

@(private)
end_overlay :: proc(ctx: ^Context) {
	ctx.draws, ctx.overlays = ctx.overlays, ctx.draws
	ctx.in_overlay = false
}
