package renderer

import "../assets"
import emath "../core/math"
import "../geometry"
import "../rhi"
import "../shaders"

Model_Parameters :: struct {
	base_color:     [4]f32,
	emissive:       [4]f32,
	metallic:       f32,
	roughness:      f32,
	alpha_cutoff:   f32,
	use_normal_map: b32,
}

#assert(size_of(Model_Parameters) == 48)

MAX_JOINTS :: 256

Joint_Uniforms :: struct {
	joints: [MAX_JOINTS]emath.Mat4,
}

Skinned_Vertex :: struct {
	vertex:  geometry.Vertex,
	joints:  [4]f32,
	weights: [4]f32,
}

#assert(offset_of(Skinned_Vertex, vertex) == 0)

SKINNED_VERTEX_LAYOUT :: Vertex_Layout {
	stride = size_of(Skinned_Vertex),
	attribute_count = 7,
	attributes = {
		0 = {location = 0, format = .F32x3, offset = u32(offset_of(geometry.Vertex, position))},
		1 = {location = 1, format = .F32x3, offset = u32(offset_of(geometry.Vertex, normal))},
		2 = {location = 2, format = .F32x2, offset = u32(offset_of(geometry.Vertex, uv))},
		3 = {location = 6, format = .F32x3, offset = u32(offset_of(geometry.Vertex, tangent))},
		4 = {location = 7, format = .F32x3, offset = u32(offset_of(geometry.Vertex, bitangent))},
		5 = {location = 8, format = .F32x4, offset = u32(offset_of(Skinned_Vertex, joints))},
		6 = {location = 9, format = .F32x4, offset = u32(offset_of(Skinned_Vertex, weights))},
	},
}

Model_Shading :: struct {
	single_sided, double_sided:                 Pipeline,
	skinned_single_sided, skinned_double_sided: Pipeline,
}

Model_Part :: struct {
	mesh, material: int,
	node:           int,
	skin:           int,
	double_sided:   bool,
}

Model :: struct {
	meshes:     []Mesh,
	materials:  []Material,
	textures:   []Texture,
	parts:      []Model_Part,
	skeleton:   assets.Model,
	node_order: []int,
}

Model_Error :: union {
	Error,
	assets.Library_Error,
	assets.File_Error,
}

create_model_shading :: proc(
	renderer: ^Renderer,
	static_shader, skinned_shader: shaders.Shader,
) -> (
	shading: Model_Shading,
	err: Error,
) {
	defer if err != .None {
		destroy_model_shading(renderer, &shading)
		shading = {}
	}
	shading.single_sided = create_model_pipeline(renderer, static_shader, .Back, false) or_return
	shading.double_sided = create_model_pipeline(renderer, static_shader, .None, false) or_return
	shading.skinned_single_sided = create_model_pipeline(
		renderer,
		skinned_shader,
		.Back,
		true,
	) or_return
	shading.skinned_double_sided = create_model_pipeline(
		renderer,
		skinned_shader,
		.None,
		true,
	) or_return
	return
}

