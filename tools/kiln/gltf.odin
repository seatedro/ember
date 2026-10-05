package kiln

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "ember:assets"
import emath "ember:core/math"
import "ember:geometry"
import "vendor:cgltf"

Texture_Source :: struct {
	id:     assets.Asset_ID,
	image:  int,
	format: assets.Texture_Format,
}

Converted :: struct {
	model:    assets.Model,
	textures: []Texture_Source,
}

@(private = "file")
Builder :: struct {
	data:          ^cgltf.data,
	model_id:      assets.Asset_ID,
	node_order:    []i32,
	vertices:      [dynamic]geometry.Vertex,
	skin_vertices: [dynamic]assets.Skin_Vertex,
	skinned:       bool,
	indices:       [dynamic]u32,
	submeshes:     [dynamic]assets.Submesh,
	textures:      [dynamic]Texture_Source,
	key_times:     [dynamic]f32,
	key_values:    [dynamic]f32,
}

parse_gltf :: proc(source: []byte, path: cstring) -> (data: ^cgltf.data, problem: string) {
	result: cgltf.result
	data, result = cgltf.parse({}, raw_data(source), uint(len(source)))
	if result != .success {
		return nil, fmt.tprintf("cannot parse glTF: %v", result)
	}

	if result = cgltf.load_buffers({}, data, path); result != .success {
		cgltf.free(data)
		return nil, fmt.tprintf("cannot load buffers: %v", result)
	}

	if result = cgltf.validate(data); result != .success {
		cgltf.free(data)
		return nil, fmt.tprintf("invalid glTF: %v", result)
	}
	return data, ""
}

convert_model :: proc(
	data: ^cgltf.data,
	id: assets.Asset_ID,
) -> (
	converted: Converted,
	problem: string,
) {
	if problem = refuse_unsupported(data); problem != "" {
		return
	}

	b := Builder {
		data     = data,
		model_id = id,
	}
	model := &converted.model

	b.node_order, problem = order_nodes(data)
	if problem != "" {
		return
	}
	model.nodes = make([]assets.Node, len(data.nodes))
	for &node, i in data.nodes {
		model.nodes[b.node_order[i]], problem = convert_node(&b, &node)
		if problem != "" {
			return
		}
	}

	model.meshes = make([]assets.Mesh, len(data.meshes))
	for &mesh, i in data.meshes {
		model.meshes[i] = {
			name          = strings.clone_from_cstring(mesh.name),
			first_submesh = u32(len(b.submeshes)),
			submesh_count = u32(len(mesh.primitives)),
		}
		for &primitive, p in mesh.primitives {
			if problem = append_primitive(&b, &primitive); problem != "" {
				return {}, fmt.tprintf("mesh %q primitive %d: %s", mesh.name, p, problem)
			}
		}
	}

	model.materials = make([]assets.Material, len(data.materials))
	for &material, i in data.materials {
		model.materials[i], problem = convert_material(&b, &material)
		if problem != "" {
			return {}, fmt.tprintf("material %q: %s", material.name, problem)
		}
	}

	model.skins = make([]assets.Skin, len(data.skins))
	skin_joints: [dynamic]assets.Skin_Joint
	for &skin, i in data.skins {
		if problem = append_skin(&b, &skin, &model.skins[i], &skin_joints); problem != "" {
			return {}, fmt.tprintf("skin %q: %s", skin.name, problem)
		}
	}

	model.animations = make([]assets.Animation, len(data.animations))
	channels: [dynamic]assets.Channel
	for &animation, i in data.animations {
		model.animations[i], problem = convert_animation(&b, &animation, &channels)
		if problem != "" {
			return {}, fmt.tprintf("animation %q: %s", animation.name, problem)
		}
	}

	model.vertices = b.vertices[:]
	model.skin_vertices = b.skin_vertices[:] if b.skinned else nil
	model.indices = narrow_indices(b.indices[:], len(b.vertices))
	model.submeshes = b.submeshes[:]
	model.skin_joints = skin_joints[:]
	model.channels = channels[:]
	model.key_times = b.key_times[:]
	model.key_values = b.key_values[:]
	converted.textures = b.textures[:]

	if err := assets.validate_model(converted.model); err != .None {
		return {}, fmt.tprintf("converted model is invalid: %v", err)
	}
	return converted, ""
}

