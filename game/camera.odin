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
			game.orbit.yaw -= f32(app.input.mouse_delta.x) * ORBIT_SENSITIVITY
			game.orbit.yaw = math.mod(game.orbit.yaw, f32(2 * math.PI))
			game.orbit.pitch = clamp(
				game.orbit.pitch + f32(app.input.mouse_delta.y) * ORBIT_SENSITIVITY,
				-PITCH_LIMIT,
				PITCH_LIMIT,
			)
		}

		if app.input.scroll_delta.y != 0 {
			// Bound the exponent before exp so a large scroll cannot overflow.
			log_distance :=
				math.ln(f64(game.orbit.distance)) - app.input.scroll_delta.y * ZOOM_SENSITIVITY
			log_distance = clamp(
				log_distance,
				math.ln(f64(MIN_DISTANCE)),
				math.ln(f64(MAX_DISTANCE)),
			)
			game.orbit.distance = clamp(f32(math.exp(log_distance)), MIN_DISTANCE, MAX_DISTANCE)
		}
	}

	game.camera = camera.from_orbit(game.orbit)
}
