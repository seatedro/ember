package rhi

import "../core/pool"
import "backend"
import "types"

Buffer_Handle :: struct {
	index:      u32,
	generation: u32,
}

Buffer_Usage :: types.Buffer_Usage
Buffer_Usages :: types.Buffer_Usages
Memory_Preference :: types.Memory_Preference
Buffer_Desc :: types.Buffer_Desc

create_buffer :: proc(
	device: ^Device,
	desc: Buffer_Desc,
	initial_data: []u8 = nil,
) -> (
	Buffer_Handle,
	Error,
) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	if err := validate_buffer_desc(desc, len(initial_data)); err != .None {
		return {}, err
	}

	handle, slot := pool.alloc(&device.buffers)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	native, err := backend.create_buffer(&device.native, desc, initial_data)
	if err != .None {
		pool.free(&device.buffers, handle)
		return {}, err
	}

	slot.size = desc.size
	slot.usage = desc.usage
	slot.native = native
	return handle, .None
}

validate_buffer_desc :: proc(desc: Buffer_Desc, initial_data_size: int) -> Error {
	if desc.size == 0 || desc.size > u64(max(int)) {
		return .Invalid_Size
	}

	if desc.usage == {} {
		return .Invalid_Usage
	}

	supported := Buffer_Usages{.Vertex, .Index, .Uniform}
	if desc.usage - supported != {} {
		return .Unsupported_Usage
	}

	if desc.memory_preference != .GPU {
		return .Unsupported_Memory
	}

	if initial_data_size < 0 || u64(initial_data_size) > desc.size {
		return .Initial_Data_Too_Large
	}

	return .None
}

validate_buffer_range :: proc(size, offset: u64, data_size: int) -> Error {
	if data_size < 0 || offset > size || u64(data_size) > size - offset {
		return .Invalid_Buffer_Range
	}

	return .None
}

// Copies the bytes before returning; the backend orders the update against GPU reads.
update_buffer :: proc(device: ^Device, handle: Buffer_Handle, offset: u64, data: []u8) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := validate_buffer_range(slot.size, offset, len(data)); err != .None {
		return err
	}

	if len(data) == 0 {
		return .None
	}

	return backend.update_buffer(&device.native, slot.native, offset, data)
}

// Wait for GPU reads to finish before recycling the buffer slot.
destroy_buffer :: proc(device: ^Device, handle: Buffer_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := backend.wait_idle(&device.native); err != .None {
		return err
	}

	if err := backend.destroy_buffer(&device.native, &slot.native); err != .None {
		return err
	}

	pool.free(&device.buffers, handle)
	return .None
}

Buffer_Resource :: struct {
	size:   u64,
	usage:  Buffer_Usages,
	native: backend.Buffer,
}
