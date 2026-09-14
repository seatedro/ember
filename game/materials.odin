package game

import render "ember:renderer"
import "ember:ui"

material_parameters :: proc(game: ^State, index: int) -> render.Lit_Parameters {
	colors := MATERIAL_COLORS
	return {
		tint = colors[index],
		emission = game.emission if index == 1 else 0,
		use_normal_map = b32(game.normal_mapping),
		metallic = game.metallic[index],
		roughness = game.roughness[index],
	}
}

shading_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	if game.lighting_tab == 0 {
		return lighting_controls(game, column)
	}
	return material_controls(game, column)
}

material_controls :: proc(game: ^State, column: ^ui.Layout) -> bool {
	ctx := &game.overlay.interface
	previous := [2]render.Lit_Parameters {
		material_parameters(game, 0),
		material_parameters(game, 1),
	}
	previous_maps := game.property_maps
	for control in ([2]struct {
			name, label: string,
			value:       ^bool,
		} {
			{"normal-mapping", "NORMAL MAP", &game.normal_mapping},
			{"property-maps", "PROPERTY MAP", &game.property_maps},
		}) {
		rect, err := ui.next(column, 24)
		if !check_ui(err) {
			return false
		}
		_, control_error := ui.checkbox(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	for control in ([5]struct {
			name, label: string,
			value:       ^f32,
			high:        f32,
		} {
			{"blue-metallic", "BLUE METALLIC", &game.metallic[0], 1},
			{"blue-roughness", "BLUE ROUGHNESS", &game.roughness[0], 1},
			{"orange-metallic", "ORANGE METALLIC", &game.metallic[1], 1},
			{"orange-roughness", "ORANGE ROUGHNESS", &game.roughness[1], 1},
			{"emission", "ORANGE EMISSION", &game.emission, 8},
		}) {
		rect, err := ui.next(column, 48)
		if !check_ui(err) {
			return false
		}
		_, control_error := ui.slider(
			ctx,
			ui.id(control.name),
			rect,
			control.label,
			control.value,
			0,
			control.high,
			step = 0.01,
		)
		if !check_ui(control_error) {
			return false
		}
	}

	for &material, i in game.materials {
		parameters := material_parameters(game, i)
		if parameters != previous[i] {
			if !check(
				render.update_material(&game.renderer, &material, parameters),
				"update material",
			) {
				return false
			}
		}
		if game.property_maps != previous_maps {
			texture := game.material_map if game.property_maps else game.renderer.white_texture
			for binding in 2 ..= 3 {
				if !check(
					render.set_material_texture(&game.renderer, &material, u32(binding), texture),
					"set material map",
				) {
					return false
				}
			}
		}
	}
	return true
}
