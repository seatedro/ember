package rhi

import "backend"

// A frame holds every pass for one present. Resources can be created and
// updated outside a frame too. size is the drawable size in pixels.
//
// TODO: Record into a command list and submit at end_frame.
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

// Presents only after every pass is closed. Once handed to the backend, the
// frame is used up even if submitting or running it fails.
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

// Closes any open work without presenting. Writes to resources aren't undone.
// Safe to call with no active frame.
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
