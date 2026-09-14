package renderer

import "../rhi"

Texture :: struct {
	handle: rhi.Texture_Handle,
}

Texture_Desc :: rhi.Texture_Desc
Texture_Kind :: rhi.Texture_Kind
Texture_Format :: rhi.Texture_Format
Texture_Filter :: rhi.Texture_Filter
Texture_Wrap :: rhi.Texture_Wrap

create_texture :: proc(
	renderer: ^Renderer,
	desc: Texture_Desc,
	pixels: []u8,
) -> (
	texture: Texture,
	err: Error,
) {
	texture.handle, err = rhi.create_texture(renderer.device, desc, pixels)

	return
}

destroy_texture :: proc(renderer: ^Renderer, texture: ^Texture) -> Error {
	if texture.handle.generation != 0 {
		if err := rhi.destroy_texture(renderer.device, texture.handle); err != .None {
			return err
		}
	}

	texture^ = {}

	return .None
}
