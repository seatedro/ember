package rhi

Error :: enum {
	None,
	Device_Not_Initialized,
	Invalid_Capacity,
	Allocation_Failed,
	Wrong_Context,
	Unsupported_Backend,
	Backend_Failed,
	Invalid_Size,
	Invalid_Usage,
	Unsupported_Usage,
	Unsupported_Memory,
	Initial_Data_Too_Large,
	Pool_Exhausted,
	Invalid_Handle,
}

Device :: struct {
	initialized: bool,
	buffers:     Buffer_Pool,
	backend:     Backend_Device,
}

create_device :: proc(
	platform_context: Device_Context,
	buffer_capacity := 1024,
	allocator := context.allocator,
) -> (Device, Error) {
	pool, pool_error := buffer_pool_create(buffer_capacity, allocator)
	if pool_error != .None {
		if pool_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}
		return {}, .Allocation_Failed
	}
	backend, err := backend_create_device(platform_context)
	if err != .None {
		buffer_pool_destroy(&pool)
		return {}, err
	}
	return Device{initialized = true, buffers = pool, backend = backend}, .None
}

validate_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .Device_Not_Initialized
	}
	return backend_validate_context(&device.backend)
}

destroy_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .None
	}
	if err := validate_device(device); err != .None {
		return err
	}
	if err := backend_wait_idle(); err != .None {
		return err
	}
	for &slot, index in device.buffers.slots {
		if slot.state == .Live {
			if err := backend_destroy_buffer(&slot.native); err != .None {
				return err
			}
			buffer_pool_retire(&device.buffers, Buffer_Handle{u32(index), slot.generation})
			buffer_pool_finish_retirement(&device.buffers, u32(index))
		}
	}
	ok := buffer_pool_destroy(&device.buffers)
	assert(ok, "Device has an unfinished buffer operation")
	device^ = {}
	return .None
}

set_viewport :: proc(device: ^Device, width, height: i32) {
	assert(validate_device(device) == .None)
	backend_set_viewport(width, height)
}

clear :: proc(device: ^Device, color: [4]f32, depth: f64) {
	assert(validate_device(device) == .None)
	backend_clear(color, depth)
}
