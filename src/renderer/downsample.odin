package renderer

import emath "../core/math"
import "../geometry"
import "../rhi"
import "../shaders"

Downsample :: struct {
	pipeline: Pipeline,
	material: Material,
	mesh:     Mesh,
}

@(private)
Downsample_Uniforms :: struct {
	scale:   [2]i32,
	padding: [2]u32,
}

create_downsample :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
) -> (
	filter: Downsample,
	err: Error,
) {
	program, shader_error := load_builtin_shader(library, .Downsample)
	if shader_error != .None {
		return {}, .Backend_Failed
	}

	defer {
		if err != .None {
			destroy_downsample(renderer, &filter)
		}
	}

	filter.pipeline, err = create_pipeline(
		renderer,
		program,
		{layout = VERTEX_LAYOUT},
		{{name = "source_texture", binding = 0}},
	)
	if err != .None {
		return
	}

	filter.material, err = create_material(renderer, program, Downsample_Uniforms{})
	if err != .None {
		return
	}

	quad := geometry.create_quad()
	filter.mesh, err = create_mesh(
		renderer,
		quad.vertices[:],
		quad.indices[:],
		VERTEX_LAYOUT,
		quad.bounds,
	)
	return
}

// Average complete source texel blocks in linear color before tone mapping.
downsample :: proc(
	renderer: ^Renderer,
	filter: ^Downsample,
	source: Render_Target,
	target: ^Render_Target,
) -> (
	err: Error,
) {
	if target == nil ||
	   source.width <= 0 ||
	   source.height <= 0 ||
	   target.width <= 0 ||
	   target.height <= 0 {
		return .Invalid_Size
	}

	if source.width % target.width != 0 || source.height % target.height != 0 {
		return .Invalid_Size
	}

	color, color_error := rhi.render_target_color(renderer.device, source.handle)
	if color_error != .None {
		return color_error
	}

	if source.color.handle != color {
		return .Invalid_Draw
	}

	if source.handle == target.handle {
		return .Feedback_Loop
	}

	if renderer.device.pass_active {
		return .Invalid_Pass
	}

	if err = set_material_texture(renderer, &filter.material, 0, source.color); err != .None {
		return
	}

	if err = update_material(
		renderer,
		&filter.material,
		Downsample_Uniforms{scale = {source.width / target.width, source.height / target.height}},
	); err != .None {
		return
	}

	if err = set_view(renderer, {orientation = 1}, emath.identity()); err != .None {
		return
	}

	if err = begin_pass(renderer, {target = target}); err != .None {
		return
	}

	defer {
		end_error := end_pass(renderer)
		if err == .None {
			err = end_error
		}
	}

	return draw_mesh(
		renderer,
		&filter.pipeline,
		&filter.mesh,
		&filter.material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

destroy_downsample :: proc(renderer: ^Renderer, filter: ^Downsample) -> (result: Error) {
	if err := destroy_material(renderer, &filter.material); err != .None {
		result = err
	}

	if err := destroy_pipeline(renderer, &filter.pipeline); err != .None {
		result = err
	}

	if err := destroy_mesh(renderer, &filter.mesh); err != .None {
		result = err
	}

	return
}
