package renderer

import emath "../core/math"
import "../geometry"
import "../shaders"
import "core:math"

Tone_Mapping :: enum u32 {
	Reinhard,
	ACES_Fitted,
}

Presentation_Settings :: struct {
	exposure:       f32,
	tone_mapping:   Tone_Mapping,
	bloom_strength: f32,
}

@(private)
Presentation_Uniforms :: struct {
	exposure:       f32,
	tone_mapping:   Tone_Mapping,
	bloom_strength: f32,
	padding:        u32,
}

Presentation :: struct {
	pipeline: Pipeline,
	material: Material,
	mesh:     Mesh,
}

create_presentation :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
) -> (
	presentation: Presentation,
	err: Error,
) {
	program, shader_error := load_builtin_shader(library, .Presentation)
	if shader_error != .None {
		return {}, .Backend_Failed
	}

	presentation.pipeline, err = create_pipeline(
		renderer,
		program,
		{layout = VERTEX_LAYOUT, primitive = .Triangles},
		{{name = "source_texture", binding = 0}, {name = "bloom_texture", binding = 1}},
	)
	if err != .None {
		return
	}

	presentation.material, err = create_material(
		renderer,
		program,
		Presentation_Uniforms{exposure = 1},
	)
	if err != .None {
		destroy_presentation(renderer, &presentation)
		return
	}

	quad := geometry.create_quad()
	presentation.mesh, err = create_mesh(
		renderer,
		quad.vertices[:],
		quad.indices[:],
		VERTEX_LAYOUT,
		quad.bounds,
	)
	if err != .None {
		destroy_presentation(renderer, &presentation)
	}

	return
}

present :: proc(
	renderer: ^Renderer,
	presentation: ^Presentation,
	source: Texture,
	viewport: Viewport,
	settings := Presentation_Settings{exposure = 1},
	bloom: Texture = {},
) -> (
	err: Error,
) {
	if !(settings.exposure >= 0) ||
	   math.is_inf(settings.exposure) ||
	   !(settings.bloom_strength >= 0) ||
	   math.is_inf(settings.bloom_strength) ||
	   settings.tone_mapping < .Reinhard ||
	   settings.tone_mapping > .ACES_Fitted {
		return .Invalid_Draw
	}

	if err = set_material_texture(renderer, &presentation.material, 0, source); err != .None {
		return
	}

	if err = set_material_texture(
		renderer,
		&presentation.material,
		1,
		bloom if settings.bloom_strength > 0 else source,
	); err != .None {
		return
	}

	if err = update_material(
		renderer,
		&presentation.material,
		Presentation_Uniforms {
			exposure = settings.exposure,
			tone_mapping = settings.tone_mapping,
			bloom_strength = settings.bloom_strength,
		},
	); err != .None {
		return
	}

	if err = begin_pass(renderer, {viewport = viewport}, {0, 0, 0, 1}); err != .None {
		return
	}

	defer {
		end_error := end_pass(renderer)
		if err == .None {
			err = end_error
		}
	}

	if err = set_view(renderer, {orientation = 1}, emath.identity()); err != .None {
		return
	}

	return draw_mesh(
		renderer,
		&presentation.pipeline,
		&presentation.mesh,
		&presentation.material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

destroy_presentation :: proc(renderer: ^Renderer, presentation: ^Presentation) -> (result: Error) {
	if err := destroy_material(renderer, &presentation.material); err != .None {
		result = err
	}

	if err := destroy_pipeline(renderer, &presentation.pipeline); err != .None {
		result = err
	}

	if err := destroy_mesh(renderer, &presentation.mesh); err != .None {
		result = err
	}

	return
}

pixel_viewport :: proc(source, framebuffer: [2]i32) -> Viewport {
	if source.x <= 0 || source.y <= 0 || framebuffer.x <= 0 || framebuffer.y <= 0 {
		return {}
	}

	scale := min(f64(framebuffer.x) / f64(source.x), f64(framebuffer.y) / f64(source.y))
	if scale >= 1 {
		scale = math.floor(scale)
	}

	width := max(1, i32(f64(source.x) * scale))
	height := max(1, i32(f64(source.y) * scale))
	return {
		x = (framebuffer.x - width) / 2,
		y = (framebuffer.y - height) / 2,
		width = width,
		height = height,
	}
}
