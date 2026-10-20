package renderer

import "../assets"
import emath "../core/math"
import "../rhi"
import "../shaders"
import "core:mem"

Model_Parameters :: struct {
	base_color:     [4]f32,
	emissive:       [4]f32,
	metallic:       f32,
	roughness:      f32,
	alpha_cutoff:   f32,
	use_normal_map: b32,
}

#assert(size_of(Model_Parameters) == 48)

Model_Shading :: struct {
	single_sided, double_sided: Pipeline,
}

Model_Part :: struct {
	mesh, material: int,
	double_sided:   bool,
	transform:      emath.Mat4,
}

Model :: struct {
	meshes:    []Mesh,
	materials: []Material,
	textures:  []Texture,
	parts:     []Model_Part,
}

Model_Error :: union {
	Error,
	assets.Library_Error,
	assets.File_Error,
}

create_model_shading :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
) -> (
	shading: Model_Shading,
	err: Error,
) {
	shading.single_sided = create_model_pipeline(renderer, shader, .Back) or_return
	shading.double_sided, err = create_model_pipeline(renderer, shader, .None)
	if err != .None {
		destroy_pipeline(renderer, &shading.single_sided)
		return {}, err
	}
	return
}

destroy_model_shading :: proc(renderer: ^Renderer, shading: ^Model_Shading) -> Error {
	single_err := destroy_pipeline(renderer, &shading.single_sided)
	double_err := destroy_pipeline(renderer, &shading.double_sided)
	return single_err if single_err != .None else double_err
}

@(private = "file")
create_model_pipeline :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
	cull: rhi.Cull_Mode,
) -> (
	Pipeline,
	Error,
) {
	textures := [5]Texture_Binding_Desc {
		{name = "base_color_texture", binding = 0},
		{name = "normal_texture", binding = 1},
		{name = "metallic_roughness_texture", binding = 2},
		{name = "emissive_texture", binding = 3},
		{name = "occlusion_texture", binding = 8},
	}
	return create_pipeline(
		renderer,
		shader,
		{
			layout = VERTEX_LAYOUT,
			primitive = .Triangles,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = cull, winding = .CCW},
		},
		textures[:],
		lighting = true,
		environment = true,
	)
}

load_model :: proc(
	renderer: ^Renderer,
	shading: ^Model_Shading,
	library: assets.Library,
	id: assets.Asset_ID,
	allocator := context.allocator,
) -> (
	model: Model,
	err: Model_Error,
) {
	source, load_err := assets.load_model(library, id)
	if load_err != nil {
		return {}, flatten_load_error(load_err)
	}
	defer assets.destroy_model(&source)

	context.allocator = allocator
	defer if err != nil {
		destroy_model(renderer, &model)
	}

	texture_ids := make([dynamic]assets.Asset_ID, context.temp_allocator)
	for material in source.materials {
		for id in material.textures {
			if id != 0 && !contains(texture_ids[:], id) {
				append(&texture_ids, id)
			}
		}
	}

	model.textures = make([]Texture, len(texture_ids))
	for id, i in texture_ids {
		model.textures[i] = load_model_texture(renderer, library, id) or_return
	}

	model.materials = make([]Material, len(source.materials) + 1)
	for material, i in source.materials {
		model.materials[i] = create_model_material(
			renderer,
			shading,
			material,
			texture_ids[:],
			model.textures,
		) or_return
	}
	model.materials[len(source.materials)] = create_model_material(
		renderer,
		shading,
		{base_color = {1, 1, 1, 1}, metallic = 0, roughness = 1},
		nil,
		nil,
	) or_return

	model.meshes = make([]Mesh, len(source.submeshes))
	for submesh, i in source.submeshes {
		model.meshes[i] = create_submesh(renderer, source, submesh) or_return
	}

	worlds := node_world_transforms(source.nodes, context.temp_allocator)
	parts := make([dynamic]Model_Part)
	for node, i in source.nodes {
		if node.mesh == assets.NO_INDEX {
			continue
		}
		mesh := source.meshes[node.mesh]
		for submesh_index in mesh.first_submesh ..< mesh.first_submesh + mesh.submesh_count {
			material := int(source.submeshes[submesh_index].material)
			if material == assets.NO_INDEX {
				material = len(source.materials)
			}
			double_sided :=
				material < len(source.materials) && source.materials[material].double_sided
			append(
				&parts,
				Model_Part {
					mesh = int(submesh_index),
					material = material,
					double_sided = double_sided,
					transform = worlds[i],
				},
			)
		}
	}
	model.parts = parts[:]
	return
}

add_model :: proc(
	list: ^Draw_List,
	shading: ^Model_Shading,
	model: ^Model,
	transform: emath.Mat4,
) -> Error {
	for part in model.parts {
		add_draw(
			list,
			{
				pipeline = shading.double_sided if part.double_sided else shading.single_sided,
				mesh = model.meshes[part.mesh],
				material = model.materials[part.material],
				transform = transform * part.transform,
			},
		) or_return
	}
	return .None
}

