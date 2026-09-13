package ui

import "../draw2d"
import "../input"

Scroll_Frame :: struct {
	viewport:     Rect,
	content_size: [2]f32,
	offset:       ^[2]f32,
	clip_depth:   int,
}

begin_scroll :: proc(
	ctx: ^Context,
	widget: ID,
	bounds: Rect,
	content_size: [2]f32,
	offset: ^[2]f32,
) -> (
	Rect,
	Error,
) {
	if offset == nil ||
	   !valid_rect(bounds) ||
	   !valid_rect({size = content_size}) ||
	   !finite(offset.x) ||
	   !finite(offset.y) {
		return {}, .Invalid_Layout
	}

	if err := validate_style(&ctx.style); err != .None {
		return {}, err
	}

	if err := region(ctx, bounds); err != .None {
		return {}, err
	}

	if widget == 0 {
		return {}, .Invalid_ID
	}

	if _, exists := ctx.seen[widget]; exists {
		return {}, .Duplicate_ID
	}
	ctx.seen[widget] = true

	viewport := bounds
	bar_size := max(ctx.style.thumb_width, 8)
	for _ in 0 ..< 2 {
		viewport.size.x = max(
			bounds.size.x - (bar_size if content_size.y > viewport.size.y else 0),
			0,
		)
		viewport.size.y = max(
			bounds.size.y - (bar_size if content_size.x > viewport.size.x else 0),
			0,
		)
	}

	for axis in 0 ..< 2 {
		limit := max(content_size[axis] - viewport.size[axis], 0)
		offset[axis] = clamp(offset[axis], 0, limit)
		if limit == 0 || viewport.size[axis] <= 0 {
			continue
		}

		bar := viewport
		bar.position[1 - axis] += viewport.size[1 - axis]
		bar.size[1 - axis] = min(bar_size, bounds.size[1 - axis])
		bar_id := id("horizontal" if axis == 0 else "vertical", widget)
		was_active := ctx.active == bar_id
		interaction, err := interact(ctx, bar_id, bar)
		if err != .None {
			return {}, err
		}

		thumb_size := min(
			bar.size[axis],
			max(bar_size, bar.size[axis] * viewport.size[axis] / content_size[axis]),
		)
		travel := bar.size[axis] - thumb_size
		if travel > 0 &&
		   (interaction.held || (was_active && input.mouse_released(&ctx.raw_input, .Left))) {
			offset[axis] =
				f32(
					clamp(
						(ctx.pointer[axis] - f64(bar.position[axis] + thumb_size / 2)) /
						f64(travel),
						0,
						1,
					),
				) *
				limit
		}

		if interaction.focused {
			if key_action(ctx, .Home) {
				offset[axis] = 0
			}

			if key_action(ctx, .End) {
				offset[axis] = limit
			}

			if key_action(ctx, .Page_Up) {
				offset[axis] -= viewport.size[axis]
			}

			if key_action(ctx, .Page_Down) {
				offset[axis] += viewport.size[axis]
			}

			if key_action(ctx, .Left if axis == 0 else .Up) {
				offset[axis] -= ctx.style.font_size
			}

			if key_action(ctx, .Right if axis == 0 else .Down) {
				offset[axis] += ctx.style.font_size
			}
		}

		offset[axis] = clamp(offset[axis], 0, limit)
		if err = draw_error(draw2d.rectangle(&ctx.draws, bar, ctx.style.background));
		   err != .None {
			return {}, err
		}

		thumb := bar
		thumb.position[axis] += offset[axis] / limit * travel
		thumb.size[axis] = thumb_size
		color := ctx.style.focus if interaction.focused || interaction.hovered else ctx.style.thumb
		if err = draw_error(draw2d.rectangle(&ctx.draws, inset_rect(thumb, {1, 1}), color));
		   err != .None {
			return {}, err
		}
	}

	if _, err := append(
		&ctx.scrolls,
		Scroll_Frame{viewport, content_size, offset, len(ctx.draws.clips)},
	); err != nil {
		return {}, .Allocation_Failed
	}

	if err := draw_error(draw2d.push_clip(&ctx.draws, viewport)); err != .None {
		pop(&ctx.scrolls)
		return {}, err
	}

	return {
			viewport.position - offset^,
			{max(content_size.x, viewport.size.x), max(content_size.y, viewport.size.y)},
		},
		.None
}

end_scroll :: proc(ctx: ^Context) -> Error {
	if !ctx.frame_active || len(ctx.scrolls) == 0 {
		return .Invalid_Frame
	}

	frame := ctx.scrolls[len(ctx.scrolls) - 1]
	if len(ctx.draws.clips) != frame.clip_depth + 1 {
		return .Invalid_Frame
	}

	if !ctx.wheel_consumed && pointer_inside(ctx, frame.viewport) {
		previous := frame.offset^
		for axis in 0 ..< 2 {
			limit := max(frame.content_size[axis] - frame.viewport.size[axis], 0)
			frame.offset[axis] = clamp(
				frame.offset[axis] -
				f32(ctx.raw_input.scroll_delta[axis]) * ctx.style.font_size * 3,
				0,
				limit,
			)
		}

		ctx.wheel_consumed = previous != frame.offset^
	}

	pop(&ctx.scrolls)
	return draw_error(draw2d.pop_clip(&ctx.draws))
}

@(private)
reveal_focused :: proc(ctx: ^Context, bounds: Rect) {
	rect := bounds
	for i := len(ctx.scrolls) - 1; i >= 0; i -= 1 {
		frame := ctx.scrolls[i]
		for axis in 0 ..< 2 {
			delta: f32
			if rect.position[axis] < frame.viewport.position[axis] {
				delta = rect.position[axis] - frame.viewport.position[axis]
			} else if rect.position[axis] + rect.size[axis] >
			   frame.viewport.position[axis] + frame.viewport.size[axis] {
				delta =
					rect.position[axis] +
					min(rect.size[axis], frame.viewport.size[axis]) -
					frame.viewport.position[axis] -
					frame.viewport.size[axis]
			}

			limit := max(frame.content_size[axis] - frame.viewport.size[axis], 0)
			old := frame.offset[axis]
			frame.offset[axis] = clamp(old + delta, 0, limit)
			rect.position[axis] -= frame.offset[axis] - old
		}
	}
}
