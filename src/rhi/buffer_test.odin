package rhi

import "base:runtime"
import "core:mem"
import "core:testing"

@(test)
test_buffer_pool_lifecycle :: proc(t: ^testing.T) {
	pool, err := buffer_pool_create(1)
	testing.expect_value(t, err, Buffer_Pool_Error.None)
	if err != .None {
		return
	}

	index, slot := buffer_pool_reserve(&pool)
	assert(slot != nil)
	testing.expect(t, !buffer_pool_destroy(&pool))
	testing.expect(t, buffer_pool_lookup(&pool, Buffer_Handle{index, slot.generation}) == nil)

	slot.size = 128
	slot.usage = {.Vertex}
	handle := buffer_pool_publish(&pool, index)
	testing.expect(t, buffer_pool_lookup(&pool, handle) == slot)
	testing.expect(t, !buffer_pool_destroy(&pool))
	testing.expect(t, buffer_pool_lookup(&pool, {}) == nil)
	testing.expect(t, buffer_pool_lookup(&pool, Buffer_Handle{max(u32), 1}) == nil)

	testing.expect(t, buffer_pool_mark_used(&pool, handle, 42))
	testing.expect(t, buffer_pool_mark_used(&pool, handle, 10))
	testing.expect_value(t, slot.last_submission, u64(42))

	testing.expect(t, buffer_pool_retire(&pool, handle))
	testing.expect(t, buffer_pool_lookup(&pool, handle) == nil)
	testing.expect(t, !buffer_pool_retire(&pool, handle))
	testing.expect(t, !buffer_pool_mark_used(&pool, handle, 43))
	testing.expect(t, !buffer_pool_destroy(&pool))
	_, unavailable := buffer_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	testing.expect_value(t, slot.size, u64(128))

	// CPU-only fixture: no native resource or GPU work needs completion.
	buffer_pool_finish_retirement(&pool, index)
	next_index, next_slot := buffer_pool_reserve(&pool)
	assert(next_slot != nil)
	testing.expect_value(t, next_index, index)
	testing.expect_value(t, next_slot.size, u64(0))
	testing.expect_value(t, next_slot.last_submission, u64(0))

	next_handle := buffer_pool_publish(&pool, next_index)
	testing.expect(t, next_handle.generation != handle.generation)
	testing.expect(t, buffer_pool_lookup(&pool, handle) == nil)
	testing.expect(t, buffer_pool_lookup(&pool, next_handle) == next_slot)

	testing.expect(t, buffer_pool_retire(&pool, next_handle))
	buffer_pool_finish_retirement(&pool, next_index)
	testing.expect(t, buffer_pool_destroy(&pool))
	testing.expect_value(t, len(pool.slots), 0)
	testing.expect_value(t, len(pool.free_indices), 0)
	testing.expect_value(t, pool.free_count, 0)
}

@(test)
test_buffer_pool_cancel :: proc(t: ^testing.T) {
	pool, err := buffer_pool_create(1)
	testing.expect_value(t, err, Buffer_Pool_Error.None)
	if err != .None {
		return
	}

	index, slot := buffer_pool_reserve(&pool)
	assert(slot != nil)
	slot.size = 128
	slot.usage = {.Index}
	buffer_pool_cancel(&pool, index)

	next_index, next_slot := buffer_pool_reserve(&pool)
	assert(next_slot != nil)
	testing.expect_value(t, next_index, index)
	testing.expect_value(t, next_slot.size, u64(0))
	testing.expect_value(t, next_slot.generation, u32(1))
	buffer_pool_cancel(&pool, next_index)
	testing.expect(t, buffer_pool_destroy(&pool))
}

@(test)
test_buffer_pool_generation_exhaustion :: proc(t: ^testing.T) {
	pool, err := buffer_pool_create(1)
	testing.expect_value(t, err, Buffer_Pool_Error.None)
	if err != .None {
		return
	}

	index, slot := buffer_pool_reserve(&pool)
	assert(slot != nil)
	slot.generation = max(u32)
	handle := buffer_pool_publish(&pool, index)

	testing.expect(t, buffer_pool_retire(&pool, handle))
	testing.expect_value(t, slot.state, Buffer_State.Retiring)
	testing.expect_value(t, slot.generation, u32(0))
	testing.expect(t, !buffer_pool_destroy(&pool))
	buffer_pool_finish_retirement(&pool, index)
	testing.expect_value(t, slot.state, Buffer_State.Exhausted)
	_, unavailable := buffer_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	testing.expect(t, buffer_pool_destroy(&pool))
}

