package renderer

import emath "../core/math"
import "../geometry"
import "../rhi"
import "../shaders"

Bloom_Settings :: struct {
	threshold, softness: f32,
}

Bloom :: struct {
	pipeline, upsample_pipeline: Pipeline,
	material:                    Material,
	mesh:                        Mesh,
	targets, pending_targets:    [dynamic]Render_Target,
	width, height:               i32,
}

@(private)
Bloom_Mode :: enum u32 {
	Prefilter,
	Downsample,
	Upsample,
}

@(private)
Bloom_Uniforms :: struct {
	threshold, knee: f32,
	mode:            Bloom_Mode,
	level_weight:    f32,
}

create_bloom :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
	allocator := context.allocator,
) -> (
	bloom: Bloom,
	err: Error,
) {
	bloom.targets = make([dynamic]Render_Target, allocator)
	bloom.pending_targets = make([dynamic]Render_Target, allocator)
	program, shader_error := load_builtin_shader(library, .Bloom)
	if shader_error != .None {
		err = .Backend_Failed
		return
	}

	bloom.pipeline, err = create_pipeline(
		renderer,
		program,
		{layout = VERTEX_LAYOUT},
		{{name = "source_texture", binding = 0}},
	)
	if err != .None {
		return
	}

	bloom.upsample_pipeline, err = create_pipeline(
		renderer,
		program,
		{
			layout = VERTEX_LAYOUT,
			blend = {
				enabled = true,
				src_factor_rgb = .One,
				dst_factor_rgb = .One,
				dst_factor_alpha = .One,
			},
		},
		{{name = "source_texture", binding = 0}},
	)
	if err != .None {
		destroy_bloom(renderer, &bloom)
		return
	}

	bloom.material, err = create_material(renderer, program, Bloom_Uniforms{})
	if err != .None {
		destroy_bloom(renderer, &bloom)
		return
	}

	quad := geometry.create_quad()
	bloom.mesh, err = create_mesh(
		renderer,
		quad.vertices[:],
		quad.indices[:],
		VERTEX_LAYOUT,
		quad.bounds,
	)
	if err != .None {
		destroy_bloom(renderer, &bloom)
	}
	return
}

apply_bloom :: proc(
	renderer: ^Renderer,
	bloom: ^Bloom,
	source: Render_Target,
	settings := Bloom_Settings{threshold = 1, softness = 0.5},
) -> (
	Texture,
	Error,
) {
	if !(settings.threshold >= 0 && settings.threshold <= 65504) ||
	   !(settings.softness >= 0 && settings.softness <= 1) {
		return {}, .Invalid_Draw
	}

	color, err := rhi.render_target_color(renderer.device, source.handle)
	if err != .None {
		return {}, err
	}

	if renderer.device.pass_active {
		return {}, .Invalid_Pass
	}

	if source.width <= 0 || source.height <= 0 || source.color.handle != color {
		return {}, .Invalid_Draw
	}

	for target in bloom.targets {
		if target.handle == source.handle {
			return {}, .Feedback_Loop
		}
	}

	if err = resize_bloom(renderer, bloom, source.width, source.height); err != .None {
		return {}, err
	}

	if err = set_view(renderer, {orientation = 1}, emath.identity()); err != .None {
		return {}, err
	}

	texture := source.color
	for &target, i in bloom.targets {
		mode := Bloom_Mode.Prefilter if i == 0 else .Downsample
		if err = bloom_pass(renderer, bloom, &bloom.pipeline, texture, &target, settings, mode);
		   err != .None {
			return {}, err
		}
		texture = target.color
	}

	for i := len(bloom.targets) - 2; i >= 0; i -= 1 {
		if err = bloom_pass(
			renderer,
			bloom,
			&bloom.upsample_pipeline,
			bloom.targets[i + 1].color,
			&bloom.targets[i],
			settings,
			.Upsample,
		); err != .None {
			return {}, err
		}
	}

	return bloom.targets[0].color, .None
}

@(private)
bloom_pass :: proc(
	renderer: ^Renderer,
	bloom: ^Bloom,
	pipeline: ^Pipeline,
	source: Texture,
	target: ^Render_Target,
	settings: Bloom_Settings,
	mode: Bloom_Mode,
) -> Error {
	if err := set_material_texture(renderer, &bloom.material, 0, source); err != .None {
		return err
	}

	if err := update_material(
		renderer,
		&bloom.material,
		Bloom_Uniforms {
			threshold = settings.threshold,
			knee = settings.threshold * settings.softness,
			mode = mode,
			level_weight = 1 / f32(len(bloom.targets)),
		},
	); err != .None {
		return err
	}

	if err := begin_pass(
		renderer,
		{target = target, color_load = .Load if mode == .Upsample else .Clear},
		{},
	); err != .None {
		return err
	}

	draw_error := draw_mesh(
		renderer,
		pipeline,
		&bloom.mesh,
		&bloom.material,
		{orientation = 1, scale = {1, 1, 1}},
	)
	end_error := end_pass(renderer)
	return draw_error if draw_error != .None else end_error
}

@(private)
resize_bloom :: proc(renderer: ^Renderer, bloom: ^Bloom, width, height: i32) -> Error {
	if bloom.width == width && bloom.height == height {
		return .None
	}

	if err := release_bloom_targets(renderer, &bloom.pending_targets); err != .None {
		return err
	}

	w, h := width, height
	for {
		w, h = max(w / 2, 1), max(h / 2, 1)
		if _, err := append(&bloom.pending_targets, Render_Target{}); err != nil {
			return .Allocation_Failed
		}
		target := &bloom.pending_targets[len(bloom.pending_targets) - 1]
		err: Error
		target^, err = create_render_target(
			renderer,
			{
				width = w,
				height = h,
				color_format = .RGBA16F,
				color_filter = .Linear,
				label = "bloom",
			},
		)
		if err != .None {
			return err
		}

		if max(w, h) <= 4 {
			break
		}
	}

	bloom.width, bloom.height = 0, 0
	if err := release_bloom_targets(renderer, &bloom.targets); err != .None {
		return err
	}
	bloom.targets, bloom.pending_targets = bloom.pending_targets, bloom.targets
	bloom.width, bloom.height = width, height
	return .None
}

@(private)
release_bloom_targets :: proc(
	renderer: ^Renderer,
	targets: ^[dynamic]Render_Target,
) -> (
	result: Error,
) {
	for &target in targets^ {
		if err := destroy_render_target(renderer, &target); err != .None {
			result = err
		}
	}

	if result == .None {
		clear(targets)
	}
	return
}

destroy_bloom :: proc(renderer: ^Renderer, bloom: ^Bloom) -> (result: Error) {
	for targets in ([2]^[dynamic]Render_Target{&bloom.targets, &bloom.pending_targets}) {
		if err := release_bloom_targets(renderer, targets); err != .None {
			result = err
		}
	}

	if err := destroy_material(renderer, &bloom.material); err != .None {
		result = err
	}
	if err := destroy_mesh(renderer, &bloom.mesh); err != .None {
		result = err
	}
	for pipeline in ([2]^Pipeline{&bloom.upsample_pipeline, &bloom.pipeline}) {
		if err := destroy_pipeline(renderer, pipeline); err != .None {
			result = err
		}
	}

	if result == .None {
		delete(bloom.targets)
		delete(bloom.pending_targets)
		bloom^ = {}
	}
	return
}
