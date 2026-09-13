package renderer

import emath "../core/math"
import "../shaders"
import "core:math"

Shadow_View :: struct {
	center:    emath.Vec3,
	half_size: [2]f32,
	depth:     f32,
}

Shadow_Settings :: struct {
	enabled:          bool,
	light_index:      u32,
	bias, slope_bias: f32,
}

Shadow_Map :: struct {
	target:          Render_Target,
	pipeline:        Pipeline,
	material:        Material,
	draws:           Draw_List,
	view_projection: emath.Mat4,
	ready:           bool,
}

create_shadow_map :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
	resolution: i32,
) -> (
	shadow: Shadow_Map,
	err: Error,
) {
	shadow.draws = create_draw_list()
	defer {
		if err != .None {
			destroy_shadow_map(renderer, &shadow)
		}
	}

	shadow.target, err = create_render_target(
		renderer,
		{width = resolution, height = resolution, depth_only = true, label = "directional shadow"},
	)
	if err != .None {
		return
	}

	program, shader_error := load_builtin_shader(library, .Shadow_Depth)
	if shader_error != .None {
		err = .Backend_Failed
		return
	}

	shadow.pipeline, err = create_pipeline(
		renderer,
		program,
		{
			layout = VERTEX_LAYOUT,
			depth_only = true,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
		},
		material_uniforms = false,
	)
	if err != .None {
		return
	}

	shadow.material, err = create_material(renderer, program, Tint_Parameters{})
	return
}

draw_directional_shadow :: proc(
	renderer: ^Renderer,
	shadow: ^Shadow_Map,
	list: ^Draw_List,
	light: Directional_Light,
	view: Shadow_View,
) -> (
	err: Error,
) {
	shadow.ready = false
	for value in light.direction {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Usage
		}
	}
	magnitude := max(abs(light.direction.x), abs(light.direction.y), abs(light.direction.z))
	if magnitude == 0 {
		return .Invalid_Usage
	}

	for value in ([3]f32{view.half_size.x, view.half_size.y, view.depth}) {
		if !(value > 0) || math.is_inf(value) {
			return .Invalid_Size
		}
	}
	for value in view.center {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Usage
		}
	}

	direction := emath.normalize(light.direction / magnitude)
	up := emath.Vec3{0, 1, 0}
	if abs(direction.y) > 0.99 {
		up = {0, 0, 1}
	}
	light_view := emath.look_at(direction, {}, up)
	for row in 0 ..< 3 {
		light_view[row, 3] = -(light_view[row, 0] * view.center.x +
			light_view[row, 1] * view.center.y +
			light_view[row, 2] * view.center.z)
	}

	projection := emath.identity()
	projection[0, 0] = 1 / view.half_size.x
	projection[1, 1] = 1 / view.half_size.y
	projection[2, 2] = -2 / view.depth
	light_matrix := projection * light_view
	for value in transmute([16]f32)light_matrix {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Usage
		}
	}

	clear_draw_list(&shadow.draws)
	// Camera visibility does not determine whether an object can cast a shadow.
	for entry in list.items {
		if entry.item.order != .Opaque {
			continue
		}
		if err = add_draw(
			&shadow.draws,
			{
				pipeline = shadow.pipeline,
				material = shadow.material,
				mesh = entry.item.mesh,
				transform = entry.item.transform,
			},
		); err != .None {
			return
		}
	}

	if err = begin_pass(renderer, {target = &shadow.target}); err != .None {
		return
	}
	defer {
		end_error := end_pass(renderer)
		if err == .None {
			err = end_error
		}
		if err == .None {
			shadow.view_projection = light_matrix
			shadow.ready = true
		}
	}

	return draw_list(renderer, &shadow.draws, {orientation = 1}, light_matrix)
}

destroy_shadow_map :: proc(renderer: ^Renderer, shadow: ^Shadow_Map) -> (result: Error) {
	destroy_draw_list(&shadow.draws)
	if err := destroy_material(renderer, &shadow.material); err != .None {
		result = err
	}
	if err := destroy_pipeline(renderer, &shadow.pipeline); err != .None {
		result = err
	}
	if err := destroy_render_target(renderer, &shadow.target); err != .None {
		result = err
	}
	shadow.ready = false
	return
}
