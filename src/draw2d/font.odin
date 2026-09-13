package draw2d

import "../image"
import "../rhi"
import "core:encoding/json"
import "core:mem"
import "core:os"

Font :: struct {
	texture:                        rhi.Texture_Handle,
	atlas_size:                     [2]i32,
	glyphs:                         map[rune]Glyph,
	kerning:                        map[[2]rune]f32,
	em_size, line_height, ascender: f32,
	distance_range:                 f32,
}

Glyph :: struct {
	advance:        f32,
	plane:          Rect,
	uv_min, uv_max: [2]f32,
}

Font_Error :: enum {
	None,
	Read_Failed,
	Invalid_Data,
	Allocation_Failed,
	Texture_Failed,
}

@(private)
Bounds :: struct {
	left, bottom, right, top: f32,
}

@(private)
Font_Data :: struct {
	atlas:   struct {
		kind:            string `json:"type"`,
		distance_range:  f32 `json:"distanceRange"`,
		distance_middle: f32 `json:"distanceRangeMiddle"`,
		width, height:   i32,
		y_origin:        string `json:"yOrigin"`,
	},
	metrics: struct {
		em_size:     f32 `json:"emSize"`,
		line_height: f32 `json:"lineHeight"`,
		ascender:    f32,
	},
	glyphs:  []struct {
		unicode: i64,
		advance: f32,
		plane:   Bounds `json:"planeBounds"`,
		atlas:   Bounds `json:"atlasBounds"`,
	},
	kerning: []struct {
		unicode1, unicode2: i64,
		advance:            f32,
	},
}

load_font :: proc(device: ^rhi.Device, metrics_path, image_path: string) -> (Font, Font_Error) {
	font: Font
	err: Font_Error
	source, read_error := os.read_entire_file(metrics_path, context.allocator)
	defer delete(source)
	if read_error != nil {
		return {}, .Read_Failed
	}

	font, err = parse_font(source)
	if err != .None {
		return {}, err
	}

	success := false
	defer {
		if !success {
			destroy_font(device, &font)
		}
	}

	atlas, image_error := image.load(image_path)
	if image_error != .None {
		return {}, .Read_Failed
	}

	defer image.destroy(&atlas)
	if atlas.width != font.atlas_size.x || atlas.height != font.atlas_size.y {
		return {}, .Invalid_Data
	}

	texture_error: rhi.Error
	font.texture, texture_error = rhi.create_texture(
		device,
		{
			width = atlas.width,
			height = atlas.height,
			format = .RGBA8,
			filter = .Linear,
			wrap_u = .Clamp,
			wrap_v = .Clamp,
			label = metrics_path,
		},
		atlas.pixels,
	)
	if texture_error != .None {
		return {}, .Texture_Failed
	}

	success = true
	return font, .None
}

