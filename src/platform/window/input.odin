package window

import "../../input"
import "core:strings"
import "vendor:glfw"

@(private)
init_input :: proc(window: ^Window) {
	x, y := glfw.GetCursorPos(window.handle)
	focused := glfw.GetWindowAttrib(window.handle, glfw.FOCUSED) != 0
	input.init(&window.input, focused, {x, y})
	glfw.SetKeyCallback(window.handle, key_callback)
	glfw.SetCharCallback(window.handle, text_callback)
	glfw.SetMouseButtonCallback(window.handle, mouse_button_callback)
	glfw.SetCursorPosCallback(window.handle, cursor_position_callback)
	glfw.SetScrollCallback(window.handle, scroll_callback)
	glfw.SetWindowFocusCallback(window.handle, focus_callback)
}

@(private)
key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window == nil {
		return
	}

	if action == glfw.REPEAT {
		input.record_repeat(&window.input, translate_key(key), translate_modifiers(mods))
	} else if action == glfw.PRESS || action == glfw.RELEASE {
		input.record_key(
			&window.input,
			translate_key(key),
			action == glfw.PRESS,
			translate_modifiers(mods),
		)
	}
}

@(private)
mouse_button_callback :: proc "c" (handle: glfw.WindowHandle, button, action, mods: i32) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window == nil || (action != glfw.PRESS && action != glfw.RELEASE) {
		return
	}
	translated, valid := translate_mouse_button(button)
	if valid {
		input.record_mouse_button(&window.input, translated, action == glfw.PRESS)
	}
}

@(private)
cursor_position_callback :: proc "c" (handle: glfw.WindowHandle, x, y: f64) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window != nil {
		input.record_cursor(&window.input, {x, y})
	}
}

@(private)
scroll_callback :: proc "c" (handle: glfw.WindowHandle, x, y: f64) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window != nil {
		input.record_scroll(&window.input, {x, y})
	}
}

@(private)
focus_callback :: proc "c" (handle: glfw.WindowHandle, focused: i32) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window != nil {
		input.record_focus(&window.input, focused != 0)
	}
}

@(private)
translate_key :: proc(key: i32) -> input.Key {
	if key < 0 || key >= len(KEY_MAP) {
		return .Unknown
	}
	return KEY_MAP[key]
}

@(private)
translate_mouse_button :: proc(button: i32) -> (input.Mouse_Button, bool) {
	buttons := [8]input.Mouse_Button {
		.Left,
		.Right,
		.Middle,
		.Button_4,
		.Button_5,
		.Button_6,
		.Button_7,
		.Button_8,
	}
	if button < 0 || button >= len(buttons) {
		return {}, false
	}
	return buttons[button], true
}

