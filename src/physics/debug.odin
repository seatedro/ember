package physics

import emath "../core/math"
import "core:math"

Debug_Line_Proc :: proc(a, b: emath.Vec3, collider: Collider_Handle, userdata: rawptr)

debug_world :: proc(
	world: ^World,
	emit: Debug_Line_Proc,
	userdata: rawptr = nil,
	alpha: f32 = 1,
) -> Error {
	if emit == nil || !finite(alpha) || alpha < 0 || alpha > 1 {
		return .Invalid_Value
	}
	for slot, i in world.colliders.slots {
		if !slot.used {
			continue
		}
		handle := Collider_Handle{u32(i), slot.generation}
		pose, _ := collider_pose(world, handle, alpha)
		if err := debug_shape(slot.value.state.shape, pose, emit, userdata, handle); err != .None {
			return err
		}
	}
	return .None
}

debug_shape :: proc(
	shape: Shape,
	pose: emath.Pose,
	emit: Debug_Line_Proc,
	userdata: rawptr = nil,
	collider: Collider_Handle = {},
	segments: int = 32,
) -> Error {
	if !valid_shape(shape) {
		return .Invalid_Shape
	}
	if !valid_pose(pose) || emit == nil || segments < 4 {
		return .Invalid_Value
	}
	frame := pose
	frame.orientation = emath.quaternion_normalize(frame.orientation)
	switch s in shape {
	case Box:
		for corner in 0 ..< 8 {
			a: emath.Vec3
			for axis in 0 ..< 3 {
				a[axis] = s.half_extent[axis] * (1 if corner & (1 << uint(axis)) != 0 else -1)
			}
			for axis in 0 ..< 3 {
				if corner & (1 << uint(axis)) != 0 {
					continue
				}
				b := a
				b[axis] = -b[axis]
				debug_edge(frame, a, b, emit, userdata, collider)
			}
		}
	case Sphere:
		for axis in 0 ..< 3 {
			for i in 0 ..< segments {
				a, b: emath.Vec3
				t0, t1 :=
					f32(i) * 2 * math.PI / f32(segments), f32(i + 1) * 2 * math.PI / f32(segments)
				a[(axis + 1) % 3], a[(axis + 2) % 3] =
					s.radius * math.cos(t0), s.radius * math.sin(t0)
				b[(axis + 1) % 3], b[(axis + 2) % 3] =
					s.radius * math.cos(t1), s.radius * math.sin(t1)
				debug_edge(frame, a, b, emit, userdata, collider)
			}
		}
	case Capsule:
		for sign in ([2]f32{-1, 1}) {
			for i in 0 ..< segments {
				t0, t1 :=
					f32(i) * 2 * math.PI / f32(segments), f32(i + 1) * 2 * math.PI / f32(segments)
				a := emath.Vec3 {
					s.radius * math.cos(t0),
					sign * s.half_height,
					s.radius * math.sin(t0),
				}
				b := emath.Vec3 {
					s.radius * math.cos(t1),
					sign * s.half_height,
					s.radius * math.sin(t1),
				}
				debug_edge(frame, a, b, emit, userdata, collider)
			}
			for axis in ([2]int{0, 2}) {
				for i in 0 ..< segments / 2 {
					t0, t1 :=
						f32(i) *
						math.PI /
						f32(segments / 2),
						f32(i + 1) *
						math.PI /
						f32(segments / 2)
					a, b: emath.Vec3
					a[axis], b[axis] = s.radius * math.cos(t0), s.radius * math.cos(t1)
					a.y = sign * (s.half_height + s.radius * math.sin(t0))
					b.y = sign * (s.half_height + s.radius * math.sin(t1))
					debug_edge(frame, a, b, emit, userdata, collider)
				}
				a, b := emath.Vec3{0, -s.half_height, 0}, emath.Vec3{0, s.half_height, 0}
				a[axis], b[axis] = sign * s.radius, sign * s.radius
				debug_edge(frame, a, b, emit, userdata, collider)
			}
		}
	}
	return .None
}

@(private)
debug_edge :: proc(
	pose: emath.Pose,
	a, b: emath.Vec3,
	emit: Debug_Line_Proc,
	userdata: rawptr,
	collider: Collider_Handle,
) {
	emit(
		pose.position + emath.quaternion_rotate(pose.orientation, a),
		pose.position + emath.quaternion_rotate(pose.orientation, b),
		collider,
		userdata,
	)
}