@(private = "file")
refuse_unsupported :: proc(data: ^cgltf.data) -> string {
	for &mesh in data.meshes {
		for &primitive, p in mesh.primitives {
			switch {
			case bool(primitive.has_draco_mesh_compression):
				return fmt.tprintf("mesh %q primitive %d uses Draco compression", mesh.name, p)
			case len(primitive.targets) > 0:
				return fmt.tprintf("mesh %q primitive %d has morph targets", mesh.name, p)
			case primitive.type != .triangles:
				return fmt.tprintf(
					"mesh %q primitive %d is %v, not triangles",
					mesh.name,
					p,
					primitive.type,
				)
			}
		}
	}

	for &view in data.buffer_views {
		if view.has_meshopt_compression {
			return "uses meshopt compression"
		}
	}

	for extension in data.extensions_required {
		if extension != "KHR_mesh_quantization" {
			return fmt.tprintf("requires the unsupported extension %s", extension)
		}
	}
	return ""
}

@(private = "file")
order_nodes :: proc(data: ^cgltf.data) -> (order: []i32, problem: string) {
	order = make([]i32, len(data.nodes))
	next := i32(0)
	stack: [dynamic]^cgltf.node
	defer delete(stack)

	for &root in data.nodes {
		if root.parent != nil {
			continue
		}

		append(&stack, &root)
		for len(stack) > 0 {
			node := pop(&stack)
			order[cgltf.node_index(data, node)] = next
			next += 1
			#reverse for child in node.children {
				append(&stack, child)
			}
		}
	}

	if int(next) != len(data.nodes) {
		return nil, "node hierarchy has a cycle"
	}
	return order, ""
}

@(private = "file")
convert_node :: proc(b: ^Builder, node: ^cgltf.node) -> (result: assets.Node, problem: string) {
	result = {
		name   = strings.clone_from_cstring(node.name),
		parent = assets.NO_INDEX,
		mesh   = assets.NO_INDEX,
		skin   = assets.NO_INDEX,
	}
	if node.parent != nil {
		result.parent = b.node_order[cgltf.node_index(b.data, node.parent)]
	}
	if node.mesh != nil {
		result.mesh = i32(cgltf.mesh_index(b.data, node.mesh))
	}
	if node.skin != nil {
		result.skin = i32(cgltf.skin_index(b.data, node.skin))
	}

	if !node.has_matrix {
		t, r, s := node.translation, node.rotation, node.scale
		result.translation = emath.Vec3(t)
		result.rotation = quaternion(x = r.x, y = r.y, z = r.z, w = r.w)
		result.scale = emath.Vec3(s)
		return result, ""
	}

	m := node.matrix_
	columns := [3][3]f32{{m[0], m[1], m[2]}, {m[4], m[5], m[6]}, {m[8], m[9], m[10]}}
	result.translation = {m[12], m[13], m[14]}
	for column, i in columns {
		result.scale[i] = linalg.length(column)
	}
	if linalg.dot(linalg.cross(columns[0], columns[1]), columns[2]) < 0 {
		result.scale.x = -result.scale.x
	}
	if result.scale.x == 0 || result.scale.y == 0 || result.scale.z == 0 {
		return {}, fmt.tprintf("node %q has a matrix with zero scale", node.name)
	}

	rotation: linalg.Matrix3f32
	for column, i in columns {
		for row in 0 ..< 3 {
			rotation[row, i] = column[row] / result.scale[i]
		}
	}
	result.rotation = linalg.quaternion_from_matrix3_f32(rotation)
	return result, ""
}

@(private = "file")
Attributes :: struct {
	position, normal, uv, tangent: ^cgltf.accessor,
	joints, weights:               [dynamic]^cgltf.accessor,
}

