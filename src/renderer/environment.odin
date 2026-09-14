package renderer

import "../camera"
import emath "../core/math"
import "../core/pool"
import "../geometry"
import "../rhi"
import "../shaders"
import "core:math"
import "core:math/linalg"

Environment :: struct {
	radiance, irradiance, brdf:                   Render_Target,
	filter_pipeline, brdf_pipeline, sky_pipeline: Pipeline,
	filter_material, brdf_material, sky_material: Material,
	mesh:                                         Mesh,
	levels, samples:                              u32,
	ready, brdf_ready:                            bool,
}

@(private)
Environment_Filter_Uniforms :: struct {
	face:          u32,
	roughness:     f32,
	mode, samples: u32,
}

@(private)
Sky_Uniforms :: struct {
	inverse_view_projection: emath.Mat4,
	settings:                [4]f32,
}

create_environment :: proc(
	renderer: ^Renderer,
	library: ^shaders.Library,
	resolution: i32 = 128,
	samples: u32 = 256,
) -> (
	environment: Environment,
	err: Error,
) {
	if resolution < 2 || resolution & (resolution - 1) != 0 || samples == 0 || samples > 4096 {
		return {}, .Invalid_Size
	}

	defer {
		if err != .None {
			destroy_environment(renderer, &environment)
		}
	}
	environment.levels = rhi.texture_mip_count(resolution, resolution)
	environment.samples = samples
	for target, i in ([3]^Render_Target {
			&environment.radiance,
			&environment.irradiance,
			&environment.brdf,
		}) {
		size := resolution if i == 0 else (32 if i == 1 else 128)
		target^, err = create_render_target(
			renderer,
			{
				kind = .Cube if i < 2 else .Image_2D,
				mip_levels = environment.levels if i == 0 else 1,
				width = size,
				height = size,
				color_format = .RGBA16F,
				color_filter = .Linear,
			},
		)
		if err != .None {
			return
		}
	}

	for kind, i in ([3]Builtin_Shader{.Environment_Filter, .Environment_BRDF, .Sky}) {
		program, shader_error := load_builtin_shader(library, kind)
		if shader_error != .None {
			return environment, .Backend_Failed
		}
		pipelines := [3]^Pipeline {
			&environment.filter_pipeline,
			&environment.brdf_pipeline,
			&environment.sky_pipeline,
		}
		materials := [3]^Material {
			&environment.filter_material,
			&environment.brdf_material,
			&environment.sky_material,
		}
		textures := [1]Texture_Binding_Desc{{name = "source_texture", binding = 0}}
		pipelines[i]^, err = create_pipeline(
			renderer,
			program,
			{layout = VERTEX_LAYOUT, depth = {test_enabled = i == 2, compare = .Less_Equal}},
			textures[:0 if i == 1 else 1],
		)
		if err != .None {
			return
		}
		if i == 2 {
			materials[i]^, err = create_material(renderer, program, Sky_Uniforms{})
		} else {
			materials[i]^, err = create_material(
				renderer,
				program,
				Environment_Filter_Uniforms{samples = samples},
			)
		}
		if err != .None {
			return
		}
	}

	quad := geometry.create_quad()
	environment.mesh, err = create_mesh(
		renderer,
		quad.vertices[:],
		quad.indices[:],
		VERTEX_LAYOUT,
		quad.bounds,
	)
	return
}

// The callback draws an ordinary view into the active face. Capture all six
// faces before filtering, and exclude the reflecting object when appropriate.
Capture_Draw :: proc(
	renderer: ^Renderer,
	view: camera.Camera,
	projection: emath.Mat4,
	userdata: rawptr,
) -> Error

capture_cubemap :: proc(
	renderer: ^Renderer,
	target: ^Render_Target,
	position: emath.Vec3,
	near, far: f32,
	draw: Capture_Draw,
	userdata: rawptr = nil,
) -> Error {
	if target == nil || draw == nil || !(near > 0 && far > near) || math.is_inf(far) {
		return .Invalid_Usage
	}
	slot := pool.get(&renderer.device.render_targets, target.handle)
	if slot == nil || slot.kind != .Cube {
		return .Invalid_Handle
	}
	for value in position {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Usage
		}
	}

	roll := emath.quaternion_angle_axis(math.PI, {0, 0, 1})
	orientations := [6]emath.Quaternion {
		emath.quaternion_angle_axis(-math.PI / 2, {0, 1, 0}) * roll,
		emath.quaternion_angle_axis(math.PI / 2, {0, 1, 0}) * roll,
		emath.quaternion_angle_axis(math.PI / 2, {1, 0, 0}),
		emath.quaternion_angle_axis(-math.PI / 2, {1, 0, 0}),
		emath.quaternion_angle_axis(math.PI, {0, 1, 0}) * roll,
		roll,
	}
	projection := emath.perspective(math.PI / 2, 1, near, far)
	for orientation, face in orientations {
		if err := begin_pass(renderer, {target = target, face = u32(face)}, {0, 0, 0, 1});
		   err != .None {
			return err
		}
		draw_error := draw(
			renderer,
			{position = position, orientation = orientation},
			projection,
			userdata,
		)
		end_error := end_pass(renderer)
		if draw_error != .None {
			return draw_error
		}
		if end_error != .None {
			return end_error
		}
	}
	return .None
}

