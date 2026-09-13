package rhi

import "../core/pool"
import "backend"
import "types"

Load_Op :: types.Load_Op
Viewport :: types.Viewport

Pass_Desc :: struct {
	target:                 Render_Target_Handle,
	viewport:               Viewport,
	color_load, depth_load: Load_Op,
}

begin_pass :: proc(
	device: ^Device,
	desc: Pass_Desc,
	clear_color: [4]f32 = {0.1, 0.1, 0.1, 1},
	clear_depth: f64 = 1,
) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if device.pass_active ||
	   desc.color_load < .Clear ||
	   desc.color_load > .Load ||
	   desc.depth_load < .Clear ||
	   desc.depth_load > .Load ||
	   !(clear_depth >= 0 && clear_depth <= 1) {
		return .Invalid_Pass
	}

	viewport := desc.viewport
	native: backend.Render_Target
	if desc.target != (Render_Target_Handle{}) {
		slot := pool.get(&device.render_targets, desc.target)
		if slot == nil || slot.native.framebuffer == 0 {
			return .Invalid_Handle
		}

		if viewport == (Viewport{}) {
			viewport = {
				width  = slot.width,
				height = slot.height,
			}
		}

		if i64(viewport.x) + i64(viewport.width) > i64(slot.width) ||
		   i64(viewport.y) + i64(viewport.height) > i64(slot.height) {
			return .Invalid_Size
		}

		native = slot.native
	}

	if viewport.x < 0 || viewport.y < 0 || viewport.width <= 0 || viewport.height <= 0 {
		return .Invalid_Size
	}

	if err := backend.begin_pass(
		native,
		viewport,
		desc.color_load,
		desc.depth_load,
		clear_color,
		clear_depth,
	); err != .None {
		backend.end_pass()
		return err
	}

	device.pass_active = true
	device.pass_viewport = viewport
	device.pass_target = desc.target
	device.bindings = {}
	return .None
}

end_pass :: proc(device: ^Device) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if !device.pass_active {
		return .Invalid_Pass
	}

	if err := backend.end_pass(); err != .None {
		return err
	}

	device.pass_active = false
	device.pass_viewport = {}
	device.pass_target = {}
	device.bindings = {}
	return .None
}
