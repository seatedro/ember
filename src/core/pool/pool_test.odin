package pool

import "core:mem"
import "core:testing"

Test_Handle :: struct {
	index, generation: u32,
}

@(test)
test_reuse_rejects_stale_handles :: proc(t: ^testing.T) {
	pool, err := create(int, Test_Handle, 2)
	testing.expect(t, err == .None)

	a, first := alloc(&pool)
	b, second := alloc(&pool)
	first^, second^ = 42, 99
	full, missing := alloc(&pool)
	testing.expect(t, full == Test_Handle{} && missing == nil)
	testing.expect(t, !destroy(&pool))
	testing.expect(t, get(&pool, Test_Handle{}) == nil)
	testing.expect(t, get(&pool, Test_Handle{max(u32), 1}) == nil)
	testing.expect(t, !free(&pool, Test_Handle{a.index, a.generation + 1}))
	testing.expect(t, get(&pool, a) == first && first^ == 42)

	testing.expect(t, free(&pool, a))
	testing.expect(t, !free(&pool, a))
	c, replacement := alloc(&pool)
	testing.expect(t, c.index == a.index && c.generation != a.generation)
	testing.expect(t, replacement^ == 0)
	testing.expect(t, get(&pool, a) == nil)
	testing.expect(t, !free(&pool, a))
	testing.expect(t, get(&pool, b) == second && second^ == 99)
	testing.expect(t, get(&pool, c) == replacement)

	testing.expect(t, free(&pool, b))
	testing.expect(t, free(&pool, c))
	testing.expect(t, destroy(&pool))
	testing.expect(t, get(&pool, c) == nil)
}

@(test)
test_generation_overflow_does_not_reuse_slot :: proc(t: ^testing.T) {
	pool, err := create(int, Test_Handle, 1)
	testing.expect(t, err == .None)
	pool.slots[0].generation = max(u32)
	handle, value := alloc(&pool)
	testing.expect(t, value != nil)
	testing.expect(t, free(&pool, handle))
	testing.expect(t, get(&pool, handle) == nil)
	missing, exhausted := alloc(&pool)
	testing.expect(t, missing == Test_Handle{} && exhausted == nil)
	testing.expect(t, destroy(&pool))
}

Failing_Allocator :: struct {
	backing:   mem.Allocator,
	remaining: int,
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]u8,
	mem.Allocator_Error,
) {
	allocator := cast(^Failing_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		if allocator.remaining == 0 {
			return nil, .Out_Of_Memory
		}

		allocator.remaining -= 1
	}

	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(test)
test_failed_creation_releases_allocations :: proc(t: ^testing.T) {
	for capacity in ([]int{0, -1, max(int)}) {
		pool, err := create(int, Test_Handle, capacity)
		testing.expect(t, err == .Invalid_Capacity && len(pool.slots) == 0)
	}

	for failure in 0 ..< 2 {
		allocator := Failing_Allocator{context.allocator, failure}
		pool, err := create(
			int,
			Test_Handle,
			2,
			{procedure = failing_allocator_proc, data = &allocator},
		)
		testing.expect(t, err == .Allocation_Failed)
		testing.expect(t, len(pool.slots) == 0 && len(pool.free_indices) == 0)
	}
}