@(private)
KEY_MAP := [glfw.KEY_LAST + 1]input.Key {
	glfw.KEY_SPACE         = .Space,
	glfw.KEY_APOSTROPHE    = .Apostrophe,
	glfw.KEY_COMMA         = .Comma,
	glfw.KEY_MINUS         = .Minus,
	glfw.KEY_PERIOD        = .Period,
	glfw.KEY_SLASH         = .Slash,
	glfw.KEY_SEMICOLON     = .Semicolon,
	glfw.KEY_EQUAL         = .Equal,
	glfw.KEY_LEFT_BRACKET  = .Left_Bracket,
	glfw.KEY_BACKSLASH     = .Backslash,
	glfw.KEY_RIGHT_BRACKET = .Right_Bracket,
	glfw.KEY_GRAVE_ACCENT  = .Grave_Accent,
	glfw.KEY_WORLD_1       = .World_1,
	glfw.KEY_WORLD_2       = .World_2,
	glfw.KEY_0             = .Digit_0,
	glfw.KEY_1             = .Digit_1,
	glfw.KEY_2             = .Digit_2,
	glfw.KEY_3             = .Digit_3,
	glfw.KEY_4             = .Digit_4,
	glfw.KEY_5             = .Digit_5,
	glfw.KEY_6             = .Digit_6,
	glfw.KEY_7             = .Digit_7,
	glfw.KEY_8             = .Digit_8,
	glfw.KEY_9             = .Digit_9,
	glfw.KEY_A             = .A,
	glfw.KEY_B             = .B,
	glfw.KEY_C             = .C,
	glfw.KEY_D             = .D,
	glfw.KEY_E             = .E,
	glfw.KEY_F             = .F,
	glfw.KEY_G             = .G,
	glfw.KEY_H             = .H,
	glfw.KEY_I             = .I,
	glfw.KEY_J             = .J,
	glfw.KEY_K             = .K,
	glfw.KEY_L             = .L,
	glfw.KEY_M             = .M,
	glfw.KEY_N             = .N,
	glfw.KEY_O             = .O,
	glfw.KEY_P             = .P,
	glfw.KEY_Q             = .Q,
	glfw.KEY_R             = .R,
	glfw.KEY_S             = .S,
	glfw.KEY_T             = .T,
	glfw.KEY_U             = .U,
	glfw.KEY_V             = .V,
	glfw.KEY_W             = .W,
	glfw.KEY_X             = .X,
	glfw.KEY_Y             = .Y,
	glfw.KEY_Z             = .Z,
	glfw.KEY_ESCAPE        = .Escape,
	glfw.KEY_ENTER         = .Enter,
	glfw.KEY_TAB           = .Tab,
	glfw.KEY_BACKSPACE     = .Backspace,
	glfw.KEY_INSERT        = .Insert,
	glfw.KEY_DELETE        = .Delete,
	glfw.KEY_RIGHT         = .Right,
	glfw.KEY_LEFT          = .Left,
	glfw.KEY_DOWN          = .Down,
	glfw.KEY_UP            = .Up,
	glfw.KEY_PAGE_UP       = .Page_Up,
	glfw.KEY_PAGE_DOWN     = .Page_Down,
	glfw.KEY_HOME          = .Home,
	glfw.KEY_END           = .End,
	glfw.KEY_CAPS_LOCK     = .Caps_Lock,
	glfw.KEY_SCROLL_LOCK   = .Scroll_Lock,
	glfw.KEY_NUM_LOCK      = .Num_Lock,
	glfw.KEY_PRINT_SCREEN  = .Print_Screen,
	glfw.KEY_PAUSE         = .Pause,
	glfw.KEY_F1            = .F1,
	glfw.KEY_F2            = .F2,
	glfw.KEY_F3            = .F3,
	glfw.KEY_F4            = .F4,
	glfw.KEY_F5            = .F5,
	glfw.KEY_F6            = .F6,
	glfw.KEY_F7            = .F7,
	glfw.KEY_F8            = .F8,
	glfw.KEY_F9            = .F9,
	glfw.KEY_F10           = .F10,
	glfw.KEY_F11           = .F11,
	glfw.KEY_F12           = .F12,
	glfw.KEY_F13           = .F13,
	glfw.KEY_F14           = .F14,
	glfw.KEY_F15           = .F15,
	glfw.KEY_F16           = .F16,
	glfw.KEY_F17           = .F17,
	glfw.KEY_F18           = .F18,
	glfw.KEY_F19           = .F19,
	glfw.KEY_F20           = .F20,
	glfw.KEY_F21           = .F21,
	glfw.KEY_F22           = .F22,
	glfw.KEY_F23           = .F23,
	glfw.KEY_F24           = .F24,
	glfw.KEY_F25           = .F25,
	glfw.KEY_KP_0          = .Keypad_0,
	glfw.KEY_KP_1          = .Keypad_1,
	glfw.KEY_KP_2          = .Keypad_2,
	glfw.KEY_KP_3          = .Keypad_3,
	glfw.KEY_KP_4          = .Keypad_4,
	glfw.KEY_KP_5          = .Keypad_5,
	glfw.KEY_KP_6          = .Keypad_6,
	glfw.KEY_KP_7          = .Keypad_7,
	glfw.KEY_KP_8          = .Keypad_8,
	glfw.KEY_KP_9          = .Keypad_9,
	glfw.KEY_KP_DECIMAL    = .Keypad_Decimal,
	glfw.KEY_KP_DIVIDE     = .Keypad_Divide,
	glfw.KEY_KP_MULTIPLY   = .Keypad_Multiply,
	glfw.KEY_KP_SUBTRACT   = .Keypad_Subtract,
	glfw.KEY_KP_ADD        = .Keypad_Add,
	glfw.KEY_KP_ENTER      = .Keypad_Enter,
	glfw.KEY_KP_EQUAL      = .Keypad_Equal,
	glfw.KEY_LEFT_SHIFT    = .Left_Shift,
	glfw.KEY_LEFT_CONTROL  = .Left_Control,
	glfw.KEY_LEFT_ALT      = .Left_Alt,
	glfw.KEY_LEFT_SUPER    = .Left_Super,
	glfw.KEY_RIGHT_SHIFT   = .Right_Shift,
	glfw.KEY_RIGHT_CONTROL = .Right_Control,
	glfw.KEY_RIGHT_ALT     = .Right_Alt,
	glfw.KEY_RIGHT_SUPER   = .Right_Super,
	glfw.KEY_MENU          = .Menu,
}

@(private)
text_callback :: proc "c" (handle: glfw.WindowHandle, character: rune) {
	context = glfw_callback_context
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window != nil {
		input.record_text(&window.input, character)
	}
}

clipboard :: proc(window: ^Window) -> input.Clipboard {
	return {get = get_clipboard, set = set_clipboard, userdata = rawptr(window.handle)}
}

@(private)
get_clipboard :: proc(userdata: rawptr) -> (string, bool) {
	value := glfw.GetClipboardString(cast(glfw.WindowHandle)userdata)
	return value, true
}

@(private)
set_clipboard :: proc(userdata: rawptr, value: string) -> bool {
	text, err := strings.clone_to_cstring(value)
	if err != nil {
		return false
	}

	defer {
		delete(text)
	}
	glfw.SetClipboardString(cast(glfw.WindowHandle)userdata, text)
	return true
}

@(private)
translate_modifiers :: proc(mods: i32) -> input.Modifiers {
	result: input.Modifiers
	if mods & glfw.MOD_SHIFT != 0 {
		result += {.Shift}
	}
	if mods & glfw.MOD_CONTROL != 0 {
		result += {.Control}
	}
	if mods & glfw.MOD_ALT != 0 {
		result += {.Alt}
	}
	if mods & glfw.MOD_SUPER != 0 {
		result += {.Super}
	}
	return result
}