@(test)
test_buffer_descriptor_validation :: proc(t: ^testing.T) {
	valid := Buffer_Desc {
		size  = 16,
		usage = {.Vertex, .Index},
	}
	testing.expect_value(t, validate_buffer_desc(valid, 0), Error.None)
	testing.expect_value(t, validate_buffer_desc(valid, 8), Error.None)
	testing.expect_value(t, validate_buffer_desc(valid, 16), Error.None)
	testing.expect_value(t, validate_buffer_desc(valid, 17), Error.Initial_Data_Too_Large)

	desc := valid
	desc.size = 0
	testing.expect_value(t, validate_buffer_desc(desc, 0), Error.Invalid_Size)
	desc.size = u64(max(int)) + 1
	testing.expect_value(t, validate_buffer_desc(desc, 0), Error.Invalid_Size)
	desc = valid
	desc.usage = {}
	testing.expect_value(t, validate_buffer_desc(desc, 0), Error.Invalid_Usage)
	for usage in Buffer_Usage {
		if usage == .Vertex || usage == .Index || usage == .Uniform {
			continue
		}
		desc.usage = {.Vertex, usage}
		testing.expect_value(t, validate_buffer_desc(desc, 0), Error.Unsupported_Usage)
	}
	desc = valid
	for preference in ([2]Memory_Preference{.Upload, .Readback}) {
		desc.memory_preference = preference
		testing.expect_value(t, validate_buffer_desc(desc, 0), Error.Unsupported_Memory)
	}
	device: Device
	handle, err := create_buffer(&device, valid)
	testing.expect_value(t, err, Error.Device_Not_Initialized)
	testing.expect_value(t, handle.generation, u32(0))
	testing.expect_value(t, destroy_buffer(&device, {}), Error.Device_Not_Initialized)
	testing.expect_value(t, destroy_device(&device), Error.None)
}

Failing_Allocator :: struct {
	backing:     mem.Allocator,
	fail_on:     int,
	allocations: int,
	live:        int,
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location = #caller_location,
) -> (
	[]u8,
	mem.Allocator_Error,
) {
	state := cast(^Failing_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		state.allocations += 1
		if state.allocations == state.fail_on {
			return nil, .Out_Of_Memory
		}
	}
	result, err := state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
	if err == .None {
		if (mode == .Alloc || mode == .Alloc_Non_Zeroed) && len(result) != 0 {
			state.live += 1
		} else if mode == .Free && old_memory != nil {
			state.live -= 1
		}
	}
	return result, err
}

@(test)
test_buffer_pool_allocation_failure :: proc(t: ^testing.T) {
	// The device allocates two arrays per resource pool.
	for fail_on in 1 ..= 6 {
		state := Failing_Allocator {
			backing = context.allocator,
			fail_on = fail_on,
		}
		allocator := mem.Allocator {
			procedure = failing_allocator_proc,
			data      = &state,
		}
		device, err := create_device({}, 2, allocator)
		testing.expect_value(t, err, Error.Allocation_Failed)
		testing.expect(t, !device.initialized)
		testing.expect_value(t, state.live, 0)
		testing.expect_value(t, state.allocations, fail_on)
	}
	for capacity in ([2]int{0, -1}) {
		device, err := create_device({}, capacity)
		testing.expect_value(t, err, Error.Invalid_Capacity)
		testing.expect(t, !device.initialized)
	}
}

test_context_is_current :: proc(id: rawptr) -> bool {
	return (cast(^bool)id)^
}

@(test)
test_device_context_initialization_failure :: proc(t: ^testing.T) {
	state := Failing_Allocator {
		backing = context.allocator,
	}
	allocator := mem.Allocator {
		procedure = failing_allocator_proc,
		data      = &state,
	}
	current := false
	platform_context := Device_Context {
		id         = &current,
		is_current = test_context_is_current,
	}

	// Invalid/missing platform access must fail before invoking an OpenGL loader,
	// and must release both pool allocations made during device initialization.
	for bridge in ([3]Device_Context{{}, {id = &current}, platform_context}) {
		device, err := create_device(bridge, 2, allocator)
		testing.expect_value(t, err, Error.Wrong_Context)
		testing.expect(t, !device.initialized)
		testing.expect_value(t, state.live, 0)
	}
	current = true
	device, err := create_device(platform_context, 2, allocator)
	testing.expect_value(t, err, Error.Unsupported_Backend)
	testing.expect(t, !device.initialized)
	testing.expect_value(t, state.live, 0)
}

@(test)
test_buffer_update_ranges :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		validate_buffer_desc({size = 128, usage = {.Uniform}}, 128),
		Error.None,
	)
	testing.expect_value(t, validate_buffer_range(16, 0, 16), Error.None)
	testing.expect_value(t, validate_buffer_range(16, 16, 0), Error.None)
	testing.expect_value(t, validate_buffer_range(16, 12, 4), Error.None)
	testing.expect_value(t, validate_buffer_range(16, 12, 5), Error.Invalid_Buffer_Range)
	testing.expect_value(t, validate_buffer_range(16, max(u64), 0), Error.Invalid_Buffer_Range)
	device: Device
	testing.expect_value(t, update_buffer(&device, {}, 0, nil), Error.Device_Not_Initialized)
}
