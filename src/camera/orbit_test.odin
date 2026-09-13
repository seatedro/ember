package camera

import "core:math"
import "core:testing"

@(test)
test_orbit_control_limits :: proc(t: ^testing.T) {
	orbit := Orbit {
		distance = 8,
	}
	testing.expect(t, rotate_orbit(&orbit, {100, 100}, 1) == true)
	testing.expect(t, orbit.pitch == 1 && abs(orbit.yaw) < 2 * math.PI)
	testing.expect(t, zoom_orbit(&orbit, 1e300, 1.5, 30))
	testing.expect(t, orbit.distance == 1.5)
	testing.expect(t, zoom_orbit(&orbit, -1e300, 1.5, 30))
	testing.expect(t, orbit.distance == 30)
	before := orbit
	testing.expect(t, !zoom_orbit(&orbit, 1, 30, 1.5))
	testing.expect(t, !rotate_orbit(&orbit, {1, 1}, 0))
	testing.expect(t, orbit == before)
}
