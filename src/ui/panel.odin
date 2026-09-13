package ui

import "../draw2d"

collapsible_panel :: proc(
	ctx: ^Context,
	widget: ID,
	bounds: Rect,
	label: string,
	expanded: ^bool,
	enabled := true,
) -> (
	Rect,
	Error,
) {
	if expanded == nil {
		return {}, .Invalid_Value
	}

	if err := validate_style(&ctx.style); err != .None {
		return {}, err
	}

	if !valid_rect(bounds) {
		return {}, .Invalid_Layout
	}

	style := &ctx.style
	header_height := min(
		bounds.size.y,
		style.font_size + 2 * (style.padding.y + style.border_width),
	)
	header := Rect{bounds.position, {bounds.size.x, header_height}}
	interaction, err := interact(ctx, widget, header, enabled)
	if err != .None {
		return {}, err
	}

	open := expanded^ != interaction.clicked
	panel := bounds
	if !open {
		panel.size.y = header_height
	}

	if err = region(ctx, panel); err != .None {
		return {}, err
	}

	if err = control_frame(ctx, panel, {}, enabled); err != .None {
		return {}, err
	}

	if interaction.hovered || interaction.focused || interaction.held {
		fill := style.active if interaction.held else style.hover
		if err = draw_error(
			draw2d.rectangle(
				&ctx.draws,
				inset_rect(header, {style.border_width, style.border_width}),
				fill,
			),
		); err != .None {
			return {}, err
		}
	}

	if err = control_text(
		ctx,
		inset_rect(header, {style.border_width, style.border_width}),
		label,
		enabled,
	); err != .None {
		return {}, err
	}

	expanded^ = open
	if !open {
		return {}, .None
	}

	body := Rect {
		bounds.position + [2]f32{0, header_height},
		{bounds.size.x, bounds.size.y - header_height},
	}
	return inset_rect(body, style.padding + [2]f32{style.border_width, style.border_width}), .None
}