@(private = "file")
append_primitive :: proc(b: ^Builder, primitive: ^cgltf.primitive) -> string {
	a: Attributes
	defer delete(a.joints)
	defer delete(a.weights)

	for attribute in primitive.attributes {
		index := int(attribute.index)
		#partial switch attribute.type {
		case .position:
			a.position = attribute.data
		case .normal:
			a.normal = attribute.data
		case .tangent:
			a.tangent = attribute.data
		case .texcoord:
			if index == 0 {
				a.uv = attribute.data
			}
		case .joints:
			resize(&a.joints, max(len(a.joints), index + 1))
			a.joints[index] = attribute.data
		case .weights:
			resize(&a.weights, max(len(a.weights), index + 1))
			a.weights[index] = attribute.data
		}
	}

	switch {
	case a.position == nil:
		return "has no POSITION"
	case a.normal == nil:
		return "has no NORMAL"
	case a.uv == nil:
		return "has no TEXCOORD_0"
	case a.tangent == nil:
		return "has no TANGENT; export with Blender's Tangents option enabled"
	case len(a.joints) != len(a.weights):
		return "has a different number of JOINTS and WEIGHTS sets"
	}

	count := int(a.position.count)
	positions, normals, uvs, tangents: []f32
	ok: bool
	if positions, ok = read_floats(a.position, 3, count); !ok {
		return "POSITION is not one vec3 per vertex"
	}
	if normals, ok = read_floats(a.normal, 3, count); !ok {
		return "NORMAL is not one vec3 per vertex"
	}
	if uvs, ok = read_floats(a.uv, 2, count); !ok {
		return "TEXCOORD_0 is not one vec2 per vertex"
	}
	if tangents, ok = read_floats(a.tangent, 4, count); !ok {
		return "TANGENT is not one vec4 per vertex"
	}
	defer delete(positions)
	defer delete(normals)
	defer delete(uvs)
	defer delete(tangents)

	first_vertex := len(b.vertices)
	if first_vertex + count > int(max(u32)) {
		return "the model has more vertices than 32-bit indices can address"
	}

	lowest, highest :=
		[3]f32{math.F32_MAX, math.F32_MAX, math.F32_MAX},
		-[3]f32{math.F32_MAX, math.F32_MAX, math.F32_MAX}
	for i in 0 ..< count {
		position := [3]f32{positions[3 * i], positions[3 * i + 1], positions[3 * i + 2]}
		normal := [3]f32{normals[3 * i], normals[3 * i + 1], normals[3 * i + 2]}
		tangent := [3]f32{tangents[4 * i], tangents[4 * i + 1], tangents[4 * i + 2]}
		append(
			&b.vertices,
			geometry.Vertex {
				position = position,
				normal = normal,
				uv = {uvs[2 * i], uvs[2 * i + 1]},
				tangent = tangent,
				bitangent = linalg.cross(normal, tangent) * tangents[4 * i + 3],
			},
		)
		lowest = linalg.min(lowest, position)
		highest = linalg.max(highest, position)
	}

	resize(&b.skin_vertices, len(b.vertices))
	if len(a.joints) > 0 {
		b.skinned = true
		if problem := read_influences(a, b.skin_vertices[first_vertex:]); problem != "" {
			return problem
		}
	}

	first_index := len(b.indices)
	if primitive.indices == nil {
		for i in 0 ..< count {
			append(&b.indices, u32(first_vertex + i))
		}
	} else {
		if primitive.indices.is_sparse {
			return "has sparse indices"
		}
		for i in 0 ..< primitive.indices.count {
			index := int(cgltf.accessor_read_index(primitive.indices, i))
			if index >= count {
				return fmt.tprintf("index %d is past the last vertex, %d", index, count - 1)
			}
			append(&b.indices, u32(first_vertex + index))
		}
	}
	index_count := len(b.indices) - first_index
	if index_count % 3 != 0 {
		return fmt.tprintf("has %d indices, which is not a whole number of triangles", index_count)
	}

	center := (lowest + highest) / 2
	radius := f32(0)
	for &vertex in b.vertices[first_vertex:] {
		radius = max(radius, linalg.length(vertex.position - center))
	}

	material := i32(assets.NO_INDEX)
	if primitive.material != nil {
		material = i32(cgltf.material_index(b.data, primitive.material))
	}
	append(
		&b.submeshes,
		assets.Submesh {
			first_index = u32(first_index),
			index_count = u32(index_count),
			material = material,
			bounds = {emath.Vec3(center), radius},
		},
	)
	return ""
}

