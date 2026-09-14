package window

import "../../input"
import "vendor:glfw"

set_cursor :: proc(window: ^Window, requested: input.Cursor) {
	cursor := requested
	if !window.input.focused || cursor < .Arrow || cursor > .Move {
		cursor = .Arrow
	}
	if cursor == window.cursor {
		return
	}

	if cursor != .Arrow && window.cursors[cursor] == nil {
		shapes := [input.Cursor]i32 {
			.Arrow             = glfw.ARROW_CURSOR,
			.Resize_Horizontal = glfw.RESIZE_EW_CURSOR,
			.Resize_Vertical   = glfw.RESIZE_NS_CURSOR,
			.Resize_NW_SE      = glfw.RESIZE_NWSE_CURSOR,
			.Resize_NE_SW      = glfw.RESIZE_NESW_CURSOR,
			.Move              = glfw.RESIZE_ALL_CURSOR,
		}
		window.cursors[cursor] = glfw.CreateStandardCursor(shapes[cursor])
	}
	glfw.SetCursor(window.handle, window.cursors[cursor])
	window.cursor = cursor
}
