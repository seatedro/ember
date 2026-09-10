package window

import "../../input"
import "core:testing"
import "vendor:glfw"

@(test)
test_key_translation_coverage :: proc(t: ^testing.T) {
	seen: [input.Key]bool
	for native in 0 ..< len(KEY_MAP) {
		key := translate_key(i32(native))
		if key != .Unknown {
			testing.expect(t, !seen[key])
			seen[key] = true
		}
	}
	for key in input.Key {
		if key != .Unknown {
			testing.expect(t, seen[key])
		}
	}
	testing.expect_value(t, translate_key(glfw.KEY_SPACE), input.Key.Space)
	testing.expect_value(t, translate_key(glfw.KEY_A), input.Key.A)
	testing.expect_value(t, translate_key(glfw.KEY_0), input.Key.Digit_0)
	testing.expect_value(t, translate_key(glfw.KEY_LEFT_CONTROL), input.Key.Left_Control)
	testing.expect_value(t, translate_key(glfw.KEY_KP_ENTER), input.Key.Keypad_Enter)
	testing.expect_value(t, translate_key(glfw.KEY_APOSTROPHE), input.Key.Apostrophe)
	testing.expect_value(t, translate_key(glfw.KEY_UNKNOWN), input.Key.Unknown)
	testing.expect_value(t, translate_key(10000), input.Key.Unknown)
	testing.expect_value(t, translate_key(200), input.Key.Unknown)
}

@(test)
test_mouse_translation_bounds :: proc(t: ^testing.T) {
	left, valid := translate_mouse_button(glfw.MOUSE_BUTTON_LEFT)
	testing.expect(t, valid && left == .Left)
	right, right_valid := translate_mouse_button(glfw.MOUSE_BUTTON_RIGHT)
	testing.expect(t, right_valid && right == .Right)
	last, last_valid := translate_mouse_button(glfw.MOUSE_BUTTON_8)
	testing.expect(t, last_valid && last == .Button_8)
	_, negative := translate_mouse_button(-1)
	_, too_large := translate_mouse_button(8)
	testing.expect(t, !negative && !too_large)
}