@(private = "file")
read_influences :: proc(a: Attributes, skin_vertices: []assets.Skin_Vertex) -> string {
	Influence :: struct {
		joint:  f32,
		weight: f32,
	}

	count := len(skin_vertices)
	joints := make([][]f32, len(a.joints))
	weights := make([][]f32, len(a.weights))
	defer {
		for set in joints {
			delete(set)
		}
		for set in weights {
			delete(set)
		}
		delete(joints)
		delete(weights)
	}

	for set in 0 ..< len(a.joints) {
		ok: bool
		if a.joints[set] == nil || a.weights[set] == nil {
			return fmt.tprintf("JOINTS_%d or WEIGHTS_%d is missing", set, set)
		}
		if joints[set], ok = read_floats(a.joints[set], 4, count); !ok {
			return fmt.tprintf("JOINTS_%d is not one vec4 per vertex", set)
		}
		if weights[set], ok = read_floats(a.weights[set], 4, count); !ok {
			return fmt.tprintf("WEIGHTS_%d is not one vec4 per vertex", set)
		}
	}

	influences := make([]Influence, 4 * len(joints))
	defer delete(influences)
	for &vertex, v in skin_vertices {
		for set in 0 ..< len(joints) {
			for k in 0 ..< 4 {
				influences[4 * set + k] = {joints[set][4 * v + k], weights[set][4 * v + k]}
			}
		}
		slice.sort_by(influences, proc(x, y: Influence) -> bool {
			return x.weight > y.weight
		})

		total := f32(0)
		for influence in influences[:4] {
			total += max(influence.weight, 0)
		}
		for influence, k in influences[:4] {
			if influence.weight <= 0 {
				continue
			}
			if influence.joint >= f32(assets.MAX_SKIN_JOINTS) {
				return fmt.tprintf(
					"joint %v is past the %d a skin can have",
					influence.joint,
					assets.MAX_SKIN_JOINTS,
				)
			}
			vertex.joints[k] = u16(influence.joint)
			vertex.weights[k] = influence.weight / total
		}
	}
	return ""
}

@(private = "file")
convert_material :: proc(
	b: ^Builder,
	material: ^cgltf.material,
) -> (
	result: assets.Material,
	problem: string,
) {
	pbr := &material.pbr_metallic_roughness
	strength :=
		material.emissive_strength.emissive_strength if material.has_emissive_strength else 1
	result = {
		name         = strings.clone_from_cstring(material.name),
		base_color   = pbr.base_color_factor,
		emissive     = material.emissive_factor * strength,
		metallic     = pbr.metallic_factor,
		roughness    = pbr.roughness_factor,
		alpha_cutoff = material.alpha_cutoff,
		alpha_mode   = assets.Alpha_Mode(material.alpha_mode),
		double_sided = bool(material.double_sided),
	}

	Slot :: struct {
		view:   ^cgltf.texture_view,
		format: assets.Texture_Format,
	}
	slots := [assets.Texture_Slot]Slot {
		.Base_Color         = {&pbr.base_color_texture, .RGBA8_SRGB},
		.Metallic_Roughness = {&pbr.metallic_roughness_texture, .RGBA8_Linear},
		.Normal             = {&material.normal_texture, .RGBA8_Linear},
		.Emissive           = {&material.emissive_texture, .RGBA8_SRGB},
		.Occlusion          = {&material.occlusion_texture, .RGBA8_Linear},
	}
	for slot, name in slots {
		view := slot.view
		if view.texture == nil {
			continue
		}

		switch {
		case bool(view.has_transform):
			return {}, fmt.tprintf("%v texture uses KHR_texture_transform", name)
		case view.texcoord != 0:
			return {}, fmt.tprintf("%v texture reads TEXCOORD_%d; only TEXCOORD_0 is converted", name, view.texcoord)
		case view.texture.image_ == nil:
			return {}, fmt.tprintf("%v texture has no PNG or JPEG image", name)
		}

		result.textures[name], problem = add_texture(b, view.texture.image_, slot.format)
		if problem != "" {
			return
		}
	}
	return result, ""
}

@(private = "file")
add_texture :: proc(
	b: ^Builder,
	image: ^cgltf.image,
	format: assets.Texture_Format,
) -> (
	assets.Asset_ID,
	string,
) {
	index := int(cgltf.image_index(b.data, image))
	name := string(image.name)
	if name == "" {
		name = fmt.tprintf("#%d", index)
	}

	id := texture_id(b.model_id, name, format)
	if id == 0 {
		return 0, fmt.tprintf("image %q hashes to the ID 0", name)
	}
	for texture in b.textures {
		if texture.id != id {
			continue
		}
		if texture.image != index || texture.format != format {
			return 0, fmt.tprintf(
				"images %d and %d have the same name, %q, and would share a texture ID",
				texture.image,
				index,
				name,
			)
		}
		return id, ""
	}
	append(&b.textures, Texture_Source{id = id, image = index, format = format})
	return id, ""
}

