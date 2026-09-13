package ui

import "../draw2d"
import "../input"
import "core:math"
import "core:strings"
import edit "core:text/edit"
import "core:unicode/utf8"

Text_Edit :: struct {
	text:   strings.Builder,
	state:  edit.State,
	scroll: f32,
}

Text_Result :: struct {
	changed, submitted: bool,
}

create_text_edit :: proc(
	value: string = "",
	allocator := context.allocator,
) -> (
	Text_Edit,
	Error,
) {
	text: Text_Edit
	text.text = strings.builder_make(allocator)
	edit.init(&text.state, allocator, allocator)
	if err := set_text(&text, value); err != .None {
		destroy_text_edit(&text)
		return {}, err
	}

	return text, .None
}

set_text :: proc(text: ^Text_Edit, value: string) -> Error {
	if !utf8.valid_string(value) {
		return .Invalid_Value
	}

	if err := reserve(&text.text.buf, len(value)); err != nil {
		return .Allocation_Failed
	}

	edit.undo_clear(&text.state, &text.state.undo)
	edit.undo_clear(&text.state, &text.state.redo)
	strings.builder_reset(&text.text)
	for character in value {
		if character >= 32 && character != 127 {
			strings.write_rune(&text.text, character)
		}
	}

	text.state.selection = {len(text.text.buf), len(text.text.buf)}
	text.scroll = 0
	return .None
}

text_value :: proc(text: ^Text_Edit) -> string {
	return strings.to_string(text.text)
}

destroy_text_edit :: proc(text: ^Text_Edit) {
	edit.destroy(&text.state)
	strings.builder_destroy(&text.text)
	text^ = {}
}