destroy_model_shading :: proc(renderer: ^Renderer, shading: ^Model_Shading) -> (result: Error) {
	for err in ([4]Error {
			destroy_pipeline(renderer, &shading.single_sided),
			destroy_pipeline(renderer, &shading.double_sided),
			destroy_pipeline(renderer, &shading.skinned_single_sided),
			destroy_pipeline(renderer, &shading.skinned_double_sided),
		}) {
		if err != .None && result == .None {
			result = err
		}
	}
	return
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
	source, load_err := assets.load_model(library, id, allocator)
	if load_err != nil {
		return {}, flatten_load_error(load_err)
	}

	context.allocator = allocator
	model.skeleton = source
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

	material_count := len(source.materials) + 1
	model.materials = make([]Material, 2 * material_count)
	for variant in 0 ..< 2 {
		shader := shading.single_sided.shader
		if variant == 1 {
			shader = shading.skinned_single_sided.shader
		}
		for i in 0 ..< material_count {
			material := assets.Material {
				base_color = {1, 1, 1, 1},
				roughness  = 1,
			}
			if i < len(source.materials) {
				material = source.materials[i]
			}
			model.materials[variant * material_count + i] = create_model_material(
				renderer,
				shader,
				material,
				texture_ids[:],
				model.textures,
			) or_return
		}
	}

	model.node_order = parents_first(source.nodes)
	rest := make([]emath.Mat4, len(source.nodes), context.temp_allocator)
	for i in model.node_order {
		node := source.nodes[i]
		rest[i] = compose(node.translation, node.rotation, node.scale)
		if node.parent != assets.NO_INDEX {
			rest[i] = rest[node.parent] * rest[i]
		}
	}
	skinned_bounds := model_bounds(source, rest)
	skinned_bounds.radius *= 1.25

	mesh_keys := make([dynamic][2]int, context.temp_allocator)
	mesh_indices := make(map[[2]int]int, allocator = context.temp_allocator)
	parts := make([dynamic]Model_Part)
	for node, node_index in source.nodes {
		if node.mesh == assets.NO_INDEX {
			continue
		}
		skinned := node.skin != assets.NO_INDEX && len(source.skin_vertices) > 0
		mesh := source.meshes[node.mesh]
		for submesh_index in mesh.first_submesh ..< mesh.first_submesh + mesh.submesh_count {
			submesh := source.submeshes[submesh_index]
			key := [2]int{int(submesh_index), int(skinned)}
			mesh_index, found := mesh_indices[key]
			if !found {
				mesh_index = len(mesh_keys)
				append(&mesh_keys, key)
				mesh_indices[key] = mesh_index
			}

			material := int(submesh.material)
			if material == assets.NO_INDEX {
				material = len(source.materials)
			}
			append(
				&parts,
				Model_Part {
					mesh = mesh_index,
					material = int(skinned) * material_count + material,
					node = node_index,
					skin = int(node.skin) if skinned else assets.NO_INDEX,
					double_sided = material < len(source.materials) &&
					source.materials[material].double_sided,
				},
			)
		}
	}
	model.parts = parts[:]

	model.meshes = make([]Mesh, len(mesh_keys))
	for key, i in mesh_keys {
		submesh := source.submeshes[key[0]]
		if key[1] == 1 {
			model.meshes[i] = create_skinned_submesh(
				renderer,
				source,
				submesh,
				skinned_bounds,
			) or_return
		} else {
			model.meshes[i] = create_submesh(renderer, source, submesh) or_return
		}
	}
	drop_geometry(&model.skeleton)
	return
}

add_model :: proc(
	list: ^Draw_List,
	shading: ^Model_Shading,
	model: ^Model,
	pose: ^Model_Pose,
	transform: emath.Mat4,
) -> Error {
	for part in model.parts {
		item := Draw_Item {
			mesh     = model.meshes[part.mesh],
			material = model.materials[part.material],
		}
		if part.skin == assets.NO_INDEX {
			item.pipeline = shading.double_sided if part.double_sided else shading.single_sided
			item.transform = transform * pose.worlds[part.node]
		} else {
			item.pipeline =
				shading.skinned_double_sided if part.double_sided else shading.skinned_single_sided
			item.transform = transform
			item.joints = pose.joints[part.skin]
		}
		add_draw(list, item) or_return
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
	delete(model.node_order, allocator)
	assets.destroy_model(&model.skeleton, allocator)
	model^ = {}
	return
}

@(private = "file")
create_model_pipeline :: proc(
	renderer: ^Renderer,
	shader: shaders.Shader,
	cull: rhi.Cull_Mode,
	skinned: bool,
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
			layout = SKINNED_VERTEX_LAYOUT if skinned else VERTEX_LAYOUT,
			primitive = .Triangles,
			depth = {test_enabled = true, write_enabled = true, compare = .Less},
			raster = {cull = cull, winding = .CCW},
		},
		textures[:],
		lighting = true,
		environment = true,
		skinned = skinned,
	)
}

@(private = "file")
drop_geometry :: proc(skeleton: ^assets.Model) {
	switch indices in skeleton.indices {
	case []u16:
		delete(indices)
	case []u32:
		delete(indices)
	}
	delete(skeleton.vertices)
	delete(skeleton.skin_vertices)
	skeleton.indices = nil
	skeleton.vertices = nil
	skeleton.skin_vertices = nil
}

