package draw2d

import "../rhi"
import "core:testing"

@(test)
test_clip_order_and_scale :: proc(t: ^testing.T) {
	list := create_list()
	defer destroy_list(&list)
	testing.expect(t, reset(&list, {200, 100}) == .None)
	testing.expect(t, rectangle(&list, {{0, 0}, {100, 100}}, {1, 0, 0, 0.5}) == .None)
	testing.expect(t, rectangle(&list, {{25, 0}, {100, 100}}, {0, 1, 0, 0.5}) == .None)
	testing.expect_value(t, len(list.batches), 1)
	testing.expect_value(t, list.batches[0].index_count, 12)
	testing.expect_value(t, list.vertices[0].color, ([4]f32{1, 0, 0, 0.5}))
	testing.expect_value(t, list.vertices[4].color, ([4]f32{0, 1, 0, 0.5}))
	testing.expect(t, push_clip(&list, {{10, 20}, {80, 70}}) == .None)
	testing.expect(t, push_clip(&list, {{50, 10}, {80, 40}}) == .None)
	testing.expect(t, rectangle(&list, {{0, 0}, {200, 100}}, {1, 1, 1, 1}) == .None)
	clip := list.batches[1].clip
	testing.expect_value(t, clip, (Rect{{50, 20}, {40, 30}}))
	testing.expect_value(
		t,
		scissor(clip, list.size, {x = 7, y = 11, width = 400, height = 200}),
		(rhi.Scissor{enabled = true, x = 107, y = 111, width = 80, height = 60}),
	)
	testing.expect(t, push_clip(&list, {{150, 90}, {10, 10}}) == .None)
	testing.expect(t, rectangle(&list, {{0, 0}, {200, 100}}, {1, 1, 1, 1}) == .None)
	testing.expect_value(t, len(list.vertices), 12)
	for _ in 0 ..< 3 {
		testing.expect(t, pop_clip(&list) == .None)
	}

	testing.expect(t, pop_clip(&list) == .Invalid_Draw)
	testing.expect(t, rectangle(&list, {{0, 0}, {20, 20}}, {1, 1, 1, 1}) == .None)
	testing.expect_value(t, len(list.batches), 3)
	testing.expect_value(t, list.batches[2].first_index, 18)
}

@(test)
test_font_metrics_and_fallback :: proc(t: ^testing.T) {
	font, err := parse_font(transmute([]u8)#load("../../assets/fonts/press-start-2p.json", string))
	testing.expect(t, err == .None)
	if err != .None {
		return
	}

	defer destroy_font(nil, &font)
	font.texture = {
		generation = 1,
	}
	defer {
		font.texture = {}
	}

	font.kerning[{'A', 'V'}] = -0.125
	list := create_list()
	defer destroy_list(&list)
	testing.expect(t, reset(&list, {1000, 1000}) == .None)
	testing.expect(t, text(&list, &font, "AV\n?", {12, 20}, 32) == .None)
	testing.expect_value(t, len(list.vertices), 12)
	a := font.glyphs['A']
	v := font.glyphs['V']
	scale := f32(32) / font.em_size
	testing.expect_value(
		t,
		list.vertices[4].position.x,
		12 + (a.advance + font.kerning[{'A', 'V'}]) * scale + v.plane.position.x * scale,
	)
	size, measure_error := measure_text(&font, "AV\n?", 32)
	testing.expect(t, measure_error == .None)
	testing.expect_value(t, size.y, 2 * font.line_height * scale)
	larger, _ := measure_text(&font, "AV\n?", 64)
	testing.expect_value(t, larger, size * 2)
	fallback, _ := measure_text(&font, "🪐", 32)
	question, _ := measure_text(&font, "?", 32)
	testing.expect_value(t, fallback, question)
	glyph := font.glyphs['A']
	testing.expect(t, glyph.uv_min.y < glyph.uv_max.y)
	testing.expect(t, glyph.plane.position.y < 0)
}

@(test)
test_invalid_font_and_empty_list :: proc(t: ^testing.T) {
	font, err := parse_font(transmute([]u8)string(`{"atlas":{"type":"msdf"},"glyphs":[]}`))
	testing.expect(t, err == .Invalid_Data)
	testing.expect_value(t, len(font.glyphs), 0)
	list := create_list()
	defer destroy_list(&list)
	testing.expect(t, reset(&list, {0, 100}) == .Invalid_Size)
	testing.expect(t, rectangle(&list, {{0, 0}, {10, 10}}, {1, 1, 1, 1}) == .Invalid_Draw)
	testing.expect(t, reset(&list, {100, 100}) == .None)
	testing.expect(t, quad(&list, {{0, 0}, {-1, 10}}, {}) == .Invalid_Draw)
	testing.expect_value(t, len(list.indices), 0)
}

@(test)
test_font_origins_and_rejected_glyph :: proc(t: ^testing.T) {
	top := string(
		`{"atlas":{"type":"msdf","distanceRange":4,"width":64,"height":64,"yOrigin":"top"},"metrics":{"emSize":1,"lineHeight":1.2,"ascender":-0.9},"glyphs":[{"unicode":65,"advance":0.6,"planeBounds":{"left":0,"top":-0.8,"right":0.6,"bottom":0},"atlasBounds":{"left":4,"top":8,"right":24,"bottom":40}}]}`,
	)
	bottom := string(
		`{"atlas":{"type":"msdf","distanceRange":4,"width":64,"height":64,"yOrigin":"bottom"},"metrics":{"emSize":1,"lineHeight":1.2,"ascender":0.9},"glyphs":[{"unicode":65,"advance":0.6,"planeBounds":{"left":0,"top":0.8,"right":0.6,"bottom":0},"atlasBounds":{"left":4,"top":56,"right":24,"bottom":24}}]}`,
	)
	a, a_error := parse_font(transmute([]u8)top)
	defer destroy_font(nil, &a)
	b, b_error := parse_font(transmute([]u8)bottom)
	defer destroy_font(nil, &b)
	testing.expect(t, a_error == .None && b_error == .None)
	testing.expect_value(t, a.glyphs['A'], b.glyphs['A'])
	testing.expect_value(t, a.ascender, b.ascender)
	invalid := string(
		`{"atlas":{"type":"msdf","distanceRange":4,"width":64,"height":64,"yOrigin":"top"},"metrics":{"emSize":1,"lineHeight":1.2,"ascender":-0.9},"glyphs":[{"unicode":1114112,"advance":0.6}]}`,
	)
	font, err := parse_font(transmute([]u8)invalid)
	testing.expect(t, err == .Invalid_Data && len(font.glyphs) == 0)
}