@(private)
parse_font :: proc(source: []u8) -> (Font, Font_Error) {
	font: Font
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	data: Font_Data
	if json.unmarshal(source, &data, allocator = mem.dynamic_arena_allocator(&arena)) != nil {
		return {}, .Invalid_Data
	}

	if (data.atlas.kind != "msdf" && data.atlas.kind != "mtsdf") ||
	   (data.atlas.y_origin != "top" && data.atlas.y_origin != "bottom") ||
	   data.atlas.width <= 0 ||
	   data.atlas.height <= 0 ||
	   !finite(data.atlas.distance_range) ||
	   data.atlas.distance_range <= 0 ||
	   data.atlas.distance_middle != 0 ||
	   !finite(data.metrics.em_size) ||
	   data.metrics.em_size <= 0 ||
	   !finite(data.metrics.line_height) ||
	   data.metrics.line_height <= 0 ||
	   !finite(data.metrics.ascender) ||
	   len(data.glyphs) == 0 {
		return {}, .Invalid_Data
	}

	allocation_error: mem.Allocator_Error
	font.glyphs, allocation_error = make(map[rune]Glyph, len(data.glyphs))
	if allocation_error != nil {
		return {}, .Allocation_Failed
	}

	font.kerning, allocation_error = make(map[[2]rune]f32, len(data.kerning))
	if allocation_error != nil {
		delete(font.glyphs)
		return {}, .Allocation_Failed
	}

	success := false
	defer {
		if !success {
			delete(font.glyphs)
			delete(font.kerning)
		}
	}

	font.atlas_size = {data.atlas.width, data.atlas.height}
	font.em_size = data.metrics.em_size
	font.line_height = data.metrics.line_height
	font.ascender = data.metrics.ascender
	font.distance_range = data.atlas.distance_range
	bottom_up := data.atlas.y_origin == "bottom"
	if !bottom_up {
		font.ascender = -font.ascender
	}

	width, height := f32(data.atlas.width), f32(data.atlas.height)
	for entry in data.glyphs {
		if entry.unicode < 0 ||
		   entry.unicode > 0x10ffff ||
		   (entry.unicode >= 0xd800 && entry.unicode <= 0xdfff) ||
		   !finite(entry.advance) {
			return {}, .Invalid_Data
		}

		if _, exists := font.glyphs[rune(entry.unicode)]; exists {
			return {}, .Invalid_Data
		}

		p, a := entry.plane, entry.atlas
		if bottom_up {
			p.top, p.bottom = -p.top, -p.bottom
			a.top, a.bottom = height - a.top, height - a.bottom
		}

		plane := Rect {
			position = {p.left, p.top},
			size     = {p.right - p.left, p.bottom - p.top},
		}
		atlas := Rect {
			position = {a.left, a.top},
			size     = {a.right - a.left, a.bottom - a.top},
		}
		if !valid_rect(plane) ||
		   !valid_rect(atlas) ||
		   a.left < 0 ||
		   a.top < 0 ||
		   a.right > width ||
		   a.bottom > height {
			return {}, .Invalid_Data
		}

		font.glyphs[rune(entry.unicode)] = {
			advance = entry.advance,
			plane   = plane,
			uv_min  = {a.left / width, a.top / height},
			uv_max  = {a.right / width, a.bottom / height},
		}
	}

	for pair in data.kerning {
		if !finite(pair.advance) ||
		   pair.unicode1 < 0 ||
		   pair.unicode1 > 0x10ffff ||
		   pair.unicode2 < 0 ||
		   pair.unicode2 > 0x10ffff {
			return {}, .Invalid_Data
		}

		font.kerning[{rune(pair.unicode1), rune(pair.unicode2)}] = pair.advance
	}

	success = true
	return font, .None
}

text :: proc(
	list: ^List,
	font: ^Font,
	value: string,
	position: [2]f32,
	size: f32,
	color: [4]f32 = {1, 1, 1, 1},
) -> Error {
	if font.texture.generation == 0 ||
	   len(list.clips) == 0 ||
	   !finite(position.x) ||
	   !finite(position.y) {
		return .Invalid_Draw
	}

	_, err := layout_text(font, value, size, list, position, color)
	return err
}

measure_text :: proc(font: ^Font, value: string, size: f32) -> ([2]f32, Error) {
	return layout_text(font, value, size, nil, {}, {})
}

@(private)
layout_text :: proc(
	font: ^Font,
	value: string,
	size: f32,
	list: ^List,
	position: [2]f32,
	color: [4]f32,
) -> (
	[2]f32,
	Error,
) {
	if !finite(size) || size <= 0 || font.em_size <= 0 {
		return {}, .Invalid_Size
	}

	if len(value) == 0 {
		return {}, .None
	}

	scale := size / font.em_size
	pen: [2]f32
	width: f32
	previous: rune
	for character in value {
		codepoint := character
		if codepoint == '\r' {
			continue
		}

		if codepoint == '\n' {
			width = max(width, pen.x)
			pen.x = 0
			pen.y += font.line_height * scale
			previous = 0
			continue
		}

		if codepoint == '\t' {
			space := font.glyphs[' ']
			pen.x += space.advance * scale * 4
			previous = 0
			continue
		}

		glyph, found := font.glyphs[codepoint]
		if !found {
			codepoint = '?'
			glyph, found = font.glyphs[codepoint]
			if !found {
				return {}, .Invalid_Draw
			}
		}

		pen.x += font.kerning[{previous, codepoint}] * scale
		if list != nil && glyph.plane.size.x > 0 && glyph.plane.size.y > 0 {
			rect := Rect {
				position = position + pen + [2]f32{0, font.ascender * scale} + glyph.plane.position * scale,
				size     = glyph.plane.size * scale,
			}
			if err := append_quad(
				list,
				rect,
				font.texture,
				color,
				glyph.uv_min,
				glyph.uv_max,
				font.distance_range,
			); err != .None {
				return {}, err
			}
		}

		pen.x += glyph.advance * scale
		previous = codepoint
	}

	return {max(width, pen.x), pen.y + font.line_height * scale}, .None
}

destroy_font :: proc(device: ^rhi.Device, font: ^Font) -> Error {
	if font.texture.generation != 0 {
		if err := rhi.destroy_texture(device, font.texture); err != .None {
			return err
		}
	}

	delete(font.glyphs)
	delete(font.kerning)
	font^ = {}
	return .None
}
