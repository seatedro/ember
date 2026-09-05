package rhi

import "backend"
import "types"

Error :: types.Error
Device_Context :: backend.Device_Context

Device :: struct {
	initialized: bool,
	buffers:     Buffer_Pool,
	shaders:     Shader_Pool,
	native:      backend.Device,
}

create_device :: proc(
	platform_context: Device_Context,
	buffer_capacity := 1024,
	allocator := context.allocator,
	shader_capacity := 128,
) -> (Device, Error) {
	pool, pool_error := buffer_pool_create(buffer_capacity, allocator)
	if pool_error != .None {
		if pool_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}
		return {}, .Allocation_Failed
	}
	shaders, shader_error := shader_pool_create(shader_capacity, allocator)
	if shader_error != .None {
		buffer_pool_destroy(&pool)
		if shader_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}
		return {}, .Allocation_Failed
	}
	native, err := backend.create_device(platform_context)
	if err != .None {
		shader_pool_destroy(&shaders)
		buffer_pool_destroy(&pool)
		return {}, err
	}
	return Device{initialized = true, buffers = pool, shaders = shaders, native = native}, .None
}

validate_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .Device_Not_Initialized
	}
	return backend.validate_context(&device.native)
}

destroy_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .None
	}
	if err := validate_device(device); err != .None {
		return err
	}
	if err := backend.wait_idle(); err != .None {
		return err
	}
	for &slot, index in device.buffers.slots {
		if slot.state == .Live {
			if err := backend.destroy_buffer(&slot.native); err != .None {
				return err
			}
			buffer_pool_retire(&device.buffers, Buffer_Handle{u32(index), slot.generation})
			buffer_pool_finish_retirement(&device.buffers, u32(index))
		}
	}
	for &slot, index in device.shaders.slots {
		if slot.state == .Live {
			if err := backend.destroy_shader(&slot.native); err != .None {
				return err
			}
			shader_pool_retire(&device.shaders, Shader_Handle{u32(index), slot.generation})
			shader_pool_finish_retirement(&device.shaders, u32(index))
		}
	}
	ok := buffer_pool_destroy(&device.buffers)
	assert(ok, "Device has an unfinished buffer operation")
	ok = shader_pool_destroy(&device.shaders)
	assert(ok, "Device has an unfinished shader operation")
	device^ = {}
	return .None
}

set_viewport :: proc(device: ^Device, width, height: i32) {
	assert(validate_device(device) == .None)
	backend.set_viewport(width, height)
}

clear :: proc(device: ^Device, color: [4]f32, depth: f64) {
	assert(validate_device(device) == .None)
	backend.clear(color, depth)
}
