package rhi

import "../core/pool"
import "backend"
import "types"

Texture_Handle :: struct {
	index:      u32,
	generation: u32,
}

Texture_Desc :: types.Texture_Desc
Texture_Kind :: types.Texture_Kind
Texture_Format :: types.Texture_Format
Texture_Filter :: types.Texture_Filter
Texture_Wrap :: types.Texture_Wrap

Texture_Resource :: struct {
	native: backend.Texture,
	desc:   Texture_Desc,
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

	if desc.kind < .Image_2D ||
	   desc.kind > .Cube ||
	   (desc.kind == .Cube && desc.width != desc.height) {
		return .Invalid_Texture
	}
	levels := texture_mip_count(desc.width, desc.height)
	if desc.mip_levels > levels {
		return .Invalid_Size
	}

	pixel_size := u64(8 if desc.format == .RGBA16F else 4)
	pixel_count: u64
	for level in 0 ..< max(desc.mip_levels, 1) {
		pixel_count += u64(max(desc.width >> level, 1)) * u64(max(desc.height >> level, 1))
	}
	face_count := u64(6 if desc.kind == .Cube else 1)
	if pixel_count > u64(max(int)) / pixel_size / face_count ||
	   pixel_count * pixel_size * face_count != u64(byte_count) {
		return .Invalid_Size
	}

	return .None
}

// Pixels contain complete mip levels, with cube faces ordered +X, -X, +Y, -Y, +Z, -Z within each level.
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

	native, err := backend.create_texture(&device.native, desc, pixels)
	if err != .None {
		pool.free(&device.textures, handle)
		return {}, err
	}

	slot.native = native
	slot.desc = desc

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

	if err := backend.wait_idle(&device.native); err != .None {
		return err
	}

	if err := backend.destroy_texture(&device.native, &slot.native); err != .None {
		return err
	}

	pool.free(&device.textures, handle)

	return .None
}

texture_mip_count :: proc(width, height: i32) -> u32 {
	levels: u32
	for size := max(width, height); size > 0; size >>= 1 {
		levels += 1
	}
	return levels
}
