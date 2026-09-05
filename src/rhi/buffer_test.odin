package rhi

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