text_field :: proc(
	ctx: ^Context,
	widget: ID,
	rect: Rect,
	text: ^Text_Edit,
	enabled := true,
) -> (
	Text_Result,
	Error,
) {
	if text == nil {
		return {}, .Invalid_Value
	}

	if err := validate_style(&ctx.style); err != .None {
		return {}, err
	}

	interaction, err := interact(ctx, widget, rect, enabled)
	if err != .None {
		return {}, err
	}

	text.state.builder = &text.text
	defer {
		text.state.builder = nil
	}
	edit.update_time(&text.state)
	for &index in text.state.selection {
		index = clamp(index, 0, len(text.text.buf))
	}

	content := inset_rect(
		rect,
		ctx.style.padding + [2]f32{ctx.style.border_width, ctx.style.border_width},
	)
	result: Text_Result
	if interaction.focused {
		shift := .Shift in input.current_modifiers(&ctx.raw_input)

		if interaction.held ||
		   (interaction.hovered && input.mouse_pressed(&ctx.raw_input, .Left)) {
			index := text_index(
				ctx,
				text_value(text),
				f32(ctx.pointer.x) - content.position.x + text.scroll,
			)
			text.state.selection[0] = index
			if input.mouse_pressed(&ctx.raw_input, .Left) && !shift {
				text.state.selection[1] = index
			}
		}

		if shortcut_action(ctx, .A) {
			text.state.selection = {len(text.text.buf), 0}
		}

		if (shortcut_action(ctx, .C) || shortcut_action(ctx, .X)) && ctx.clipboard.set != nil {
			lo, hi :=
				min(text.state.selection[0], text.state.selection[1]),
				max(text.state.selection[0], text.state.selection[1])
			if lo != hi &&
			   ctx.clipboard.set(ctx.clipboard.userdata, text_value(text)[lo:hi]) &&
			   key_action(ctx, .X) {
				edit.selection_delete(&text.state)
				result.changed = true
			}
		}

		if shortcut_action(ctx, .V) && ctx.clipboard.get != nil {
			if value, ok := ctx.clipboard.get(ctx.clipboard.userdata);
			   ok && utf8.valid_string(value) {
				if reserve(&text.text.buf, len(text.text.buf) + len(value)) != nil {
					return {}, .Allocation_Failed
				}

				for character in value {
					if character >= 32 && character != 127 {
						edit.input_rune(&text.state, character)
						result.changed = true
					}
				}
			}
		}

		if (shortcut_action(ctx, .Z) || shortcut_action(ctx, .Y)) {
			redo := .Shift in input.key_modifiers(&ctx.raw_input, .Z) || shortcut_action(ctx, .Y)
			if redo && len(text.state.redo) > 0 {
				edit.undo(&text.state, &text.state.redo, &text.state.undo)
				result.changed = true
			} else if !redo && len(text.state.undo) > 0 {
				edit.undo(&text.state, &text.state.undo, &text.state.redo)
				result.changed = true
			}
		}

		for key, i in ([4]input.Key{.Left, .Right, .Home, .End}) {
			if key_action(ctx, key) {
				move := edit.Translation.Start if i == 2 else edit.Translation.End
				if i < 2 {
					move = edit_translation(ctx, key, i == 1)
				}
				if .Shift in input.key_modifiers(&ctx.raw_input, key) {
					edit.select_to(&text.state, move)
				} else {
					edit.move_to(&text.state, move)
				}
			}
		}

		if key_action(ctx, .Backspace) || key_action(ctx, .Delete) {
			before := len(text.text.buf)
			key := input.Key.Backspace if key_action(ctx, .Backspace) else input.Key.Delete
			edit.delete_to(&text.state, edit_translation(ctx, key, key == .Delete))
			result.changed = result.changed || before != len(text.text.buf)
		}

		if len(ctx.raw_input.text) > 0 {
			if reserve(&text.text.buf, len(text.text.buf) + len(ctx.raw_input.text) * 4) != nil {
				return {}, .Allocation_Failed
			}

			edit.input_runes(&text.state, ctx.raw_input.text[:])
			result.changed = true
		}

		result.submitted = input.pressed(&ctx.raw_input, .Enter)
		if result.submitted {
			ctx.focus = 0
			ctx.navigation_used = true
		}
	}

	if err = control_frame(ctx, rect, interaction, enabled); err != .None {
		return {}, err
	}

	if err = draw_error(draw2d.push_clip(&ctx.draws, content)); err != .None {
		return {}, err
	}

	defer {
		draw2d.pop_clip(&ctx.draws)
	}
	value := text_value(text)
	head, _ := draw2d.measure_text(
		ctx.style.font,
		value[:text.state.selection[0]],
		ctx.style.font_size,
	)
	tail, _ := draw2d.measure_text(
		ctx.style.font,
		value[:text.state.selection[1]],
		ctx.style.font_size,
	)
	if interaction.focused {
		text.scroll = max(0, max(head.x - content.size.x + 1, min(text.scroll, head.x)))
	}

	line_height := ctx.style.font.line_height * ctx.style.font_size / ctx.style.font.em_size
	position := content.position - [2]f32{text.scroll, 0}
	position.y += math.floor((content.size.y - line_height) / 2)
	if interaction.focused && head.x != tail.x {
		if err = draw_error(
			draw2d.rectangle(
				&ctx.draws,
				{position + [2]f32{min(head.x, tail.x), 0}, {abs(head.x - tail.x), line_height}},
				ctx.style.active,
			),
		); err != .None {
			return {}, err
		}
	}

	color := ctx.style.text if enabled else ctx.style.disabled
	if err = draw_error(
		draw2d.text(&ctx.draws, ctx.style.font, value, position, ctx.style.font_size, color),
	); err != .None {
		return {}, err
	}

	if interaction.focused {
		if err = draw_error(
			draw2d.rectangle(
				&ctx.draws,
				{position + [2]f32{head.x, 0}, {1, line_height}},
				ctx.style.focus,
			),
		); err != .None {
			return {}, err
		}
	}

	return result, .None
}

@(private)
text_index :: proc(ctx: ^Context, value: string, x: f32) -> int {
	previous: f32
	for _, index in value {
		_, width := utf8.decode_rune_in_string(value[index:])
		size, _ := draw2d.measure_text(ctx.style.font, value[:index + width], ctx.style.font_size)
		if x < (previous + size.x) / 2 {
			return index
		}

		previous = size.x
	}

	return len(value)
}

@(private)
shortcut_action :: proc(ctx: ^Context, key: input.Key) -> bool {
	modifier := input.Modifier.Control
	when ODIN_OS == .Darwin {
		modifier = .Super
	}
	return key_action(ctx, key) && modifier in input.key_modifiers(&ctx.raw_input, key)
}

@(private)
edit_translation :: proc(ctx: ^Context, key: input.Key, forward: bool) -> edit.Translation {
	modifiers := input.key_modifiers(&ctx.raw_input, key)
	word := .Control in modifiers
	when ODIN_OS == .Darwin {
		if .Super in modifiers {
			return .End if forward else .Start
		}
		word = .Alt in modifiers
	}

	if word {
		return .Word_Right if forward else .Word_Left
	}
	return .Right if forward else .Left
}
