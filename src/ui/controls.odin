package ui

import "../draw2d"
import "../input"
import "core:fmt"
import "core:math"

Style :: struct {
	font:         ^draw2d.Font,
	font_size:    f32,
	padding:      [2]f32,
	border_width: f32,
	thumb_width:  f32,
	text:         [4]f32,
	background:   [4]f32,
	hover:        [4]f32,
	active:       [4]f32,
	border:       [4]f32,
	focus:        [4]f32,
	disabled:     [4]f32,
	thumb:        [4]f32,
}

button :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	label: string,
	enabled := true,
) -> (
	bool,
	Error,
) {
	if err := validate_style(&ctx.style); err != .None {
		return false, err
	}

	interaction, err := interact(ctx, widget, rect, enabled)
	if err != .None {
		return false, err
	}

	if err = control_frame(ctx, rect, interaction, enabled); err != .None {
		return false, err
	}

	if err = control_text(ctx, rect, label, enabled); err != .None {
		return false, err
	}

	return interaction.clicked, .None
}

checkbox :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	label: string,
	value: ^bool,
	enabled := true,
) -> (
	bool,
	Error,
) {
	if value == nil {
		return false, .Invalid_Value
	}

	if err := validate_style(&ctx.style); err != .None {
		return false, err
	}

	interaction, err := interact(ctx, widget, rect, enabled)
	if err != .None {
		return false, err
	}

	checked := value^ != interaction.clicked
	side := min(rect.size.x, rect.size.y)
	box := Rect{rect.position, {side, side}}
	if err = control_frame(ctx, box, interaction, enabled); err != .None {
		return false, err
	}

	if checked {
		mark := inset_rect(box, {ctx.style.border_width * 2, ctx.style.border_width * 2})
		color := ctx.style.text if enabled else ctx.style.disabled
		if err = draw_error(draw2d.rectangle(&ctx.draws, mark, color)); err != .None {
			return false, err
		}
	}

	text_rect := Rect{rect.position + [2]f32{side, 0}, {rect.size.x - side, rect.size.y}}
	if err = control_text(ctx, text_rect, label, enabled); err != .None {
		return false, err
	}

	value^ = checked
	return interaction.clicked, .None
}

slider :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	label: string,
	value: ^f32,
	low, high: f32,
	step: f32 = 0.01,
	enabled := true,
	precision: int = 2,
) -> (
	bool,
	Error,
) {
	if value == nil ||
	   !finite(value^) ||
	   !finite(low) ||
	   !finite(high) ||
	   high <= low ||
	   !finite(step) ||
	   step <= 0 ||
	   precision < 0 ||
	   precision > 9 {
		return false, .Invalid_Value
	}

	if err := validate_style(&ctx.style); err != .None {
		return false, err
	}

	if !valid_rect(rect) {
		return false, .Invalid_Frame
	}

	label_rect := Rect{rect.position, {rect.size.x, rect.size.y / 2}}
	track_rect := Rect {
		rect.position + [2]f32{0, label_rect.size.y},
		{rect.size.x, rect.size.y - label_rect.size.y},
	}
	was_active := ctx.active == widget
	interaction, err := interact(ctx, widget, track_rect, enabled)
	if err != .None {
		return false, err
	}

	inner := inset_rect(track_rect, {ctx.style.border_width, ctx.style.border_width})
	thumb_width := min(ctx.style.thumb_width, inner.size.x)
	travel := inner.size.x - thumb_width
	v := f64(value^)
	if enabled {
		v = clamp(v, f64(low), f64(high))
		pointer_changed :=
			interaction.held ||
			(input.mouse_released(&ctx.raw_input, .Left) &&
					(was_active ||
							(interaction.hovered && input.mouse_pressed(&ctx.raw_input, .Left))))
		if ctx.raw_input.focused && pointer_changed && travel > 0 {
			t := clamp(
				(ctx.pointer.x - f64(inner.position.x + thumb_width / 2)) / f64(travel),
				0,
				1,
			)
			v = f64(low) + t * (f64(high) - f64(low))
			if t > 0 && t < 1 {
				v = f64(low) + math.round((v - f64(low)) / f64(step)) * f64(step)
			}
		}

		if interaction.focused {
			if key_action(ctx, .Left) || key_action(ctx, .Down) {
				v -= f64(step)
			}

			if key_action(ctx, .Right) || key_action(ctx, .Up) {
				v += f64(step)
			}

			if key_action(ctx, .Home) {
				v = f64(low)
			}

			if key_action(ctx, .End) {
				v = f64(high)
			}
		}

		v = clamp(v, f64(low), f64(high))
	}

	track_height := min(max(ctx.style.border_width, 1), inner.size.y)
	track := Rect {
		inner.position + [2]f32{thumb_width / 2, math.floor((inner.size.y - track_height) / 2)},
		{travel, track_height},
	}
	track_color := ctx.style.border if enabled else ctx.style.disabled
	if err = draw_error(draw2d.rectangle(&ctx.draws, track, track_color)); err != .None {
		return false, err
	}

	t := f32(clamp((v - f64(low)) / (f64(high) - f64(low)), 0, 1))
	thumb := Rect {
		inner.position + [2]f32{min(math.round(t * travel), travel), 0},
		{thumb_width, inner.size.y},
	}
	color := ctx.style.focus if interaction.focused || interaction.hovered else ctx.style.thumb
	if !enabled {
		color = ctx.style.disabled
	}
	if err = draw_error(draw2d.rectangle(&ctx.draws, thumb, color)); err != .None {
		return false, err
	}

	buffer: [256]u8
	text := fmt.bprintf(buffer[:], "%s %.*f", label, precision, v)
	if err = control_text(ctx, label_rect, text, enabled); err != .None {
		return false, err
	}

	changed := value^ != f32(v)
	value^ = f32(v)
	return changed, .None
}

