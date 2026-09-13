package input

import "core:testing"

@(test)
test_text_repeat_and_modifier_snapshot :: proc(t: ^testing.T) {
	state: State
	init(&state, true)
	defer destroy(&state)
	record_key(&state, .A, true, {.Super})
	record_key(&state, .A, false)
	testing.expect(t, pressed(&state, .A) && released(&state, .A))
	testing.expect(t, .Super in key_modifiers(&state, .A) && current_modifiers(&state) == {})
	record_text(&state, 'λ')
	record_text(&state, rune(0xd800))
	testing.expect_value(t, len(state.text), 1)
	clear(&state)
	testing.expect(t, len(state.text) == 0 && !pressed(&state, .A))
	record_key(&state, .Backspace, true)
	clear(&state)
	record_repeat(&state, .Backspace, {.Alt})
	testing.expect(t, state.keys[.Backspace].repeated && !pressed(&state, .Backspace))
	testing.expect(t, .Alt in key_modifiers(&state, .Backspace))
	record_text(&state, 'x')
	record_focus(&state, false)
	testing.expect(t, len(state.text) == 0 && !state.keys[.Backspace].repeated)
	record_text(&state, 'y')
	testing.expect_value(t, len(state.text), 0)
}
