package rhi

import "../core/pool"
import "backend"
import "types"

Shader_Handle :: types.Shader_Handle

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

	handle, slot := pool.alloc(&device.shaders)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	native, err := backend.create_shader(desc, device.shaders.allocator)
	if err != .None {
		pool.free(&device.shaders, handle)
		return {}, err
	}

	slot.stage = desc.stage
	slot.native = native
	return handle, .None
}

destroy_shader :: proc(device: ^Device, handle: Shader_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.shaders, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := backend.destroy_shader(&slot.native); err != .None {
		return err
	}

	pool.free(&device.shaders, handle)
	return .None
}

Shader_Resource :: struct {
	stage:  Shader_Stage,
	native: backend.Shader,
}
