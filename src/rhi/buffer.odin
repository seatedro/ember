package rhi

import "backend"
import "core:mem"
import "types"

Buffer_Handle :: struct {
	index:      u32,
	generation: u32,
}

Buffer_State :: enum {
	Free,
	Reserved,
	Live,
	Retiring,
	Exhausted,
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
	index, slot := buffer_pool_reserve(&device.buffers)
	if slot == nil {
		return {}, .Pool_Exhausted
	}
	native, err := backend.create_buffer(desc, initial_data)
	if err != .None {
		buffer_pool_cancel(&device.buffers, index)
		return {}, err
	}
	slot.size = desc.size
	slot.usage = desc.usage
	slot.native = native
	return buffer_pool_publish(&device.buffers, index), .None
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
	slot := buffer_pool_lookup(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}
	if err := validate_buffer_range(slot.size, offset, len(data)); err != .None {
		return err
	}
	if len(data) == 0 {
		return .None
	}
	return backend.update_buffer(slot.native, offset, data)
}

// Wait for GPU reads to finish before recycling the buffer slot.
destroy_buffer :: proc(device: ^Device, handle: Buffer_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}
	slot := buffer_pool_lookup(&device.buffers, handle)
	if slot == nil {
		return .Invalid_Handle
	}
	if err := backend.wait_idle(); err != .None {
		return err
	}
	if err := backend.destroy_buffer(&slot.native); err != .None {
		return err
	}
	buffer_pool_retire(&device.buffers, handle)
	buffer_pool_finish_retirement(&device.buffers, handle.index)
	return .None
}

Buffer_Slot :: struct {
	generation:      u32,
	state:           Buffer_State,
	size:            u64,
	usage:           Buffer_Usages,
	last_submission: u64,
	native:          backend.Buffer,
}

Buffer_Pool :: struct {
	slots:        []Buffer_Slot,
	free_indices: []u32,
	free_count:   int,
	allocator:    mem.Allocator,
}

Buffer_Pool_Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
}

buffer_pool_create :: proc(
	capacity: int,
	allocator := context.allocator,
) -> (
	Buffer_Pool,
	Buffer_Pool_Error,
) {
	if capacity <= 0 ||
	   u64(capacity) > u64(max(u32)) ||
	   capacity > max(int) / size_of(Buffer_Slot) {
		return {}, .Invalid_Capacity
	}

	slots, slots_error := make([]Buffer_Slot, capacity, allocator)
	if slots_error != .None {
		return {}, .Allocation_Failed
	}

	free_indices, free_indices_error := make([]u32, capacity, allocator)
	if free_indices_error != .None {
		delete(slots, allocator)
		return {}, .Allocation_Failed
	}

	for i in 0 ..< capacity {
		slots[i].generation = 1
		slots[i].state = .Free

		free_indices[i] = u32(capacity - i - 1)
	}

	return Buffer_Pool {
			slots = slots,
			free_indices = free_indices,
			free_count = capacity,
			allocator = allocator,
		},
		.None
}

buffer_pool_reserve :: proc(pool: ^Buffer_Pool) -> (index: u32, slot: ^Buffer_Slot) {
	if pool.free_count == 0 {
		return 0, nil
	}

	pool.free_count -= 1
	index = pool.free_indices[pool.free_count]
	slot = &pool.slots[index]

	assert(slot.state == .Free)
	assert(slot.generation != 0)

	slot.state = .Reserved
	return index, slot
}

buffer_pool_publish :: proc(pool: ^Buffer_Pool, index: u32) -> Buffer_Handle {
	slot := &pool.slots[index]
	assert(slot.state == .Reserved)

	slot.state = .Live
	return Buffer_Handle{index = index, generation = slot.generation}
}

buffer_pool_return_slot :: proc(pool: ^Buffer_Pool, index: u32) {
	generation := pool.slots[index].generation

	pool.slots[index] = Buffer_Slot {
		generation = generation,
		state      = .Free,
	}

	assert(pool.free_count < len(pool.free_indices))
	pool.free_indices[pool.free_count] = index
	pool.free_count += 1
}

buffer_pool_cancel :: proc(pool: ^Buffer_Pool, index: u32) {
	assert(pool.slots[index].state == .Reserved)
	buffer_pool_return_slot(pool, index)
}

buffer_pool_lookup :: proc(pool: ^Buffer_Pool, handle: Buffer_Handle) -> ^Buffer_Slot {
	if handle.generation == 0 {
		return nil
	}

	if uint(handle.index) >= uint(len(pool.slots)) {
		return nil
	}

	slot := &pool.slots[handle.index]

	if slot.state != .Live || slot.generation != handle.generation {
		return nil
	}

	return slot
}

buffer_pool_mark_used :: proc(pool: ^Buffer_Pool, handle: Buffer_Handle, submission: u64) -> bool {
	slot := buffer_pool_lookup(pool, handle)
	if slot == nil {
		return false
	}

	slot.last_submission = max(slot.last_submission, submission)
	return true
}

buffer_pool_retire :: proc(pool: ^Buffer_Pool, handle: Buffer_Handle) -> bool {
	slot := buffer_pool_lookup(pool, handle)
	if slot == nil {
		return false
	}

	slot.state = .Retiring

	if slot.generation == max(u32) {
		// Mark generation overflow so retirement never makes an old handle valid again.
		slot.generation = 0
	} else {
		slot.generation += 1
	}

	return true
}

buffer_pool_finish_retirement :: proc(pool: ^Buffer_Pool, index: u32) {
	slot := &pool.slots[index]
	assert(slot.state == .Retiring)

	if slot.generation == 0 {
		slot^ = Buffer_Slot {
			state = .Exhausted,
		}
		return
	}

	buffer_pool_return_slot(pool, index)
}

buffer_pool_destroy :: proc(pool: ^Buffer_Pool) -> bool {
	for slot in pool.slots {
		if slot.state != .Free && slot.state != .Exhausted {
			return false
		}
	}

	delete(pool.slots, pool.allocator)
	delete(pool.free_indices, pool.allocator)
	pool^ = {}

	return true
}
