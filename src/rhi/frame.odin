package rhi

import "backend"

// Frames contain all passes for one presentation. Resource creation and updates
// can also happen outside a frame. Size is the current drawable size in pixels.
//
// TODO: Record passes, bindings, and draws into a command list per frame and
// submit it at end_frame, instead of executing each call on the backend as it
// arrives. Recording is what a render thread and draw sorting need; per-draw
// uniform bytes must then be copied into frame-owned storage. The typed array
// form is described in .docs/rhi.md (see .docs/decisions.md RHI-6).
begin_frame :: proc(device: ^Device, size: [2]i32) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if device.frame_active || device.pass_active {
		return .Invalid_Frame
	}

	if size.x <= 0 || size.y <= 0 {
		return .Invalid_Size
	}

	if err := backend.begin_frame(&device.native, size); err != .None {
		return err
	}

	device.frame_active = true
	device.frame_size = size
	device.bindings = {}
	return .None
}

// Present only after every pass is closed. Once submitted to the backend, the
// frame is consumed even if submission or GPU execution fails.
end_frame :: proc(device: ^Device) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if !device.frame_active {
		return .Invalid_Frame
	}

	if device.pass_active {
		return .Invalid_Pass
	}

	return finish_frame(device, true)
}

// Close outstanding work without presenting. This does not roll back writes to
// resources. It is also safe to call when there is no active frame.
discard_frame :: proc(device: ^Device) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	if !device.frame_active {
		return .None
	}

	if device.pass_active {
		if err := end_pass(device); err != .None {
			return err
		}
	}

	return finish_frame(device, false)
}

@(private)
finish_frame :: proc(device: ^Device, present: bool) -> Error {
	err := backend.end_frame(&device.native, present)

	device.frame_active = false
	device.frame_size = {}
	device.bindings = {}
	return err
}