update_environment :: proc(
	renderer: ^Renderer,
	environment: ^Environment,
	source: Texture,
) -> Error {
	if environment == nil || environment.levels == 0 {
		return .Invalid_Usage
	}
	slot := pool.get(&renderer.device.textures, source.handle)
	if slot == nil || slot.desc.kind != .Cube {
		return .Invalid_Texture
	}
	if source.handle == environment.radiance.color.handle ||
	   source.handle == environment.irradiance.color.handle {
		return .Feedback_Loop
	}
	if renderer.device.pass_active {
		return .Invalid_Pass
	}

	environment.ready = false
	if err := set_material_texture(renderer, &environment.filter_material, 0, source);
	   err != .None {
		return err
	}
	if !environment.brdf_ready {
		if err := environment_pass(
			renderer,
			environment,
			&environment.brdf,
			0,
			0,
			&environment.brdf_pipeline,
			&environment.brdf_material,
		); err != .None {
			return err
		}
		environment.brdf_ready = true
	}
	for target, i in ([2]^Render_Target{&environment.radiance, &environment.irradiance}) {
		levels := environment.levels if i == 0 else 1
		for level in 0 ..< levels {
			for face in 0 ..< 6 {
				parameters := Environment_Filter_Uniforms {
					face      = u32(face),
					roughness = f32(level) / f32(environment.levels - 1),
					mode      = 1 if i == 1 else (0 if level == 0 else 2),
					samples   = environment.samples,
				}
				if err := update_material(renderer, &environment.filter_material, parameters);
				   err != .None {
					return err
				}
				if err := environment_pass(
					renderer,
					environment,
					target,
					u32(face),
					level,
					&environment.filter_pipeline,
					&environment.filter_material,
				); err != .None {
					return err
				}
			}
		}
	}
	environment.ready = true
	return .None
}

@(private)
environment_pass :: proc(
	renderer: ^Renderer,
	environment: ^Environment,
	target: ^Render_Target,
	face, level: u32,
	pipeline: ^Pipeline,
	material: ^Material,
) -> (
	result: Error,
) {
	if err := begin_pass(renderer, {target = target, face = face, mip_level = level});
	   err != .None {
		return err
	}
	defer {
		end_error := end_pass(renderer)
		if result == .None {
			result = end_error
		}
	}
	if err := set_view(renderer, {orientation = 1}, emath.identity()); err != .None {
		return err
	}
	return draw_mesh(
		renderer,
		pipeline,
		&environment.mesh,
		material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

draw_environment :: proc(
	renderer: ^Renderer,
	environment: ^Environment,
	view: camera.Camera,
	projection: emath.Mat4,
	intensity: f32 = 1,
	rotation: f32 = 0,
) -> Error {
	if environment == nil ||
	   !environment.ready ||
	   !(intensity >= 0) ||
	   math.is_inf(intensity) ||
	   math.is_nan(rotation) ||
	   math.is_inf(rotation) {
		return .Invalid_Usage
	}
	pose := view
	pose.position = {}
	parameters := Sky_Uniforms {
		inverse_view_projection = linalg.inverse(projection * camera.view_matrix(pose)),
		settings                = {intensity, rotation, 0, 0},
	}
	if err := update_material(renderer, &environment.sky_material, parameters); err != .None {
		return err
	}
	if err := set_material_texture(
		renderer,
		&environment.sky_material,
		0,
		environment.radiance.color,
	); err != .None {
		return err
	}
	far_plane := emath.identity()
	far_plane[2, 3] = 1
	if err := set_view(renderer, {orientation = 1}, far_plane); err != .None {
		return err
	}
	return draw_mesh(
		renderer,
		&environment.sky_pipeline,
		&environment.mesh,
		&environment.sky_material,
		{orientation = 1, scale = {1, 1, 1}},
	)
}

destroy_environment :: proc(renderer: ^Renderer, environment: ^Environment) -> (result: Error) {
	for material in ([3]^Material {
			&environment.filter_material,
			&environment.brdf_material,
			&environment.sky_material,
		}) {
		if err := destroy_material(renderer, material); err != .None {
			result = err
		}
	}
	for pipeline in ([3]^Pipeline {
			&environment.filter_pipeline,
			&environment.brdf_pipeline,
			&environment.sky_pipeline,
		}) {
		if err := destroy_pipeline(renderer, pipeline); err != .None {
			result = err
		}
	}
	if err := destroy_mesh(renderer, &environment.mesh); err != .None {
		result = err
	}
	for target in ([3]^Render_Target {
			&environment.radiance,
			&environment.irradiance,
			&environment.brdf,
		}) {
		if err := destroy_render_target(renderer, target); err != .None {
			result = err
		}
	}
	if result == .None {
		environment^ = {}
	}
	return
}
