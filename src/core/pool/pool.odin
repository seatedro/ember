package pool

import "core:mem"

Pool :: struct($T, $Handle: typeid) {
	slots:        []Slot(T),
	free_indices: []u32,
	free_count:   int,
	allocator:    mem.Allocator,
}

Slot :: struct($T: typeid) {
	value:      T,
	generation: u32,
	used:       bool,
}

Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
}

create :: proc(
	$T, $Handle: typeid,
	capacity: int,
	allocator := context.allocator,
) -> (
	Pool(T, Handle),
	Error,
) {
	if capacity <= 0 ||
	   u64(capacity) > u64(max(u32)) ||
	   capacity > max(int) / size_of(Slot(T)) ||
	   capacity > max(int) / size_of(u32) {
		return {}, .Invalid_Capacity
	}

	slots, err := make([]Slot(T), capacity, allocator)
	if err != .None {
		return {}, .Allocation_Failed
	}

	free_indices, indices_error := make([]u32, capacity, allocator)
	if indices_error != .None {
		delete(slots, allocator)
		return {}, .Allocation_Failed
	}

	for i in 0 ..< capacity {
		slots[i].generation = 1
		free_indices[i] = u32(capacity - i - 1)
	}

	return {
			slots = slots,
			free_indices = free_indices,
			free_count = capacity,
			allocator = allocator,
		},
		.None
}

alloc :: proc(pool: ^Pool($T, $Handle)) -> (Handle, ^T) {
	if pool.free_count == 0 {
		return {}, nil
	}

	pool.free_count -= 1
	index := pool.free_indices[pool.free_count]
	slot := &pool.slots[index]
	assert(!slot.used && slot.generation != 0)
	slot.used = true
	return Handle{index = index, generation = slot.generation}, &slot.value
}

get :: proc(pool: ^Pool($T, $Handle), handle: Handle) -> ^T {
	if handle.generation == 0 || uint(handle.index) >= uint(len(pool.slots)) {
		return nil
	}

	slot := &pool.slots[handle.index]
	if !slot.used || slot.generation != handle.generation {
		return nil
	}

	return &slot.value
}

free :: proc(pool: ^Pool($T, $Handle), handle: Handle) -> bool {
	if get(pool, handle) == nil {
		return false
	}

	slot := &pool.slots[handle.index]
	slot.value = {}
	slot.used = false

	// Never recycle a slot whose generation would wrap and validate an old handle.
	if slot.generation == max(u32) {
		slot.generation = 0
		return true
	}

	slot.generation += 1
	pool.free_indices[pool.free_count] = handle.index
	pool.free_count += 1
	return true
}

destroy :: proc(pool: ^Pool($T, $Handle)) -> bool {
	for slot in pool.slots {
		if slot.used {
			return false
		}
	}

	delete(pool.slots, pool.allocator)
	delete(pool.free_indices, pool.allocator)
	pool^ = {}
	return true
}
