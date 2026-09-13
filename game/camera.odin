package game

import "core:math"
import "ember:camera"
import "ember:engine"
import "ember:input"

INITIAL_ORBIT := camera.Orbit {
	pitch    = math.atan2(f32(0.35), f32(3.3)),
	distance = 8,
}

ORBIT_SENSITIVITY :: f32(0.005)
ZOOM_SENSITIVITY :: f64(0.1)
PITCH_LIMIT :: f32(85 * math.PI / 180)
MIN_DISTANCE :: f32(1.5)
MAX_DISTANCE :: f32(30)

update_camera :: proc(game: ^State, app: ^engine.Context) {
	if input.pressed(app.input, .R) {
		game.orbit = INITIAL_ORBIT
	} else {
		if input.mouse_down(app.input, .Left) {
			if !camera.rotate_orbit(
				&game.orbit,
				{
					f32(app.input.mouse_delta.x) * ORBIT_SENSITIVITY,
					f32(app.input.mouse_delta.y) * ORBIT_SENSITIVITY,
				},
				PITCH_LIMIT,
			) {
				engine.request_quit(app)
			}
		}

		if app.input.scroll_delta.y != 0 {
			if !camera.zoom_orbit(
				&game.orbit,
				app.input.scroll_delta.y * ZOOM_SENSITIVITY,
				MIN_DISTANCE,
				MAX_DISTANCE,
			) {
				engine.request_quit(app)
			}
		}
	}

	game.camera = camera.from_orbit(game.orbit)
}
