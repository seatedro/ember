package rhi

import "backend"
import "core:mem"
import "types"

Shader_Handle :: types.Shader_Handle

Shader_State :: enum {
	Free,
	Reserved,
	Live,
	Retiring,
	Exhausted,
}

Shader_Stage :: types.Shader_Stage
Shader_Desc :: types.Shader_Desc

validate_shader_desc :: proc(desc: Shader_Desc) -> Error {
	if desc.stage != .Vertex && desc.stage != .Fragment {
		return .Unsupported_Shader_Stage
	}
	if len(desc.source) == 0 || len(desc.source) > int(max(i32)) {
		return .Invalid_Shader_Source
	}
	return .None
}

create_shader :: proc(device: ^Device, desc: Shader_Desc) -> (Shader_Handle, Error) {
	if err := validate_device(device); err != .None {
		return {}, err
	}
	if err := validate_shader_desc(desc); err != .None {
		return {}, err
	}
	index, slot := shader_pool_reserve(&device.shaders)
	if slot == nil {
		return {}, .Pool_Exhausted
	}
	native, err := backend.create_shader(desc, device.shaders.allocator)
	if err != .None {
		shader_pool_cancel(&device.shaders, index)
		return {}, err
	}
	slot.stage = desc.stage
	slot.native = native
	return shader_pool_publish(&device.shaders, index), .None
}

destroy_shader :: proc(device: ^Device, handle: Shader_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}
	slot := shader_pool_lookup(&device.shaders, handle)
	if slot == nil {
		return .Invalid_Handle
	}
	if err := backend.destroy_shader(&slot.native); err != .None {
		return err
	}
	shader_pool_retire(&device.shaders, handle)
	shader_pool_finish_retirement(&device.shaders, handle.index)
	return .None
}

Shader_Slot :: struct {
	generation: u32,
	state:      Shader_State,
	stage:      Shader_Stage,
	native:     backend.Shader,
}

Shader_Pool :: struct {
	slots:        []Shader_Slot,
	free_indices: []u32,
	free_count:   int,
	allocator:    mem.Allocator,
}

Shader_Pool_Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
}

shader_pool_create :: proc(
	capacity: int,
	allocator := context.allocator,
) -> (
	Shader_Pool,
	Shader_Pool_Error,
) {
	if capacity <= 0 ||
	   u64(capacity) > u64(max(u32)) ||
	   capacity > max(int) / size_of(Shader_Slot) {
		return {}, .Invalid_Capacity
	}

	slots, slots_error := make([]Shader_Slot, capacity, allocator)
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

	return Shader_Pool {
			slots = slots,
			free_indices = free_indices,
			free_count = capacity,
			allocator = allocator,
		},
		.None
}

shader_pool_reserve :: proc(pool: ^Shader_Pool) -> (index: u32, slot: ^Shader_Slot) {
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

shader_pool_publish :: proc(pool: ^Shader_Pool, index: u32) -> Shader_Handle {
	slot := &pool.slots[index]
	assert(slot.state == .Reserved)

	slot.state = .Live
	return Shader_Handle{index = index, generation = slot.generation}
}

shader_pool_return_slot :: proc(pool: ^Shader_Pool, index: u32) {
	generation := pool.slots[index].generation

	pool.slots[index] = Shader_Slot {
		generation = generation,
		state      = .Free,
	}

	assert(pool.free_count < len(pool.free_indices))
	pool.free_indices[pool.free_count] = index
	pool.free_count += 1
}

shader_pool_cancel :: proc(pool: ^Shader_Pool, index: u32) {
	assert(pool.slots[index].state == .Reserved)
	shader_pool_return_slot(pool, index)
}

shader_pool_lookup :: proc(pool: ^Shader_Pool, handle: Shader_Handle) -> ^Shader_Slot {
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

shader_pool_retire :: proc(pool: ^Shader_Pool, handle: Shader_Handle) -> bool {
	slot := shader_pool_lookup(pool, handle)
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

shader_pool_finish_retirement :: proc(pool: ^Shader_Pool, index: u32) {
	slot := &pool.slots[index]
	assert(slot.state == .Retiring)

	if slot.generation == 0 {
		slot^ = Shader_Slot {
			state = .Exhausted,
		}
		return
	}

	shader_pool_return_slot(pool, index)
}

shader_pool_destroy :: proc(pool: ^Shader_Pool) -> bool {
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