@(private = "file")
append_skin :: proc(
	b: ^Builder,
	skin: ^cgltf.skin,
	result: ^assets.Skin,
	skin_joints: ^[dynamic]assets.Skin_Joint,
) -> string {
	if len(skin.joints) > assets.MAX_SKIN_JOINTS {
		return fmt.tprintf(
			"has %d joints; at most %d are allowed",
			len(skin.joints),
			assets.MAX_SKIN_JOINTS,
		)
	}

	result^ = {
		first_joint = u32(len(skin_joints)),
		joint_count = u32(len(skin.joints)),
		root        = assets.NO_INDEX,
	}
	if skin.skeleton != nil {
		result.root = b.node_order[cgltf.node_index(b.data, skin.skeleton)]
	}

	matrices: []f32
	defer delete(matrices)
	if skin.inverse_bind_matrices != nil {
		ok: bool
		if matrices, ok = read_floats(skin.inverse_bind_matrices, 16, len(skin.joints)); !ok {
			return "inverse bind matrices are not one mat4 per joint"
		}
	}

	for joint, j in skin.joints {
		inverse_bind := linalg.MATRIX4F32_IDENTITY
		if matrices != nil {
			for column in 0 ..< 4 {
				for row in 0 ..< 4 {
					inverse_bind[row, column] = matrices[16 * j + 4 * column + row]
				}
			}
		}
		append(
			skin_joints,
			assets.Skin_Joint {
				node = u32(b.node_order[cgltf.node_index(b.data, joint)]),
				inverse_bind = inverse_bind,
			},
		)
	}
	return ""
}

@(private = "file")
convert_animation :: proc(
	b: ^Builder,
	animation: ^cgltf.animation,
	channels: ^[dynamic]assets.Channel,
) -> (
	result: assets.Animation,
	problem: string,
) {
	result = {
		name          = strings.clone_from_cstring(animation.name),
		first_channel = u32(len(channels)),
		channel_count = u32(len(animation.channels)),
	}

	for &channel, c in animation.channels {
		if channel.target_node == nil {
			return {}, fmt.tprintf("channel %d has no target node", c)
		}

		converted := assets.Channel {
			node      = u32(b.node_order[cgltf.node_index(b.data, channel.target_node)]),
			first_key = u32(len(b.key_times)),
		}
		components := 3
		#partial switch channel.target_path {
		case .translation:
			converted.path = .Translation
		case .rotation:
			converted.path = .Rotation
			components = 4
		case .scale:
			converted.path = .Scale
		case:
			return {}, fmt.tprintf("channel %d animates %v", c, channel.target_path)
		}

		sampler := channel.sampler
		keys := int(sampler.input.count)
		values_per_key := 1
		switch sampler.interpolation {
		case .step:
			converted.interpolation = .Step
		case .linear:
			converted.interpolation = .Linear
		case .cubic_spline:
			converted.interpolation = .Cubic_Spline
			values_per_key = 3
		}

		times, times_ok := read_floats(sampler.input, 1, keys)
		defer delete(times)
		if !times_ok {
			return {}, fmt.tprintf("channel %d key times are not one scalar per key", c)
		}
		values, values_ok := read_floats(sampler.output, components, values_per_key * keys)
		defer delete(values)
		if !values_ok {
			return {}, fmt.tprintf("channel %d values do not match its key count", c)
		}

		converted.key_count = u32(keys)
		converted.first_value = u32(len(b.key_values))
		append(&b.key_times, ..times)
		append(&b.key_values, ..values)
		if keys > 0 {
			result.duration = max(result.duration, times[keys - 1])
		}
		append(channels, converted)
	}
	return result, ""
}

@(private = "file")
narrow_indices :: proc(indices: []u32, vertex_count: int) -> assets.Indices {
	if vertex_count > int(max(u16)) + 1 {
		return indices
	}
	narrow := make([]u16, len(indices))
	for index, i in indices {
		narrow[i] = u16(index)
	}
	return narrow
}

@(private = "file")
read_floats :: proc(accessor: ^cgltf.accessor, components, count: int) -> ([]f32, bool) {
	if int(cgltf.num_components(accessor.type)) != components || int(accessor.count) != count {
		return nil, false
	}
	values := make([]f32, components * count)
	if int(cgltf.accessor_unpack_floats(accessor, raw_data(values), uint(len(values)))) !=
	   len(values) {
		delete(values)
		return nil, false
	}
	return values, true
}
