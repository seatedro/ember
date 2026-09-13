package rhi

import "../core/pool"
import "backend"
import "types"

Error :: types.Error
Device_Context :: backend.Device_Context

Device :: struct {
	initialized:    bool,
	buffers:        pool.Pool(Buffer_Resource, Buffer_Handle),
	shaders:        pool.Pool(Shader_Resource, Shader_Handle),
	pipelines:      pool.Pool(Pipeline_Resource, Pipeline_Handle),
	textures:       pool.Pool(Texture_Resource, Texture_Handle),
	render_targets: pool.Pool(Render_Target_Resource, Render_Target_Handle),
	frame_active:   bool,
	frame_size:     [2]i32,
	pass_active:    bool,
	pass_viewport:  Viewport,
	pass_target:    Render_Target_Handle,
	bindings:       Bindings,
	native:         backend.Device,
}

create_device :: proc(
	platform_context: Device_Context,
	buffer_capacity := 1024,
	allocator := context.allocator,
	shader_capacity := 128,
	pipeline_capacity := 128,
	texture_capacity := 256,
) -> (
	Device,
	Error,
) {
	buffers, pool_error := pool.create(Buffer_Resource, Buffer_Handle, buffer_capacity, allocator)
	if pool_error != .None {
		if pool_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}

		return {}, .Allocation_Failed
	}

	shaders, shader_error := pool.create(
		Shader_Resource,
		Shader_Handle,
		shader_capacity,
		allocator,
	)
	if shader_error != .None {
		pool.destroy(&buffers)
		if shader_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}

		return {}, .Allocation_Failed
	}

	pipelines, pipeline_error := pool.create(
		Pipeline_Resource,
		Pipeline_Handle,
		pipeline_capacity,
		allocator,
	)
	if pipeline_error != .None {
		pool.destroy(&shaders)
		pool.destroy(&buffers)
		if pipeline_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}

		return {}, .Allocation_Failed
	}

	textures, texture_error := pool.create(
		Texture_Resource,
		Texture_Handle,
		texture_capacity,
		allocator,
	)
	if texture_error != .None {
		pool.destroy(&pipelines)
		pool.destroy(&shaders)
		pool.destroy(&buffers)
		if texture_error == .Invalid_Capacity {
			return {}, .Invalid_Capacity
		}

		return {}, .Allocation_Failed
	}

	targets, target_error := pool.create(
		Render_Target_Resource,
		Render_Target_Handle,
		texture_capacity,
		allocator,
	)
	if target_error != .None {
		pool.destroy(&textures)
		pool.destroy(&pipelines)
		pool.destroy(&shaders)
		pool.destroy(&buffers)
		return {}, .Allocation_Failed
	}

	native, err := backend.create_device(platform_context)
	if err != .None {
		pool.destroy(&targets)
		pool.destroy(&textures)
		pool.destroy(&pipelines)
		pool.destroy(&shaders)
		pool.destroy(&buffers)
		return {}, err
	}

	return Device {
			initialized = true,
			buffers = buffers,
			shaders = shaders,
			pipelines = pipelines,
			textures = textures,
			render_targets = targets,
			native = native,
		},
		.None
}

validate_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .Device_Not_Initialized
	}

	return backend.validate_context(&device.native)
}

destroy_device :: proc(device: ^Device) -> Error {
	if device == nil || !device.initialized {
		return .None
	}

	if err := validate_device(device); err != .None {
		return err
	}

	if err := discard_frame(device); err != .None {
		return err
	}

	if err := backend.wait_idle(&device.native); err != .None {
		return err
	}

	for slot, index in device.render_targets.slots {
		if slot.used {
			if err := destroy_render_target(device, {u32(index), slot.generation}); err != .None {
				return err
			}
		}
	}

	for &slot, index in device.pipelines.slots {
		if slot.used {
			if err := backend.destroy_pipeline(&device.native, &slot.value.native); err != .None {
				return err
			}

			pool.free(&device.pipelines, Pipeline_Handle{u32(index), slot.generation})
		}
	}

	for &slot, index in device.buffers.slots {
		if slot.used {
			if err := backend.destroy_buffer(&device.native, &slot.value.native); err != .None {
				return err
			}

			pool.free(&device.buffers, Buffer_Handle{u32(index), slot.generation})
		}
	}

	for &slot, index in device.textures.slots {
		if slot.used {
			if err := backend.destroy_texture(&device.native, &slot.value.native); err != .None {
				return err
			}

			pool.free(&device.textures, Texture_Handle{u32(index), slot.generation})
		}
	}

	for &slot, index in device.shaders.slots {
		if slot.used {
			if err := backend.destroy_shader(&device.native, &slot.value.native); err != .None {
				return err
			}

			pool.free(&device.shaders, Shader_Handle{u32(index), slot.generation})
		}
	}

	if err := backend.destroy_device(&device.native); err != .None {
		return err
	}

	ok := pool.destroy(&device.buffers)
	assert(ok, "Device has an unfinished buffer operation")
	ok = pool.destroy(&device.shaders)
	assert(ok, "Device has an unfinished shader operation")
	ok = pool.destroy(&device.pipelines)
	assert(ok, "Device has an unfinished pipeline operation")
	ok = pool.destroy(&device.textures)
	assert(ok, "Device has an unfinished texture operation")
	ok = pool.destroy(&device.render_targets)
	assert(ok, "Device has an unfinished render target operation")
	device^ = {}

	return .None
}
