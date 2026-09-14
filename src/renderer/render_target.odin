package renderer

import "../rhi"

Render_Target :: struct {
	handle:        rhi.Render_Target_Handle,
	color, depth:  Texture,
	width, height: i32,
}

Render_Target_Desc :: rhi.Render_Target_Desc
Viewport :: rhi.Viewport
Load_Op :: rhi.Load_Op

Pass_Desc :: struct {
	face, mip_level:        u32,
	target:                 ^Render_Target,
	viewport:               Viewport,
	color_load, depth_load: Load_Op,
}

create_render_target :: proc(
	renderer: ^Renderer,
	desc: Render_Target_Desc,
) -> (
	target: Render_Target,
	err: Error,
) {
	target.handle, err = rhi.create_render_target(renderer.device, desc)
	if target.handle.generation != 0 {
		target.color.handle, _ = rhi.render_target_color(renderer.device, target.handle)
		target.depth.handle, _ = rhi.render_target_depth(renderer.device, target.handle)
		target.width, target.height = desc.width, desc.height
	}

	return
}

destroy_render_target :: proc(renderer: ^Renderer, target: ^Render_Target) -> Error {
	if target.handle.generation != 0 {
		if err := rhi.destroy_render_target(renderer.device, target.handle); err != .None {
			return err
		}
	}

	target^ = {}
	return .None
}

begin_pass :: proc(
	renderer: ^Renderer,
	desc: Pass_Desc,
	clear_color: [4]f32 = {0.1, 0.1, 0.1, 1},
	clear_depth: f64 = 1,
) -> Error {
	pass := rhi.Pass_Desc {
		viewport   = desc.viewport,
		face       = desc.face,
		mip_level  = desc.mip_level,
		color_load = desc.color_load,
		depth_load = desc.depth_load,
	}

	if desc.target != nil {
		if desc.target.handle.generation == 0 {
			return .Invalid_Handle
		}

		pass.target = desc.target.handle
	}

	return rhi.begin_pass(renderer.device, pass, clear_color, clear_depth)
}

end_pass :: proc(renderer: ^Renderer) -> Error {
	return rhi.end_pass(renderer.device)
}