@(private = "file")
parents_first :: proc(nodes: []assets.Node) -> []int {
	order := make([dynamic]int, 0, len(nodes))
	placed := make([]bool, len(nodes), context.temp_allocator)
	for len(order) < len(nodes) {
		progress := false
		for node, i in nodes {
			if !placed[i] && (node.parent == assets.NO_INDEX || placed[node.parent]) {
				append(&order, i)
				placed[i] = true
				progress = true
			}
		}
		if !progress {
			break
		}
	}
	return order[:]
}

@(private = "file")
model_bounds :: proc(source: assets.Model, worlds: []emath.Mat4) -> emath.Bounding_Sphere {
	lowest := emath.Vec3{max(f32), max(f32), max(f32)}
	highest := emath.Vec3{min(f32), min(f32), min(f32)}
	for node, i in source.nodes {
		if node.mesh == assets.NO_INDEX {
			continue
		}
		mesh := source.meshes[node.mesh]
		for submesh in source.submeshes[mesh.first_submesh:][:mesh.submesh_count] {
			sphere := emath.transform_sphere_matrix(submesh.bounds, worlds[i])
			lowest = {
				min(lowest.x, sphere.center.x - sphere.radius),
				min(lowest.y, sphere.center.y - sphere.radius),
				min(lowest.z, sphere.center.z - sphere.radius),
			}
			highest = {
				max(highest.x, sphere.center.x + sphere.radius),
				max(highest.y, sphere.center.y + sphere.radius),
				max(highest.z, sphere.center.z + sphere.radius),
			}
		}
	}
	if lowest.x > highest.x {
		return {}
	}
	return {center = (lowest + highest) * 0.5, radius = emath.length(highest - lowest) * 0.5}
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
	shader: shaders.Shader,
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
		shader,
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
Submesh_Range :: struct {
	indices:         []u32,
	lowest, highest: u32,
}

@(private = "file")
submesh_range :: proc(source: assets.Model, submesh: assets.Submesh) -> Submesh_Range {
	range := Submesh_Range {
		indices = make([]u32, submesh.index_count, context.temp_allocator),
		lowest  = max(u32),
	}
	for i in 0 ..< submesh.index_count {
		index: u32
		switch all in source.indices {
		case []u16:
			index = u32(all[submesh.first_index + i])
		case []u32:
			index = all[submesh.first_index + i]
		}
		range.indices[i] = index
		range.lowest = min(range.lowest, index)
		range.highest = max(range.highest, index)
	}
	for &index in range.indices {
		index -= range.lowest
	}
	return range
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
	range := submesh_range(source, submesh)
	mesh, err := create_mesh(
		renderer,
		source.vertices[range.lowest:range.highest + 1],
		range.indices,
		VERTEX_LAYOUT,
		submesh.bounds,
	)
	if err != .None {
		return {}, err
	}
	return mesh, nil
}

@(private = "file")
create_skinned_submesh :: proc(
	renderer: ^Renderer,
	source: assets.Model,
	submesh: assets.Submesh,
	bounds: emath.Bounding_Sphere,
) -> (
	Mesh,
	Model_Error,
) {
	if submesh.index_count == 0 {
		return {}, Error.Invalid_Size
	}
	range := submesh_range(source, submesh)
	vertices := make([]Skinned_Vertex, range.highest - range.lowest + 1, context.temp_allocator)
	for &vertex, i in vertices {
		index := range.lowest + u32(i)
		influence := source.skin_vertices[index]
		vertex = {
			vertex  = source.vertices[index],
			joints  = {
				f32(influence.joints[0]),
				f32(influence.joints[1]),
				f32(influence.joints[2]),
				f32(influence.joints[3]),
			},
			weights = influence.weights,
		}
	}
	mesh, err := create_mesh(renderer, vertices, range.indices, SKINNED_VERTEX_LAYOUT, bounds)
	if err != .None {
		return {}, err
	}
	return mesh, nil
}

@(private)
compose :: proc(translation: emath.Vec3, rotation: emath.Quaternion, scale: emath.Vec3) -> emath.Mat4 {
	result := emath.rotation_matrix(rotation)
	for column in 0 ..< 3 {
		for row in 0 ..< 3 {
			result[row, column] *= scale[column]
		}
		result[column, 3] = translation[column]
	}
	return result
}
