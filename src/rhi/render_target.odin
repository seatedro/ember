package rhi

import "../core/pool"
import "backend"
import "types"

Render_Target_Handle :: struct {
	index:      u32,
	generation: u32,
}

Render_Target_Desc :: types.Render_Target_Desc

Render_Target_Resource :: struct {
	ready:         bool,
	native:        backend.Render_Target,
	color, depth:  Texture_Handle,
	width, height: i32,
}

create_render_target :: proc(
	device: ^Device,
	desc: Render_Target_Desc,
) -> (
	Render_Target_Handle,
	Error,
) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	if desc.width <= 0 || desc.height <= 0 {
		return {}, .Invalid_Size
	}

	if desc.color_format < .RGBA8 ||
	   desc.color_format > .RGBA16F ||
	   desc.color_filter < .Linear ||
	   desc.color_filter > .Nearest {
		return {}, .Invalid_Texture
	}

	handle, slot := pool.alloc(&device.render_targets)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	slot.width, slot.height = desc.width, desc.height
	for attachment in 0 ..< 2 {
		if attachment == 0 && desc.depth_only {
			continue
		}

		texture_handle, texture_slot := pool.alloc(&device.textures)
		if texture_slot == nil {
			if destroy_render_target(device, handle) != .None {
				return handle, .Pool_Exhausted
			}
			return {}, .Pool_Exhausted
		}

		texture_slot.owner = handle
		if attachment == 0 {
			slot.color = texture_handle
		} else {
			slot.depth = texture_handle
		}

		texture, err := backend.create_texture(
			&device.native,
			{
				width = desc.width,
				height = desc.height,
				format = desc.color_format if attachment == 0 else .Depth32F,
				filter = desc.color_filter if attachment == 0 else .Nearest,
				wrap_u = .Clamp,
				wrap_v = .Clamp,
				label = desc.label,
			},
			nil,
		)
		if err != .None {
			if destroy_render_target(device, handle) == .None {
				return {}, err
			}
			return handle, err
		}
		texture_slot.native = texture
	}

	color: backend.Texture
	if slot.color.generation != 0 {
		color = pool.get(&device.textures, slot.color).native
	}
	depth := pool.get(&device.textures, slot.depth).native
	native, err := backend.create_render_target(&device.native, desc, color, depth)
	if err != .None {
		if destroy_render_target(device, handle) == .None {
			return {}, err
		}
		return handle, err
	}

	slot.native = native
	slot.ready = true
	return handle, .None
}

render_target_color :: proc(
	device: ^Device,
	handle: Render_Target_Handle,
) -> (
	Texture_Handle,
	Error,
) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	slot := pool.get(&device.render_targets, handle)
	if slot == nil {
		return {}, .Invalid_Handle
	}

	return slot.color, .None
}

render_target_depth :: proc(
	device: ^Device,
	handle: Render_Target_Handle,
) -> (
	Texture_Handle,
	Error,
) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	slot := pool.get(&device.render_targets, handle)
	if slot == nil {
		return {}, .Invalid_Handle
	}

	return slot.depth, .None
}

destroy_render_target :: proc(device: ^Device, handle: Render_Target_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.render_targets, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if device.pass_active && device.pass_target == handle {
		return .Resource_In_Use
	}

	if err := backend.wait_idle(&device.native); err != .None {
		return err
	}

	slot.ready = false
	if err := backend.destroy_render_target(&device.native, &slot.native); err != .None {
		return err
	}

	for texture in ([2]^Texture_Handle{&slot.color, &slot.depth}) {
		if texture.generation != 0 {
			if err := release_texture(device, texture^); err != .None {
				return err
			}
			texture^ = {}
		}
	}

	pool.free(&device.render_targets, handle)
	return .None
}
