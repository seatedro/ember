package renderer

import emath "../core/math"
import "core:math"

// TODO: Replace the fixed light limits with scalable light selection and storage.
MAX_POINT_LIGHTS :: 16
MAX_DIRECTIONAL_LIGHTS :: 4

Point_Light :: struct {
	position:  emath.Vec3,
	color:     emath.Vec3,
	intensity: f32,
	range:     f32,
}

Directional_Light :: struct {
	// Direction toward the light source; normalized when uploaded.
	direction: emath.Vec3,
	color:     emath.Vec3,
	intensity: f32,
}

Lighting :: struct {
	ambient:            emath.Vec3,
	point_lights:       []Point_Light,
	directional_lights: []Directional_Light,
}

@(private)
Point_Light_Uniform :: struct {
	position_range:  [4]f32,
	color_intensity: [4]f32,
}

@(private)
Directional_Light_Uniform :: struct {
	direction:       [4]f32,
	color_intensity: [4]f32,
}

@(private)
Lighting_Uniforms :: struct {
	ambient:                 [4]f32,
	point_light_count:       u32,
	directional_light_count: u32,
	_padding:                [2]u32,
	point_lights:            [MAX_POINT_LIGHTS]Point_Light_Uniform,
	directional_lights:      [MAX_DIRECTIONAL_LIGHTS]Directional_Light_Uniform,
}

#assert(size_of(Point_Light_Uniform) == 32)
#assert(size_of(Directional_Light_Uniform) == 32)
#assert(offset_of(Lighting_Uniforms, point_lights) == 32)
#assert(offset_of(Lighting_Uniforms, directional_lights) == 32 + MAX_POINT_LIGHTS * 32)

@(private)
pack_lighting :: proc(lighting: Lighting) -> (data: Lighting_Uniforms, err: Error) {
	if len(lighting.point_lights) > MAX_POINT_LIGHTS ||
	   len(lighting.directional_lights) > MAX_DIRECTIONAL_LIGHTS {
		return {}, .Invalid_Capacity
	}

	for value in lighting.ambient {
		if !(value >= 0) || math.is_inf(value) {
			return {}, .Invalid_Usage
		}
	}

	data.ambient = {lighting.ambient.x, lighting.ambient.y, lighting.ambient.z, 0}
	data.point_light_count = u32(len(lighting.point_lights))
	for light, i in lighting.point_lights {
		if !(light.range > 0) || math.is_inf(light.range) {
			return {}, .Invalid_Size
		}

		for value in ([4]f32{light.color.x, light.color.y, light.color.z, light.intensity}) {
			if !(value >= 0) || math.is_inf(value) {
				return {}, .Invalid_Usage
			}
		}

		for value in light.position {
			if math.is_nan(value) || math.is_inf(value) {
				return {}, .Invalid_Usage
			}
		}

		data.point_lights[i] = {
			position_range  = {light.position.x, light.position.y, light.position.z, light.range},
			color_intensity = {light.color.x, light.color.y, light.color.z, light.intensity},
		}
	}

	data.directional_light_count = u32(len(lighting.directional_lights))
	for light, i in lighting.directional_lights {
		for value in light.direction {
			if math.is_nan(value) || math.is_inf(value) {
				return {}, .Invalid_Usage
			}
		}

		magnitude := max(abs(light.direction.x), abs(light.direction.y), abs(light.direction.z))
		if magnitude == 0 {
			return {}, .Invalid_Usage
		}

		for value in ([4]f32{light.color.x, light.color.y, light.color.z, light.intensity}) {
			if !(value >= 0) || math.is_inf(value) {
				return {}, .Invalid_Usage
			}
		}

		direction := emath.normalize(light.direction / magnitude)
		data.directional_lights[i] = {
			direction       = {direction.x, direction.y, direction.z, 0},
			color_intensity = {light.color.x, light.color.y, light.color.z, light.intensity},
		}
	}

	return
}
