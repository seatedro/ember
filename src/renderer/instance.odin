package renderer

import emath "../core/math"
import "../rhi"
import "core:mem"

Instance_Data :: struct {
	rows: [3][4]f32,
}

INSTANCE_LAYOUT :: Vertex_Layout {
	stride = size_of(Instance_Data),
	attribute_count = 3,
	attributes = {
		0 = {location = 3, format = .F32x4, offset = 0},
		1 = {location = 4, format = .F32x4, offset = 16},
		2 = {location = 5, format = .F32x4, offset = 32},
	},
}

pack_instance :: proc(model: emath.Mat4) -> Instance_Data {
	data: Instance_Data
	for row in 0 ..< 3 {
		for column in 0 ..< 4 {
			data.rows[row][column] = model[row, column]
		}
	}

	return data
}

@(private)
upload_instances :: proc(renderer: ^Renderer, data: []Instance_Data) -> Error {
	if len(data) == 0 ||
	   u64(len(data)) > u64(max(i32)) ||
	   len(data) > max(int) / size_of(Instance_Data) {
		return .Invalid_Size
	}

	if len(data) > renderer.instance_capacity {
		if renderer.pending_instance_buffer.generation != 0 {
			if err := rhi.destroy_buffer(renderer.device, renderer.pending_instance_buffer);
			   err != .None {
				return err
			}

			renderer.pending_instance_buffer = {}
		}

		capacity := max(
			len(data),
			min(renderer.instance_capacity, max(int) / size_of(Instance_Data) / 2) * 2,
		)
		buffer, err := rhi.create_buffer(
			renderer.device,
			{
				size = u64(capacity * size_of(Instance_Data)),
				usage = {.Vertex},
				label = "mesh instances",
			},
		)
		if err != .None {
			return err
		}

		if err := rhi.destroy_buffer(renderer.device, renderer.instance_buffer); err != .None {
			renderer.pending_instance_buffer = buffer
			return err
		}

		renderer.instance_buffer = buffer
		renderer.instance_capacity = capacity
	}

	return rhi.update_buffer(
		renderer.device,
		renderer.instance_buffer,
		0,
		mem.slice_to_bytes(data),
	)
}
