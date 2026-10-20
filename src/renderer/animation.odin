package renderer

import "../assets"
import emath "../core/math"
import "../rhi"
import "core:math"
import "core:mem"

Node_Transform :: struct {
	translation: emath.Vec3,
	rotation:    emath.Quaternion,
	scale:       emath.Vec3,
}

Model_Pose :: struct {
	locals: []Node_Transform,
	worlds: []emath.Mat4,
	joints: []rhi.Buffer_Handle,
}

create_model_pose :: proc(
	renderer: ^Renderer,
	model: ^Model,
	allocator := context.allocator,
) -> (
	pose: Model_Pose,
	err: Error,
) {
	context.allocator = allocator
	defer if err != .None {
		destroy_model_pose(renderer, &pose)
	}
	pose.locals = make([]Node_Transform, len(model.skeleton.nodes))
	pose.worlds = make([]emath.Mat4, len(model.skeleton.nodes))
	pose.joints = make([]rhi.Buffer_Handle, len(model.skeleton.skins))
	for skin, i in model.skeleton.skins {
		if skin.joint_count > MAX_JOINTS {
			return pose, .Invalid_Size
		}
		pose.joints[i] = rhi.create_buffer(
			renderer.device,
			{size = size_of(Joint_Uniforms), usage = {.Uniform}, label = "joint matrices"},
			nil,
		) or_return
	}
	reset_model_pose(model, &pose)
	return pose, update_model_pose(renderer, model, &pose)
}

destroy_model_pose :: proc(
	renderer: ^Renderer,
	pose: ^Model_Pose,
	allocator := context.allocator,
) -> (
	result: Error,
) {
	for handle in pose.joints {
		if handle.generation == 0 {
			continue
		}
		if err := rhi.destroy_buffer(renderer.device, handle); err != .None && result == .None {
			result = err
		}
	}
	delete(pose.locals, allocator)
	delete(pose.worlds, allocator)
	delete(pose.joints, allocator)
	pose^ = {}
	return
}

reset_model_pose :: proc(model: ^Model, pose: ^Model_Pose) {
	for node, i in model.skeleton.nodes {
		pose.locals[i] = {node.translation, node.rotation, node.scale}
	}
}

find_animation :: proc(model: ^Model, name: string) -> (int, bool) {
	for animation, i in model.skeleton.animations {
		if animation.name == name {
			return i, true
		}
	}
	return 0, false
}

sample_animation :: proc(model: ^Model, pose: ^Model_Pose, animation: int, time: f32) {
	reset_model_pose(model, pose)
	skeleton := &model.skeleton
	clip := skeleton.animations[animation]
	t := time
	if clip.duration > 0 {
		t = math.mod(time, clip.duration)
		if t < 0 {
			t += clip.duration
		}
	}

	for channel in skeleton.channels[clip.first_channel:][:clip.channel_count] {
		if channel.key_count == 0 {
			continue
		}
		times := skeleton.key_times[channel.first_key:][:channel.key_count]
		components := 4 if channel.path == .Rotation else 3
		values := skeleton.key_values[channel.first_value:]

		next := 0
		for next < len(times) && times[next] <= t {
			next += 1
		}
		value: [4]f32
		switch {
		case next == 0:
			value = key_value(values, channel.interpolation, components, 0)
		case next == len(times) || channel.interpolation == .Step:
			value = key_value(values, channel.interpolation, components, next - 1)
		case:
			value = interpolate(values, channel, components, times, next - 1, t)
		}

		local := &pose.locals[channel.node]
		switch channel.path {
		case .Translation:
			local.translation = value.xyz
		case .Rotation:
			local.rotation = emath.quaternion_normalize(
				quaternion(x = value.x, y = value.y, z = value.z, w = value.w),
			)
		case .Scale:
			local.scale = value.xyz
		}
	}
}

update_model_pose :: proc(renderer: ^Renderer, model: ^Model, pose: ^Model_Pose) -> Error {
	skeleton := &model.skeleton
	for i in model.node_order {
		local := pose.locals[i]
		pose.worlds[i] = compose(local.translation, local.rotation, local.scale)
		parent := skeleton.nodes[i].parent
		if parent != assets.NO_INDEX {
			pose.worlds[i] = pose.worlds[parent] * pose.worlds[i]
		}
	}

	palette: Joint_Uniforms
	for skin, s in skeleton.skins {
		joints := skeleton.skin_joints[skin.first_joint:][:skin.joint_count]
		for joint, j in joints {
			palette.joints[j] = pose.worlds[joint.node] * joint.inverse_bind
		}
		bytes := mem.slice_to_bytes(palette.joints[:len(joints)])
		if err := rhi.update_buffer(renderer.device, pose.joints[s], 0, bytes); err != .None {
			return err
		}
	}
	return .None
}

@(private = "file")
key_value :: proc(
	values: []f32,
	interpolation: assets.Interpolation,
	components, key: int,
) -> (
	value: [4]f32,
) {
	stride := components
	offset := 0
	if interpolation == .Cubic_Spline {
		stride = 3 * components
		offset = components
	}
	copy(value[:components], values[key * stride + offset:][:components])
	return
}

@(private = "file")
interpolate :: proc(
	values: []f32,
	channel: assets.Channel,
	components: int,
	times: []f32,
	key: int,
	t: f32,
) -> [4]f32 {
	span := times[key + 1] - times[key]
	alpha := (t - times[key]) / span if span > 0 else 0
	from := key_value(values, channel.interpolation, components, key)
	to := key_value(values, channel.interpolation, components, key + 1)

	if channel.interpolation == .Cubic_Spline {
		stride := 3 * components
		out_tangent: [4]f32
		in_tangent: [4]f32
		copy(out_tangent[:components], values[key * stride + 2 * components:][:components])
		copy(in_tangent[:components], values[(key + 1) * stride:][:components])
		s := alpha
		s2, s3 := s * s, s * s * s
		return(
			(2 * s3 - 3 * s2 + 1) * from +
			(s3 - 2 * s2 + s) * span * out_tangent +
			(-2 * s3 + 3 * s2) * to +
			(s3 - s2) * span * in_tangent
		)
	}

	if channel.path == .Rotation {
		q := emath.quaternion_slerp(
			quaternion(x = from.x, y = from.y, z = from.z, w = from.w),
			quaternion(x = to.x, y = to.y, z = to.z, w = to.w),
			alpha,
		)
		return {q.x, q.y, q.z, q.w}
	}
	return from + (to - from) * alpha
}