destroy_model :: proc(
	renderer: ^Renderer,
	model: ^Model,
	allocator := context.allocator,
) -> (
	result: Error,
) {
	keep :: proc(result: ^Error, err: Error) {
		if err != .None && result^ == .None {
			result^ = err
		}
	}
	for &mesh in model.meshes {
		keep(&result, destroy_mesh(renderer, &mesh))
	}
	for &material in model.materials {
		keep(&result, destroy_material(renderer, &material))
	}
	for &texture in model.textures {
		keep(&result, destroy_texture(renderer, &texture))
	}
	delete(model.meshes, allocator)
	delete(model.materials, allocator)
	delete(model.textures, allocator)
	delete(model.parts, allocator)
	model^ = {}
	return
}

@(private = "file")
flatten_load_error :: proc(err: assets.Load_Error) -> Model_Error {
	switch e in err {
	case assets.Library_Error:
		return e
	case assets.File_Error:
		return e
	}
	return nil
}

@(private = "file")
contains :: proc(ids: []assets.Asset_ID, id: assets.Asset_ID) -> bool {
	for candidate in ids {
		if candidate == id {
			return true
		}
	}
	return false
}

@(private = "file")
load_model_texture :: proc(
	renderer: ^Renderer,
	library: assets.Library,
	id: assets.Asset_ID,
) -> (
	Texture,
	Model_Error,
) {
	source, load_err := assets.load_texture(library, id)
	if load_err != nil {
		return {}, flatten_load_error(load_err)
	}
	defer assets.destroy_texture(&source)

	texture, err := create_texture(
		renderer,
		{
			mip_levels = source.mip_count,
			width = i32(source.width),
			height = i32(source.height),
			format = .RGBA8_SRGB if source.format == .RGBA8_SRGB else .RGBA8,
			filter = .Linear,
			label = "model texture",
		},
		source.pixels,
	)
	if err != .None {
		return {}, err
	}
	return texture, nil
}

@(private = "file")
create_model_material :: proc(
	renderer: ^Renderer,
	shading: ^Model_Shading,
	material: assets.Material,
	ids: []assets.Asset_ID,
	textures: []Texture,
) -> (
	Material,
	Model_Error,
) {
	find :: proc(
		slot: assets.Texture_Slot,
		material: assets.Material,
		ids: []assets.Asset_ID,
		textures: []Texture,
		fallback: Texture,
	) -> Texture {
		for id, i in ids {
			if id == material.textures[slot] {
				return textures[i]
			}
		}
		return fallback
	}

	white := renderer.white_texture
	parameters := Model_Parameters {
		base_color     = material.base_color,
		emissive       = {material.emissive.x, material.emissive.y, material.emissive.z, 0},
		metallic       = material.metallic,
		roughness      = material.roughness,
		alpha_cutoff   = material.alpha_cutoff if material.alpha_mode == .Mask else 0,
		use_normal_map = b32(material.textures[.Normal] != 0),
	}
	result, err := create_material(
		renderer,
		shading.single_sided.shader,
		parameters,
		{
			{binding = 0, texture = find(.Base_Color, material, ids, textures, white)},
			{binding = 1, texture = find(.Normal, material, ids, textures, renderer.flat_normal)},
			{binding = 2, texture = find(.Metallic_Roughness, material, ids, textures, white)},
			{binding = 3, texture = find(.Emissive, material, ids, textures, white)},
			{binding = 8, texture = find(.Occlusion, material, ids, textures, white)},
		},
	)
	if err != .None {
		return {}, err
	}
	return result, nil
}

@(private = "file")
create_submesh :: proc(
	renderer: ^Renderer,
	source: assets.Model,
	submesh: assets.Submesh,
) -> (
	Mesh,
	Model_Error,
) {
	if submesh.index_count == 0 {
		return {}, Error.Invalid_Size
	}
	lowest, highest := max(u32), u32(0)
	indices := make([]u32, submesh.index_count, context.temp_allocator)
	for i in 0 ..< submesh.index_count {
		index: u32
		switch all in source.indices {
		case []u16:
			index = u32(all[submesh.first_index + i])
		case []u32:
			index = all[submesh.first_index + i]
		}
		indices[i] = index
		lowest = min(lowest, index)
		highest = max(highest, index)
	}
	for &index in indices {
		index -= lowest
	}

	mesh, err := create_mesh(
		renderer,
		source.vertices[lowest:highest + 1],
		indices,
		VERTEX_LAYOUT,
		submesh.bounds,
	)
	if err != .None {
		return {}, err
	}
	return mesh, nil
}

@(private = "file")
node_world_transforms :: proc(nodes: []assets.Node, allocator: mem.Allocator) -> []emath.Mat4 {
	worlds := make([]emath.Mat4, len(nodes), allocator)
	done := make([]bool, len(nodes), context.temp_allocator)
	resolve :: proc(i: int, nodes: []assets.Node, worlds: []emath.Mat4, done: []bool, depth: int) {
		if done[i] {
			return
		}
		node := nodes[i]
		local := emath.transform_matrix(
			{position = node.translation, orientation = node.rotation, scale = node.scale},
		)
		parent := int(node.parent)
		if parent != assets.NO_INDEX && depth < len(nodes) {
			resolve(parent, nodes, worlds, done, depth + 1)
			local = worlds[parent] * local
		}
		worlds[i] = local
		done[i] = true
	}
	for i in 0 ..< len(nodes) {
		resolve(i, nodes, worlds, done, 0)
	}
	return worlds
}
