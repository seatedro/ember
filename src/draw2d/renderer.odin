package draw2d

import "../rhi"
import "core:math"
import "core:mem"

@(private)
QUAD_SOURCES :: #partial [rhi.Shader_Language][2]rhi.Shader_Source {
	.MSL  = {
		{entry_point = "vertex_main", code = #load("msl/quad.metal", string)},
		{entry_point = "fragment_main", code = #load("msl/quad.metal", string)},
	},
	.GLSL = {
		{entry_point = "main", code = #load("glsl/quad.vert", string)},
		{entry_point = "main", code = #load("glsl/quad.frag", string)},
	},
}

Renderer :: struct {
	device:            ^rhi.Device,
	pipeline:          rhi.Pipeline_Handle,
	shaders:           [2]rhi.Shader_Handle,
	view:              rhi.Buffer_Handle,
	white:             rhi.Texture_Handle,
	vertices, indices: Stream,
	draw_calls:        int,
}

@(private)
Stream :: struct {
	handle, pending: rhi.Buffer_Handle,
	capacity:        u64,
}

create :: proc(device: ^rhi.Device) -> (Renderer, Error) {
	renderer: Renderer
	err: Error
	renderer.device = device
	success := false
	defer {
		if !success {
			destroy(&renderer)
		}
	}

	renderer.shaders[0], err = rhi.create_shader(
		device,
		{
			stage = .Vertex,
			language = rhi.SHADER_LANGUAGE,
			source = QUAD_SOURCES[rhi.SHADER_LANGUAGE][0],
			label = "2D vertex",
		},
	)
	if err != .None {
		return {}, err
	}

	renderer.shaders[1], err = rhi.create_shader(
		device,
		{
			stage = .Fragment,
			language = rhi.SHADER_LANGUAGE,
			source = QUAD_SOURCES[rhi.SHADER_LANGUAGE][1],
			label = "2D fragment",
		},
	)
	if err != .None {
		return {}, err
	}

	renderer.pipeline, err = rhi.create_pipeline(
		device,
		{
			vertex_shader = renderer.shaders[0],
			fragment_shader = renderer.shaders[1],
			label = "2D quads and text",
			uniform_blocks = {{name = "View", binding = 0}},
			textures = {{name = "source_texture", binding = 0}},
			settings = {
				layout = {
					stride = size_of(Vertex),
					attribute_count = 4,
					attributes = {
						0 = {
							location = 0,
							format = .F32x2,
							offset = u32(offset_of(Vertex, position)),
						},
						1 = {location = 1, format = .F32x2, offset = u32(offset_of(Vertex, uv))},
						2 = {
							location = 2,
							format = .F32x4,
							offset = u32(offset_of(Vertex, color)),
						},
						3 = {
							location = 3,
							format = .F32,
							offset = u32(offset_of(Vertex, distance_range)),
						},
					},
				},
				blend = {
					enabled = true,
					src_factor_rgb = .Src_Alpha,
					dst_factor_rgb = .One_Minus_Src_Alpha,
					src_factor_alpha = .One,
					dst_factor_alpha = .One_Minus_Src_Alpha,
				},
			},
		},
	)
	if err != .None {
		return {}, err
	}

	renderer.view, err = rhi.create_buffer(
		device,
		{size = 16, usage = {.Uniform}, label = "2D view"},
	)
	if err != .None {
		return {}, err
	}

	renderer.white, err = rhi.create_texture(
		device,
		{width = 1, height = 1, format = .RGBA8, label = "2D white"},
		{255, 255, 255, 255},
	)
	if err != .None {
		return {}, err
	}

	success = true
	return renderer, .None
}

draw :: proc(renderer: ^Renderer, list: ^List) -> Error {
	renderer.draw_calls = 0
	device := renderer.device
	if err := rhi.validate_device(device); err != .None {
		return err
	}

	if !device.pass_active {
		return .Invalid_Pass
	}

	viewport := device.pass_viewport
	if len(list.clips) != 1 ||
	   viewport.x < 0 ||
	   viewport.y < 0 ||
	   viewport.width <= 0 ||
	   viewport.height <= 0 ||
	   i64(viewport.x) + i64(viewport.width) > i64(max(i32)) ||
	   i64(viewport.y) + i64(viewport.height) > i64(max(i32)) {
		return .Invalid_Draw
	}

	if len(list.indices) == 0 {
		return .None
	}

	if err := upload(device, &renderer.vertices, .Vertex, mem.slice_to_bytes(list.vertices[:]));
	   err != .None {
		return err
	}

	if err := upload(device, &renderer.indices, .Index, mem.slice_to_bytes(list.indices[:]));
	   err != .None {
		return err
	}

	view := [4]f32{list.size.x, list.size.y, 0, 0}
	if err := rhi.update_buffer(device, renderer.view, 0, mem.slice_to_bytes(view[:]));
	   err != .None {
		return err
	}

	if err := rhi.bind_pipeline(device, renderer.pipeline); err != .None {
		return err
	}

	if err := rhi.bind_vertex_buffer(device, renderer.vertices.handle); err != .None {
		return err
	}

	if err := rhi.bind_index_buffer(device, renderer.indices.handle, .U32); err != .None {
		return err
	}

	if err := rhi.bind_uniform_buffer(device, 0, renderer.view); err != .None {
		return err
	}

	for batch in list.batches {
		texture := batch.texture
		if texture == (rhi.Texture_Handle{}) {
			texture = renderer.white
		}

		if err := rhi.bind_texture(device, 0, texture); err != .None {
			return err
		}

		if err := rhi.draw_indexed(
			device,
			{
				first_index = batch.first_index,
				index_count = batch.index_count,
				instance_count = 1,
				scissor = scissor(batch.clip, list.size, viewport),
			},
		); err != .None {
			return err
		}

		renderer.draw_calls += 1
	}

	return .None
}

@(private)
scissor :: proc(rect: Rect, size: [2]f32, viewport: rhi.Viewport) -> rhi.Scissor {
	// Flip top-left logical coordinates into the RHI's bottom-left pixel coordinates.
	sx := f64(viewport.width) / f64(size.x)
	sy := f64(viewport.height) / f64(size.y)
	x0 := i32(math.floor(clamp(f64(rect.position.x) * sx, 0, f64(viewport.width))))
	y0 := i32(math.floor(clamp(f64(rect.position.y) * sy, 0, f64(viewport.height))))
	x1 := i32(math.ceil(clamp(f64(rect.position.x + rect.size.x) * sx, 0, f64(viewport.width))))
	y1 := i32(math.ceil(clamp(f64(rect.position.y + rect.size.y) * sy, 0, f64(viewport.height))))
	return {
		enabled = true,
		x = viewport.x + x0,
		y = viewport.y + viewport.height - y1,
		width = x1 - x0,
		height = y1 - y0,
	}
}

@(private)
upload :: proc(
	device: ^rhi.Device,
	stream: ^Stream,
	usage: rhi.Buffer_Usage,
	data: []u8,
) -> Error {
	if stream.pending.generation != 0 {
		if err := rhi.destroy_buffer(device, stream.pending); err != .None {
			return err
		}

		stream.pending = {}
	}

	if u64(len(data)) > stream.capacity {
		capacity := max(u64(len(data)), min(stream.capacity, u64(max(int)) / 2) * 2)
		buffer, err := rhi.create_buffer(
			device,
			{size = capacity, usage = {usage}, label = "2D stream"},
		)
		if err != .None {
			return err
		}

		if stream.handle.generation != 0 {
			if err := rhi.destroy_buffer(device, stream.handle); err != .None {
				stream.pending = buffer
				return err
			}
		}

		stream.handle = buffer
		stream.capacity = capacity
	}

	return rhi.update_buffer(device, stream.handle, 0, data)
}

destroy :: proc(renderer: ^Renderer) -> (result: Error) {
	device := renderer.device
	for handle in ([5]^rhi.Buffer_Handle {
			&renderer.view,
			&renderer.vertices.handle,
			&renderer.vertices.pending,
			&renderer.indices.handle,
			&renderer.indices.pending,
		}) {
		if handle.generation != 0 {
			if err := rhi.destroy_buffer(device, handle^); err != .None {
				result = err
			} else {
				handle^ = {}
			}
		}
	}

	if renderer.pipeline.generation != 0 {
		if err := rhi.destroy_pipeline(device, renderer.pipeline); err != .None {
			result = err
		} else {
			renderer.pipeline = {}
		}
	}

	for &shader in renderer.shaders {
		if shader.generation != 0 {
			if err := rhi.destroy_shader(device, shader); err != .None {
				result = err
			} else {
				shader = {}
			}
		}
	}

	if renderer.white.generation != 0 {
		if err := rhi.destroy_texture(device, renderer.white); err != .None {
			result = err
		} else {
			renderer.white = {}
		}
	}

	if result == .None {
		renderer^ = {}
	}

	return
}
