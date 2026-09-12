package rhi

import "backend"
import "core:mem"
import "core:strings"
import "types"

Pipeline_Handle :: struct {
	index:      u32,
	generation: u32,
}
Pipeline_State :: enum {
	Free,
	Reserved,
	Live,
	Retiring,
	Exhausted,
}
MAX_VERTEX_ATTRIBUTES :: types.MAX_VERTEX_ATTRIBUTES
Vertex_Format :: types.Vertex_Format
Vertex_Attribute :: types.Vertex_Attribute
Vertex_Layout :: types.Vertex_Layout
Compare :: types.Compare
Cull_Mode :: types.Cull_Mode
Winding :: types.Winding
Primitive :: types.Primitive
Depth_State :: types.Depth_State
Raster_State :: types.Raster_State
Pipeline_Settings :: types.Pipeline_Settings
Pipeline_Desc :: types.Pipeline_Desc
Uniform_Block_Desc :: types.Uniform_Block_Desc
MAX_UNIFORM_BINDINGS :: types.MAX_UNIFORM_BINDINGS
MAX_TEXTURE_BINDINGS :: types.MAX_TEXTURE_BINDINGS
Texture_Binding_Desc :: types.Texture_Binding_Desc

Pipeline_Slot :: struct {
	generation:       u32,
	state:            Pipeline_State,
	settings:         Pipeline_Settings,
	uniform_sizes:    [MAX_UNIFORM_BINDINGS]u64,
	texture_bindings: [MAX_TEXTURE_BINDINGS]bool,
	native:           backend.Pipeline,
}

Pipeline_Pool :: struct {
	slots:        []Pipeline_Slot,
	free_indices: []u32,
	free_count:   int,
	allocator:    mem.Allocator,
}

Pipeline_Pool_Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
}

pipeline_pool_create :: proc(
	capacity: int,
	allocator := context.allocator,
) -> (
	Pipeline_Pool,
	Pipeline_Pool_Error,
) {
	if capacity <= 0 ||
	   u64(capacity) > u64(max(u32)) ||
	   capacity > max(int) / size_of(Pipeline_Slot) {
		return {}, .Invalid_Capacity
	}

	slots, slots_error := make([]Pipeline_Slot, capacity, allocator)
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

	return Pipeline_Pool {
			slots = slots,
			free_indices = free_indices,
			free_count = capacity,
			allocator = allocator,
		},
		.None
}

