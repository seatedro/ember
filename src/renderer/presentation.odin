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
	exposure:     f32,
	tone_mapping: Tone_Mapping,
}

@(private)
Presentation_Uniforms :: struct {
	exposure:     f32,
	tone_mapping: Tone_Mapping,
	padding:      [2]u32,
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
		{{name = "source_texture", binding = 0}},
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
) -> (
	err: Error,
) {
	if !(settings.exposure >= 0) ||
	   math.is_inf(settings.exposure) ||
	   settings.tone_mapping < .Reinhard ||
	   settings.tone_mapping > .ACES_Fitted {
		return .Invalid_Draw
	}

	if err = set_material_texture(renderer, &presentation.material, 0, source); err != .None {
		return
	}

	if err = update_material(
		renderer,
		&presentation.material,
		Presentation_Uniforms{exposure = settings.exposure, tone_mapping = settings.tone_mapping},
	); err != .None {
		return
	}

	if err = begin_pass(renderer, {viewport = viewport}); err != .None {
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
