package rhi

import "core:testing"

@(test)
test_pipeline_pool_lifecycle :: proc(t: ^testing.T) {
	pool, err := pipeline_pool_create(1)
	testing.expect_value(t, err, Pipeline_Pool_Error.None)
	if err != .None {
		return
	}
	index, slot := pipeline_pool_reserve(&pool)
	assert(slot != nil)
	testing.expect(t, !pipeline_pool_destroy(&pool))
	testing.expect(t, pipeline_pool_lookup(&pool, Pipeline_Handle{index, slot.generation}) == nil)
	slot.settings.layout.stride = 12
	pipeline_pool_cancel(&pool, index)
	index, slot = pipeline_pool_reserve(&pool)
	assert(slot != nil)
	testing.expect_value(t, slot.settings.layout.stride, u32(0))
	handle := pipeline_pool_publish(&pool, index)
	testing.expect(t, pipeline_pool_lookup(&pool, handle) == slot)
	testing.expect(t, pipeline_pool_lookup(&pool, {}) == nil)
	testing.expect(t, pipeline_pool_lookup(&pool, Pipeline_Handle{max(u32), 1}) == nil)
	testing.expect(t, !pipeline_pool_destroy(&pool))
	testing.expect(t, pipeline_pool_retire(&pool, handle))
	testing.expect(t, !pipeline_pool_retire(&pool, handle))
	testing.expect(t, pipeline_pool_lookup(&pool, handle) == nil)
	testing.expect(t, !pipeline_pool_destroy(&pool))
	_, unavailable := pipeline_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	// No native module exists in this CPU fixture.
	pipeline_pool_finish_retirement(&pool, index)
	index, slot = pipeline_pool_reserve(&pool)
	assert(slot != nil)
	next_handle := pipeline_pool_publish(&pool, index)
	testing.expect(t, next_handle.generation != handle.generation)
	testing.expect(t, pipeline_pool_lookup(&pool, handle) == nil)
	testing.expect(t, pipeline_pool_retire(&pool, next_handle))
	pipeline_pool_finish_retirement(&pool, index)

	// Exhausting the generation must permanently remove the slot.
	index, slot = pipeline_pool_reserve(&pool)
	assert(slot != nil)
	slot.generation = max(u32)
	last_handle := pipeline_pool_publish(&pool, index)
	testing.expect(t, pipeline_pool_retire(&pool, last_handle))
	testing.expect_value(t, slot.generation, u32(0))
	pipeline_pool_finish_retirement(&pool, index)
	testing.expect_value(t, slot.state, Pipeline_State.Exhausted)
	_, unavailable = pipeline_pool_reserve(&pool)
	testing.expect(t, unavailable == nil)
	testing.expect(t, pipeline_pool_destroy(&pool))
}

@(test)
test_pipeline_layout_validation :: proc(t: ^testing.T) {
	valid := Pipeline_Settings {
		layout = {
			stride = 12,
			attribute_count = 1,
			attributes = {0 = {location = 0, format = .F32x3}},
		},
	}
	testing.expect_value(t, validate_pipeline_settings(valid), Error.None)
	invalid := valid
	invalid.layout.attribute_count = 0
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.attribute_count = MAX_VERTEX_ATTRIBUTES + 1
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.attribute_count = 2
	invalid.layout.attributes[1] = valid.layout.attributes[0]
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.attributes[0].offset = max(u32) - 3
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.attributes[0].location = MAX_VERTEX_ATTRIBUTES
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.attributes[0].format = Vertex_Format(99)
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.layout.stride = 8
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Vertex_Layout)
	invalid = valid
	invalid.raster.cull = Cull_Mode(99)
	testing.expect_value(t, validate_pipeline_settings(invalid), Error.Invalid_Pipeline_State)
	device: Device
	_, err := create_pipeline(&device, {})
	testing.expect_value(t, err, Error.Device_Not_Initialized)
	_, capacity_error := create_device({}, pipeline_capacity = 0)
	testing.expect_value(t, capacity_error, Error.Invalid_Capacity)
}

@(test)
test_indexed_draw_ranges :: proc(t: ^testing.T) {
	testing.expect_value(t, validate_indexed_range({index_count = 3}, .U16, 0, 6), Error.None)
	testing.expect_value(t, validate_indexed_range({index_count = 3}, .U16, 2, 8), Error.None)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = 3, first_index = 1}, .U32, 0, 16),
		Error.None,
	)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = 3, first_index = 1}, .U16, 0, 6),
		Error.Invalid_Draw,
	)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = 3}, .U16, 1, 8),
		Error.Invalid_Draw,
	)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = 3}, .U32, 0, 6),
		Error.Invalid_Draw,
	)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = 0}, .U16, 0, 6),
		Error.Invalid_Draw,
	)
	testing.expect_value(
		t,
		validate_indexed_range({index_count = max(u32)}, .U32, 0, max(u64)),
		Error.Invalid_Draw,
	)
	testing.expect_value(
		t,
		validate_indexed_range(
			{index_count = 3, first_index = max(u32)},
			.U32,
			max(u64) - 3,
			max(u64),
		),
		Error.Invalid_Draw,
	)
	device: Device
	testing.expect_value(t, draw_indexed(&device, {index_count = 3}), Error.Device_Not_Initialized)
}