pipeline_pool_reserve :: proc(pool: ^Pipeline_Pool) -> (index: u32, slot: ^Pipeline_Slot) {
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

pipeline_pool_publish :: proc(pool: ^Pipeline_Pool, index: u32) -> Pipeline_Handle {
	slot := &pool.slots[index]
	assert(slot.state == .Reserved)

	slot.state = .Live
	return Pipeline_Handle{index = index, generation = slot.generation}
}

pipeline_pool_return_slot :: proc(pool: ^Pipeline_Pool, index: u32) {
	generation := pool.slots[index].generation

	pool.slots[index] = Pipeline_Slot {
		generation = generation,
		state      = .Free,
	}

	assert(pool.free_count < len(pool.free_indices))
	pool.free_indices[pool.free_count] = index
	pool.free_count += 1
}

pipeline_pool_cancel :: proc(pool: ^Pipeline_Pool, index: u32) {
	assert(pool.slots[index].state == .Reserved)
	pipeline_pool_return_slot(pool, index)
}

pipeline_pool_lookup :: proc(pool: ^Pipeline_Pool, handle: Pipeline_Handle) -> ^Pipeline_Slot {
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

pipeline_pool_retire :: proc(pool: ^Pipeline_Pool, handle: Pipeline_Handle) -> bool {
	slot := pipeline_pool_lookup(pool, handle)
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

pipeline_pool_finish_retirement :: proc(pool: ^Pipeline_Pool, index: u32) {
	slot := &pool.slots[index]
	assert(slot.state == .Retiring)

	if slot.generation == 0 {
		slot^ = Pipeline_Slot {
			state = .Exhausted,
		}
		return
	}

	pipeline_pool_return_slot(pool, index)
}

pipeline_pool_destroy :: proc(pool: ^Pipeline_Pool) -> bool {
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

validate_vertex_layout :: proc(layout: Vertex_Layout) -> Error {
	if layout.attribute_count == 0 ||
	   layout.attribute_count > MAX_VERTEX_ATTRIBUTES ||
	   layout.stride == 0 ||
	   layout.stride > u32(max(i32)) ||
	   layout.stride % 4 != 0 {
		return .Invalid_Vertex_Layout
	}
	locations: u32
	for i in 0 ..< layout.attribute_count {
		attribute := layout.attributes[i]
		if attribute.location >= MAX_VERTEX_ATTRIBUTES ||
		   attribute.format < .F32 ||
		   attribute.format > .F32x4 ||
		   attribute.offset % 4 != 0 {
			return .Invalid_Vertex_Layout
		}
		width := (u32(attribute.format) + 1) * 4
		if attribute.offset > layout.stride || width > layout.stride - attribute.offset {
			return .Invalid_Vertex_Layout
		}
		bit := u32(1) << attribute.location
		if locations & bit != 0 {
			return .Invalid_Vertex_Layout
		}
		locations |= bit
	}
	return .None
}

validate_pipeline_settings :: proc(settings: Pipeline_Settings) -> Error {
	if err := validate_vertex_layout(settings.layout); err != .None {return err}
	if settings.depth.compare < .Less ||
	   settings.depth.compare > .Always ||
	   settings.raster.cull < .None ||
	   settings.raster.cull > .Front ||
	   settings.raster.winding < .CCW ||
	   settings.raster.winding > .CW ||
	   settings.primitive < .Triangles ||
	   settings.primitive > .Points {
		return .Invalid_Pipeline_State
	}
	return .None
}

// Linking finishes here; the linked pipeline survives destruction of its shader stages.
create_pipeline :: proc(device: ^Device, desc: Pipeline_Desc) -> (Pipeline_Handle, Error) {
	if err := validate_device(device); err != .None {
		return {}, err
	}
	if err := validate_pipeline_settings(desc.settings); err != .None {
		return {}, err
	}
	if err := validate_uniform_blocks(desc.uniform_blocks); err != .None {
		return {}, err
	}
	if err := validate_texture_bindings(desc.textures); err != .None {return {}, err}
	vertex := shader_pool_lookup(&device.shaders, desc.vertex_shader)
	fragment := shader_pool_lookup(&device.shaders, desc.fragment_shader)
	if vertex == nil || fragment == nil {
		return {}, .Invalid_Handle
	}
	if vertex.stage != .Vertex || fragment.stage != .Fragment {
		return {}, .Unsupported_Shader_Stage
	}
	index, slot := pipeline_pool_reserve(&device.pipelines)
	if slot == nil {
		return {}, .Pool_Exhausted
	}
	native, err := backend.create_pipeline(
		vertex.native,
		fragment.native,
		desc.label,
		desc.uniform_blocks,
		desc.textures,
		device.pipelines.allocator,
	)
	if err != .None {
		pipeline_pool_cancel(&device.pipelines, index)
		return {}, err
	}
	slot.native = native
	slot.settings = desc.settings
	slot.uniform_sizes = backend.pipeline_uniform_sizes(native)
	slot.texture_bindings = native.texture_bindings
	return pipeline_pool_publish(&device.pipelines, index), .None
}

validate_uniform_blocks :: proc(blocks: []Uniform_Block_Desc) -> Error {
	if len(blocks) > MAX_UNIFORM_BINDINGS {
		return .Invalid_Uniform_Binding
	}
	for block, i in blocks {
		if block.binding >= MAX_UNIFORM_BINDINGS ||
		   len(block.name) == 0 ||
		   strings.contains(block.name, "\x00") {
			return .Invalid_Uniform_Binding
		}
		for previous in blocks[:i] {
			if previous.binding == block.binding || previous.name == block.name {
				return .Invalid_Uniform_Binding
			}
		}
	}
	return .None
}

validate_texture_bindings :: proc(bindings: []Texture_Binding_Desc) -> Error {
	if len(bindings) > MAX_TEXTURE_BINDINGS {return .Invalid_Texture_Binding}
	for binding, i in bindings {
		if binding.binding >= MAX_TEXTURE_BINDINGS ||
		   len(binding.name) == 0 ||
		   strings.contains(binding.name, "\x00") {
			return .Invalid_Texture_Binding
		}
		for previous in bindings[:i] {
			if previous.binding == binding.binding || previous.name == binding.name {
				return .Invalid_Texture_Binding
			}
		}
	}
	return .None
}

destroy_pipeline :: proc(device: ^Device, handle: Pipeline_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}
	slot := pipeline_pool_lookup(&device.pipelines, handle)
	if slot == nil {
		return .Invalid_Handle
	}
	if err := backend.wait_idle(); err != .None {
		return err
	}
	if err := backend.destroy_pipeline(&slot.native); err != .None {
		return err
	}
	pipeline_pool_retire(&device.pipelines, handle)
	pipeline_pool_finish_retirement(&device.pipelines, handle.index)
	return .None
}