@(private)
validate_style :: proc(style: ^Style) -> Error {
	if style.font == nil ||
	   !finite(style.font.em_size) ||
	   style.font.em_size <= 0 ||
	   !finite(style.font_size) ||
	   style.font_size <= 0 ||
	   !finite(style.border_width) ||
	   style.border_width < 0 ||
	   !finite(style.thumb_width) ||
	   style.thumb_width <= 0 {
		return .Invalid_Style
	}

	for padding in style.padding {
		if !finite(padding) || padding < 0 {
			return .Invalid_Style
		}
	}

	return .None
}

@(private)
inset_rect :: proc(rect: Rect, padding: [2]f32) -> Rect {
	inset := [2]f32{min(padding.x, rect.size.x / 2), min(padding.y, rect.size.y / 2)}
	return {rect.position + inset, rect.size - inset * 2}
}

@(private)
control_frame :: proc(
	ctx: ^Context,
	rect: Rect,
	interaction: Interaction,
	enabled: bool,
) -> Error {
	style := &ctx.style
	border := style.focus if interaction.focused else style.border
	fill :=
		style.active if interaction.held else (style.hover if interaction.hovered else style.background)
	if !enabled {
		border = style.disabled
	}

	if err := draw_error(draw2d.rectangle(&ctx.draws, rect, border)); err != .None {
		return err
	}

	return draw_error(
		draw2d.rectangle(
			&ctx.draws,
			inset_rect(rect, {style.border_width, style.border_width}),
			fill,
		),
	)
}

@(private)
control_text :: proc(ctx: ^Context, rect: Rect, label: string, enabled: bool) -> Error {
	style := &ctx.style
	inner := inset_rect(rect, {style.border_width, style.border_width})
	if err := draw_error(draw2d.push_clip(&ctx.draws, inner)); err != .None {
		return err
	}

	defer {
		draw2d.pop_clip(&ctx.draws)
	}
	content := inset_rect(rect, style.padding)
	size, err := draw2d.measure_text(style.font, label, style.font_size)
	if err != .None {
		return draw_error(err)
	}
	content.position.y = rect.position.y + math.floor((rect.size.y - size.y) / 2)
	color := style.text if enabled else style.disabled
	return draw_error(
		draw2d.text(&ctx.draws, style.font, label, content.position, style.font_size, color),
	)
}

@(private)
draw_error :: proc(err: draw2d.Error) -> Error {
	if err == .None {
		return .None
	}

	return .Allocation_Failed if err == .Allocation_Failed else .Draw_Failed
}
