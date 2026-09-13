package renderer

import "../camera"
import emath "../core/math"
import "../rhi"
import "core:math"
import "core:mem"
import "core:slice"

Billboard :: struct {
	position: emath.Vec3,
	size:     [2]f32,
	rotation: f32,
	color:    emath.Vec4,
}

Billboard_Blend :: enum {
	Alpha,
	Additive,
}

Billboard_Renderer :: struct {
	device:                             ^rhi.Device,
	pipelines:                          [Billboard_Blend]rhi.Pipeline_Handle,
	shaders:                            [2]rhi.Shader_Handle,
	vertices, indices, instances, view: rhi.Buffer_Handle,
	white:                              rhi.Texture_Handle,
	entries:                            []Billboard_Entry,
	allocator:                          mem.Allocator,
	stats:                              Draw_Stats,
}

@(private)
Billboard_Entry :: struct {
	billboard: Billboard,
	depth:     f32,
}

@(private)
Billboard_View :: struct {
	view_projection: emath.Mat4,
	right, up:       emath.Vec4,
}

@(private)
BILLBOARD_SOURCES :: #partial [rhi.Shader_Language][2]rhi.Shader_Source {
	.MSL  = {
		{entry_point = "vertex_main", code = #load("msl/billboard.metal", string)},
		{entry_point = "fragment_main", code = #load("msl/billboard.metal", string)},
	},
	.GLSL = {
		{entry_point = "main", code = #load("glsl/billboard.vert", string)},
		{entry_point = "main", code = #load("glsl/billboard.frag", string)},
	},
}

create_billboard_renderer :: proc(
	device: ^rhi.Device,
	capacity: int,
	allocator := context.allocator,
) -> (
	renderer: Billboard_Renderer,
	err: Error,
) {
	if capacity <= 0 ||
	   capacity > max(int) / size_of(Billboard_Entry) ||
	   u64(capacity) > u64(max(i32)) {
		return {}, .Invalid_Size
	}

	renderer.device, renderer.allocator = device, allocator
	success := false
	defer {
		if !success {
			destroy_billboard_renderer(&renderer)
		}
	}

	allocation_error: mem.Allocator_Error
	renderer.entries, allocation_error = make([]Billboard_Entry, capacity, allocator)
	if allocation_error != .None {
		return renderer, .Allocation_Failed
	}

	sources := BILLBOARD_SOURCES[rhi.SHADER_LANGUAGE]
	for stage, i in ([2]rhi.Shader_Stage{.Vertex, .Fragment}) {
		renderer.shaders[i], err = rhi.create_shader(
			device,
			{
				stage = stage,
				language = rhi.SHADER_LANGUAGE,
				source = sources[i],
				label = "billboard",
			},
		)
		if err != .None {
			return
		}
	}

	for blend in Billboard_Blend {
		renderer.pipelines[blend], err = rhi.create_pipeline(
			device,
			{
				vertex_shader = renderer.shaders[0],
				fragment_shader = renderer.shaders[1],
				label = "billboards",
				uniform_blocks = {{name = "View", binding = 0}},
				textures = {{name = "source_texture", binding = 0}},
				settings = {
					layout = {
						stride = 16,
						attribute_count = 2,
						attributes = {
							0 = {location = 0, format = .F32x2, offset = 0},
							1 = {location = 1, format = .F32x2, offset = 8},
						},
					},
					instance_layout = {
						stride = size_of(Billboard_Entry),
						attribute_count = 4,
						attributes = {
							0 = {
								location = 3,
								format = .F32x3,
								offset = u32(offset_of(Billboard, position)),
							},
							1 = {
								location = 4,
								format = .F32x2,
								offset = u32(offset_of(Billboard, size)),
							},
							2 = {
								location = 5,
								format = .F32,
								offset = u32(offset_of(Billboard, rotation)),
							},
							3 = {
								location = 6,
								format = .F32x4,
								offset = u32(offset_of(Billboard, color)),
							},
						},
					},
					depth = {test_enabled = true, write_enabled = false, compare = .Less_Equal},
					blend = {
						enabled = true,
						src_factor_rgb = .Src_Alpha,
						dst_factor_rgb = .One if blend == .Additive else .One_Minus_Src_Alpha,
						src_factor_alpha = .One,
						dst_factor_alpha = .One_Minus_Src_Alpha,
					},
				},
			},
		)
		if err != .None {
			return
		}
	}

	vertices := [4][4]f32 {
		{-0.5, -0.5, 0, 0},
		{0.5, -0.5, 1, 0},
		{0.5, 0.5, 1, 1},
		{-0.5, 0.5, 0, 1},
	}

	indices := [6]u16{0, 1, 2, 2, 3, 0}
	renderer.vertices, err = rhi.create_buffer(
		device,
		{size = size_of(vertices), usage = {.Vertex}, label = "billboard quad"},
		mem.slice_to_bytes(vertices[:]),
	)
	if err != .None {
		return
	}

	renderer.indices, err = rhi.create_buffer(
		device,
		{size = size_of(indices), usage = {.Index}, label = "billboard indices"},
		mem.slice_to_bytes(indices[:]),
	)
	if err != .None {
		return
	}

	renderer.instances, err = rhi.create_buffer(
		device,
		{
			size = u64(capacity) * size_of(Billboard_Entry),
			usage = {.Vertex},
			label = "billboard instances",
		},
	)
	if err != .None {
		return
	}

	renderer.view, err = rhi.create_buffer(
		device,
		{size = size_of(Billboard_View), usage = {.Uniform}, label = "billboard view"},
	)
	if err != .None {
		return
	}

	renderer.white, err = rhi.create_texture(
		device,
		{width = 1, height = 1, format = .RGBA8, label = "billboard white"},
		{255, 255, 255, 255},
	)
	success = err == .None
	return
}

// Call within the world pass after opaque geometry. Alpha ordering covers this entire slice.
draw_billboards :: proc(
	renderer: ^Billboard_Renderer,
	billboards: []Billboard,
	view: camera.Camera,
	projection: emath.Mat4,
	blend: Billboard_Blend = .Alpha,
	texture: Texture = {},
) -> Error {
	renderer.stats = {
		submitted = len(billboards),
	}

	device := renderer.device
	if err := rhi.validate_device(device); err != .None {
		return err
	}

	if !device.pass_active {
		return .Invalid_Pass
	}

	if len(billboards) > len(renderer.entries) {
		return .Invalid_Size
	}

	if blend < .Alpha || blend > .Additive {
		return .Invalid_Draw
	}

	view_matrix := camera.view_matrix(view)
	view_projection := projection * view_matrix
	count, err := prepare_billboards(
		renderer.entries,
		billboards,
		view_matrix,
		emath.frustum_from_matrix(view_projection),
		blend,
	)
	if err != .None || count == 0 {
		return err
	}

	renderer.stats.visible = count
	uniforms := [1]Billboard_View {
		{
			view_projection = view_projection,
			right = {view_matrix[0, 0], view_matrix[0, 1], view_matrix[0, 2], 0},
			up = {view_matrix[1, 0], view_matrix[1, 1], view_matrix[1, 2], 0},
		},
	}

	if err = rhi.update_buffer(device, renderer.view, 0, mem.slice_to_bytes(uniforms[:]));
	   err != .None {
		return err
	}

	if err = rhi.update_buffer(
		device,
		renderer.instances,
		0,
		mem.slice_to_bytes(renderer.entries[:count]),
	); err != .None {
		return err
	}

	if err = rhi.bind_pipeline(device, renderer.pipelines[blend]); err != .None {
		return err
	}

	if err = rhi.bind_vertex_buffer(device, renderer.vertices); err != .None {
		return err
	}

	if err = rhi.bind_instance_buffer(device, renderer.instances); err != .None {
		return err
	}

	if err = rhi.bind_index_buffer(device, renderer.indices, .U16); err != .None {
		return err
	}

	if err = rhi.bind_uniform_buffer(device, 0, renderer.view); err != .None {
		return err
	}

	handle := texture.handle if texture.handle.generation != 0 else renderer.white
	if err = rhi.bind_texture(device, 0, handle); err != .None {
		return err
	}

	if err = rhi.draw_indexed(device, {index_count = 6, instance_count = u32(count)});
	   err == .None {
		renderer.stats.draw_calls = 1
	}

	return err
}

@(private)
prepare_billboards :: proc(
	entries: []Billboard_Entry,
	billboards: []Billboard,
	view: emath.Mat4,
	frustum: emath.Frustum,
	blend: Billboard_Blend,
) -> (
	int,
	Error,
) {
	count := 0
	for billboard in billboards {
		for value in ([10]f32{billboard.position.x, billboard.position.y, billboard.position.z, billboard.size.x, billboard.size.y, billboard.rotation, billboard.color.r, billboard.color.g, billboard.color.b, billboard.color.a}) {
			if math.is_nan(value) || math.is_inf(value) {
				return 0, .Invalid_Draw
			}
		}

		if billboard.size.x < 0 ||
		   billboard.size.y < 0 ||
		   billboard.color.a < 0 ||
		   billboard.color.a > 1 {
			return 0, .Invalid_Draw
		}

		if billboard.size.x == 0 || billboard.size.y == 0 || billboard.color.a == 0 {
			continue
		}

		radius :=
			0.5 *
			math.sqrt(billboard.size.x * billboard.size.x + billboard.size.y * billboard.size.y)
		if !emath.sphere_in_frustum(frustum, {center = billboard.position, radius = radius}) {
			continue
		}

		position := billboard.position
		depth := (view * emath.Vec4{position.x, position.y, position.z, 1}).z
		entries[count] = {billboard, depth}
		count += 1
	}

	if blend == .Alpha {
		slice.sort_by(entries[:count], proc(a, b: Billboard_Entry) -> bool {
			return a.depth < b.depth
		})
	}

	return count, .None
}

destroy_billboard_renderer :: proc(renderer: ^Billboard_Renderer) -> (result: Error) {
	device := renderer.device
	for handle in ([4]^rhi.Buffer_Handle{&renderer.vertices, &renderer.indices, &renderer.instances, &renderer.view}) {
		if handle.generation != 0 {
			if err := rhi.destroy_buffer(device, handle^); err != .None {
				result = err
			} else {
				handle^ = {}
			}
		}
	}

	for &handle in renderer.pipelines {
		if handle.generation != 0 {
			if err := rhi.destroy_pipeline(device, handle); err != .None {
				result = err
			} else {
				handle = {}
			}
		}
	}

	for &handle in renderer.shaders {
		if handle.generation != 0 {
			if err := rhi.destroy_shader(device, handle); err != .None {
				result = err
			} else {
				handle = {}
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
		delete(renderer.entries, renderer.allocator)
		renderer^ = {}
	}

	return
}
