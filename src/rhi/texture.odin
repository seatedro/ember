package rhi

import "../core/pool"
import "backend"
import "types"

Texture_Handle :: struct {
	index:      u32,
	generation: u32,
}

Texture_Desc :: types.Texture_Desc
Texture_Format :: types.Texture_Format
Texture_Filter :: types.Texture_Filter
Texture_Wrap :: types.Texture_Wrap

Texture_Resource :: struct {
	native: backend.Texture,
	owner:  Render_Target_Handle,
}

validate_texture_desc :: proc(desc: Texture_Desc, byte_count: int) -> Error {
	if desc.width <= 0 || desc.height <= 0 || byte_count < 0 {
		return .Invalid_Size
	}

	if desc.format < .RGBA8 ||
	   desc.format > .RGBA16F ||
	   desc.filter < .Linear ||
	   desc.filter > .Nearest ||
	   desc.wrap_u < .Repeat ||
	   desc.wrap_u > .Clamp ||
	   desc.wrap_v < .Repeat ||
	   desc.wrap_v > .Clamp {
		return .Invalid_Texture
	}

	pixel_size := u64(8 if desc.format == .RGBA16F else 4)
	pixel_count := u64(desc.width) * u64(desc.height)
	if pixel_count > u64(max(int)) / pixel_size || pixel_count * pixel_size != u64(byte_count) {
		return .Invalid_Size
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

	handle, slot := pool.alloc(&device.textures)
	if slot == nil {
		return {}, .Pool_Exhausted
	}

	native, err := backend.create_texture(desc, pixels)
	if err != .None {
		pool.free(&device.textures, handle)
		return {}, err
	}

	slot.native = native

	return handle, .None
}

destroy_texture :: proc(device: ^Device, handle: Texture_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.textures, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if slot.owner.generation != 0 {
		return .Resource_In_Use
	}

	return release_texture(device, handle)
}

@(private)
release_texture :: proc(device: ^Device, handle: Texture_Handle) -> Error {
	if err := validate_device(device); err != .None {
		return err
	}

	slot := pool.get(&device.textures, handle)
	if slot == nil {
		return .Invalid_Handle
	}

	if err := backend.wait_idle(); err != .None {
		return err
	}

	if err := backend.destroy_texture(&slot.native); err != .None {
		return err
	}

	pool.free(&device.textures, handle)

	return .None
}
