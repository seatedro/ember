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
	native:        backend.Render_Target,
	color:         Texture_Handle,
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

	color_handle, color_slot := pool.alloc(&device.textures)
	if color_slot == nil {
		pool.free(&device.render_targets, handle)
		return {}, .Pool_Exhausted
	}

	color, color_error := backend.create_texture(
		{
			width = desc.width,
			height = desc.height,
			format = desc.color_format,
			filter = desc.color_filter,
			wrap_u = .Clamp,
			wrap_v = .Clamp,
			label = desc.label,
		},
		nil,
	)
	if color_error != .None {
		pool.free(&device.textures, color_handle)
		pool.free(&device.render_targets, handle)
		return {}, color_error
	}

	color_slot.native = color
	slot.color = color_handle
	slot.width, slot.height = desc.width, desc.height
	color_slot.owner = handle

	native, err := backend.create_render_target(desc, color)
	if err != .None {
		// Preserve the owning handle if releasing its color texture also fails.
		if destroy_render_target(device, handle) == .None {
			return {}, err
		}

		return handle, err
	}

	slot.native = native
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

	if err := backend.wait_idle(); err != .None {
		return err
	}

	if err := backend.destroy_render_target(&slot.native); err != .None {
		return err
	}

	if slot.color.generation != 0 {
		if err := release_texture(device, slot.color); err != .None {
			return err
		}

		slot.color = {}
	}

	pool.free(&device.render_targets, handle)
	return .None
}
