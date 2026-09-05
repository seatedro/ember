package rhi

import "core:testing"

@(test)
test_shader_pool_lifecycle :: proc(t: ^testing.T) {
	pool, err := shader_pool_create(1)
	testing.expect_value(t, err, Shader_Pool_Error.None)
	if err != .None {
		return
	}
	index, slot := shader_pool_reserve(&pool)
	assert(slot != nil)
	testing.expect(t, !shader_pool_destroy(&pool))
	testing.expect(t, shader_pool_lookup(&pool, Shader_Handle{index, slot.generation}) == nil)
	slot.stage = .Fragment
	shader_pool_cancel(&pool, index)
	index, slot = shader_pool_reserve(&pool)
	assert(slot != nil)
	testing.expect_value(t, slot.stage, Shader_Stage.Vertex)
	handle := shader_pool_publish(&pool, index)
	testing.expect(t, shader_pool_lookup(&pool, handle) == slot)
	testing.expect(t, shader_pool_lookup(&pool, {}) == nil)
	testing.expect(t, shader_pool_lookup(&pool, Shader_Handle{max(u32), 1}) == nil)
	testing.expect(t, !shader_pool_destroy(&pool))
	testing.expect(t, shader_pool_retire(&pool, handle))
	testing.expect(t, !shader_pool_retire(&pool, handle))
	testing.expect(t, shader_pool_lookup(&pool, handle) == nil)
	testing.expect(t, !shader_pool_destroy(&pool))
	_, unavailable := shader_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	// No native module exists in this CPU fixture.
	shader_pool_finish_retirement(&pool, index)
	index, slot = shader_pool_reserve(&pool)
	assert(slot != nil)
	next_handle := shader_pool_publish(&pool, index)
	testing.expect(t, next_handle.generation != handle.generation)
	testing.expect(t, shader_pool_lookup(&pool, handle) == nil)
	testing.expect(t, shader_pool_retire(&pool, next_handle))
	shader_pool_finish_retirement(&pool, index)

	// Exhausting the generation must permanently remove the slot.
	index, slot = shader_pool_reserve(&pool)
	assert(slot != nil)
	slot.generation = max(u32)
	last_handle := shader_pool_publish(&pool, index)
	testing.expect(t, shader_pool_retire(&pool, last_handle))
	testing.expect_value(t, slot.generation, u32(0))
	shader_pool_finish_retirement(&pool, index)
	testing.expect_value(t, slot.state, Shader_State.Exhausted)
	_, unavailable = shader_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	testing.expect(t, shader_pool_destroy(&pool))
}

@(test)
test_shader_descriptor_validation :: proc(t: ^testing.T) {
	desc := Shader_Desc {
		stage  = .Vertex,
		source = "void main() {}",
	}
	testing.expect_value(t, validate_shader_desc(desc), Error.None)
	desc.stage = .Fragment
	testing.expect_value(t, validate_shader_desc(desc), Error.None)
	desc.stage = Shader_Stage(99)
	testing.expect_value(t, validate_shader_desc(desc), Error.Unsupported_Shader_Stage)
	desc.stage = .Vertex
	desc.source = ""
	testing.expect_value(t, validate_shader_desc(desc), Error.Invalid_Shader_Source)
	device: Device
	handle, err := create_shader(&device, desc)
	testing.expect_value(t, err, Error.Device_Not_Initialized)
	testing.expect_value(t, handle.generation, u32(0))
	testing.expect_value(t, destroy_shader(&device, {}), Error.Device_Not_Initialized)
	_, capacity_error := create_device({}, shader_capacity = 0)
	testing.expect_value(t, capacity_error, Error.Invalid_Capacity)
}
