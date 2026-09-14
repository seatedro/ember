package game

import "core:log"
import "core:math"
import emath "ember:core/math"
import "ember:scene"

init_objects :: proc(game: ^State) -> bool {
	err: scene.Error
	game.world, err = scene.create(401)
	if !check_scene(err) {
		return false
	}
	game.grid, err = scene.create_object(&game.world)
	if !check_scene(err) {
		return false
	}

	for z in 0 ..< 20 {
		for x in 0 ..< 20 {
			game.spheres[z][x], err = scene.create_object(
				&game.world,
				sphere_transform(x, z, 0),
				game.grid,
			)
			if !check_scene(err) {
				return false
			}
		}
	}

	return true
}

sphere_transform :: proc(x, z: int, angle: f32) -> emath.Mat4 {
	return emath.transform_matrix(
		{
			position = {(f32(x) - 9.5) * 2.5, math.sin(f32(x + z) * 0.4), (f32(z) - 9.5) * 2.5},
			orientation = emath.quaternion_angle_axis(
				angle + f32(x) * 0.2,
				emath.normalize({1, 1, 0}),
			),
			scale = {0.7, 1, 0.7},
		},
	)
}

check_scene :: proc(err: scene.Error) -> bool {
	if err != .None {
		log.errorf("Scene: %v", err)
	}

	return err == .None
}
