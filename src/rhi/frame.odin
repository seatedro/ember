package rhi

import "backend"

// Frames contain all passes for one presentation. Resource creation and updates
// can also happen outside a frame. Size is the current drawable size in pixels.
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

// Present only after every pass is closed. On failure the frame remains active
// so the caller can discard it before destroying resources.
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
	if err := backend.end_frame(&device.native, present); err != .None {
		return err
	}

	device.frame_active = false
	device.frame_size = {}
	device.bindings = {}
	return .None
}
