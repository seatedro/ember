package rhi

import "backend"
import "core:mem"
import "types"

Texture_Handle :: struct {
	index:      u32,
	generation: u32,
}

Texture_Desc :: types.Texture_Desc
Texture_Format :: types.Texture_Format
Texture_Filter :: types.Texture_Filter
Texture_Wrap :: types.Texture_Wrap

Texture_State :: enum {
	Free,
	Reserved,
	Live,
	Retiring,
	Exhausted,
}

Texture_Slot :: struct {
	generation: u32,
	state:      Texture_State,
	native:     backend.Texture,
}

Texture_Pool :: struct {
	slots:        []Texture_Slot,
	free_indices: []u32,
	free_count:   int,
	allocator:    mem.Allocator,
}

Texture_Pool_Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
}

texture_pool_create :: proc(
	capacity: int,
	allocator := context.allocator,
) -> (
	Texture_Pool,
	Texture_Pool_Error,
) {
	if capacity <= 0 ||
	   u64(capacity) > u64(max(u32)) ||
	   capacity > max(int) / size_of(Texture_Slot) {
		return {}, .Invalid_Capacity
	}

	slots, slots_error := make([]Texture_Slot, capacity, allocator)
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

	return Texture_Pool {
			slots = slots,
			free_indices = free_indices,
			free_count = capacity,
			allocator = allocator,
		},
		.None
}

texture_pool_reserve :: proc(pool: ^Texture_Pool) -> (index: u32, slot: ^Texture_Slot) {
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

texture_pool_publish :: proc(pool: ^Texture_Pool, index: u32) -> Texture_Handle {
	slot := &pool.slots[index]
	assert(slot.state == .Reserved)

	slot.state = .Live

	return Texture_Handle{index = index, generation = slot.generation}
}

texture_pool_return_slot :: proc(pool: ^Texture_Pool, index: u32) {
	generation := pool.slots[index].generation

	pool.slots[index] = Texture_Slot {
		generation = generation,
		state      = .Free,
	}

	assert(pool.free_count < len(pool.free_indices))
	pool.free_indices[pool.free_count] = index
	pool.free_count += 1
}

texture_pool_cancel :: proc(pool: ^Texture_Pool, index: u32) {
	assert(pool.slots[index].state == .Reserved)
	texture_pool_return_slot(pool, index)
}

texture_pool_lookup :: proc(pool: ^Texture_Pool, handle: Texture_Handle) -> ^Texture_Slot {
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

texture_pool_retire :: proc(pool: ^Texture_Pool, handle: Texture_Handle) -> bool {
	slot := texture_pool_lookup(pool, handle)
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

texture_pool_finish_retirement :: proc(pool: ^Texture_Pool, index: u32) {
	slot := &pool.slots[index]
	assert(slot.state == .Retiring)

	if slot.generation == 0 {
		slot^ = Texture_Slot {
			state = .Exhausted,
		}

		return
	}

	texture_pool_return_slot(pool, index)
}

texture_pool_destroy :: proc(pool: ^Texture_Pool) -> bool {
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

validate_texture_desc :: proc(desc: Texture_Desc, byte_count: int) -> Error {
	if desc.width <= 0 || desc.height <= 0 || byte_count < 0 {
		return .Invalid_Size
	}

	if u64(desc.width) * u64(desc.height) * 4 != u64(byte_count) {
		return .Invalid_Size
	}

	if desc.format < .RGBA8 ||
	   desc.format > .RGBA8_SRGB ||
	   desc.filter < .Linear ||
	   desc.filter > .Nearest ||
	   desc.wrap_u < .Repeat ||
	   desc.wrap_u > .Clamp ||
	   desc.wrap_v < .Repeat ||
	   desc.wrap_v > .Clamp {
		return .Invalid_Texture
	}

	return .None
}

create_texture :: proc(
	device: ^Device,
	desc: Texture_Desc,
	pixels: []u8,
) -> (
	Texture_Handle,
	Error,
) {
	if err := validate_device(device); err != .None {
		return {}, err
	}

	if err := validate_texture_desc(desc, len(pixels)); err != .None {
		return {}, err
	}

	index, slot := texture_pool_reserve(&device.textures)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	native, err := backend.create_texture(desc, pixels)
	if err != .None {
		texture_pool_cancel(&device.textures, index)
		return {}, err
	}

	slot.native = native

	return texture_pool_publish(&device.textures, index), .None
}

destroy_texture :: proc(device: ^Device, handle: Texture_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := texture_pool_lookup(&device.textures, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := backend.wait_idle(); err != .None {
		return err
	}

	if err := backend.destroy_texture(&slot.native); err != .None {
		return err
	}

	texture_pool_retire(&device.textures, handle)
	texture_pool_finish_retirement(&device.textures, handle.index)

	return .None
}
