package assets

import emath "../core/math"
import "../geometry"
import "core:math"

// Record sizes in bytes
NODE_SIZE :: 60
MESH_SIZE :: 16
SUBMESH_SIZE :: 28
MATERIAL_SIZE :: 96
VERTEX_SIZE :: 56
SKIN_VERTEX_SIZE :: 24
SKIN_SIZE :: 12
SKIN_JOINT_SIZE :: 68
ANIMATION_SIZE :: 20
CHANNEL_SIZE :: 24

#assert(size_of(geometry.Vertex) == VERTEX_SIZE)

NO_INDEX :: -1

Node :: struct {
	name:        string,
	parent:      i32,
	mesh:        i32,
	skin:        i32,
	translation: emath.Vec3,
	rotation:    emath.Quaternion,
	scale:       emath.Vec3,
}

Mesh :: struct {
	name:                         string,
	first_submesh, submesh_count: u32,
}

// Indices point into the model's whole vertex array.
Submesh :: struct {
	first_index, index_count: u32,
	material:                 i32,
	bounds:                   emath.Bounding_Sphere,
}

Alpha_Mode :: enum u32 {
	Opaque,
	Mask,
	Blend,
}

Texture_Slot :: enum {
	Base_Color,
	Metallic_Roughness,
	Normal,
	Emissive,
	Occlusion,
}

// A texture slot holds the converted texture's ID, or 0 for none.
Material :: struct {
	name:         string,
	base_color:   [4]f32,
	emissive:     [3]f32,
	metallic:     f32,
	roughness:    f32,
	alpha_cutoff: f32,
	alpha_mode:   Alpha_Mode,
	double_sided: bool,
	textures:     [Texture_Slot]Asset_ID,
}

// joints index the skin's joint list; weights sum to 1.
Skin_Vertex :: struct {
	joints:  [4]u16,
	weights: [4]f32,
}

MAX_SKIN_JOINTS :: int(max(u16)) + 1

// u16 when every index fits, u32 otherwise.
Indices :: union {
	[]u16,
	[]u32,
}

Skin :: struct {
	first_joint, joint_count: u32,
	root:                     i32,
}

Skin_Joint :: struct {
	node:         u32,
	inverse_bind: emath.Mat4,
}

Animation :: struct {
	name:                         string,
	duration:                     f32,
	first_channel, channel_count: u32,
}

Channel_Path :: enum u32 {
	Translation,
	Rotation,
	Scale,
}

Interpolation :: enum u32 {
	Step,
	Linear,
	// Each key stores an in-tangent, a value, and an out-tangent.
	Cubic_Spline,
}

// Keys are key_times[first_key:][:key_count]; their values start at
// key_values[first_value].
Channel :: struct {
	node:          u32,
	path:          Channel_Path,
	interpolation: Interpolation,
	first_key:     u32,
	key_count:     u32,
	first_value:   u32,
}

// skin_vertices is empty or one per vertex.
Model :: struct {
	nodes:         []Node,
	meshes:        []Mesh,
	submeshes:     []Submesh,
	materials:     []Material,
	vertices:      []geometry.Vertex,
	skin_vertices: []Skin_Vertex,
	indices:       Indices,
	skins:         []Skin,
	skin_joints:   []Skin_Joint,
	animations:    []Animation,
	channels:      []Channel,
	key_times:     []f32,
	key_values:    []f32,
}

encode_model :: proc(
	model: Model,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: File_Error,
) {
	validate_model(model) or_return
	context.allocator = context.temp_allocator

	strings_table: [dynamic]byte

	nodes := make([dynamic]byte, 0, NODE_SIZE * len(model.nodes))
	for &node in model.nodes {
		put_name(&nodes, &strings_table, node.name)
		put_i32(&nodes, node.parent)
		put_i32(&nodes, node.mesh)
		put_i32(&nodes, node.skin)
		put_f32s(&nodes, node.translation[:])
		rotation := node.rotation
		put_f32s(&nodes, {rotation.x, rotation.y, rotation.z, rotation.w})
		put_f32s(&nodes, node.scale[:])
	}

	meshes := make([dynamic]byte, 0, MESH_SIZE * len(model.meshes))
	for mesh in model.meshes {
		put_name(&meshes, &strings_table, mesh.name)
		put_u32(&meshes, mesh.first_submesh)
		put_u32(&meshes, mesh.submesh_count)
	}

	submeshes := make([dynamic]byte, 0, SUBMESH_SIZE * len(model.submeshes))
	for &submesh in model.submeshes {
		put_u32(&submeshes, submesh.first_index)
		put_u32(&submeshes, submesh.index_count)
		put_i32(&submeshes, submesh.material)
		put_f32s(&submeshes, submesh.bounds.center[:])
		put_f32s(&submeshes, {submesh.bounds.radius})
	}

	materials := make([dynamic]byte, 0, MATERIAL_SIZE * len(model.materials))
	for &m in model.materials {
		put_name(&materials, &strings_table, m.name)
		put_f32s(&materials, m.base_color[:])
		put_f32s(&materials, m.emissive[:])
		put_f32s(&materials, {m.metallic, m.roughness, m.alpha_cutoff})
		put_u32(&materials, u32(m.alpha_mode))
		put_u32(&materials, 1 if m.double_sided else 0)
		for texture in m.textures {
			put_u64(&materials, u64(texture))
		}
	}

	vertices := make([dynamic]byte, 0, VERTEX_SIZE * len(model.vertices))
	for &v in model.vertices {
		put_f32s(&vertices, v.position[:])
		put_f32s(&vertices, v.normal[:])
		put_f32s(&vertices, v.uv[:])
		put_f32s(&vertices, v.tangent[:])
		put_f32s(&vertices, v.bitangent[:])
	}

	skin_vertices := make([dynamic]byte, 0, SKIN_VERTEX_SIZE * len(model.skin_vertices))
	for &v in model.skin_vertices {
		for joint in v.joints {
			put_u16(&skin_vertices, joint)
		}
		put_f32s(&skin_vertices, v.weights[:])
	}

	indices: [dynamic]byte
	index_size := u32(2)
	switch values in model.indices {
	case []u16:
		reserve(&indices, 2 * len(values))
		for index in values {
			put_u16(&indices, index)
		}
	case []u32:
		index_size = 4
		reserve(&indices, 4 * len(values))
		for index in values {
			put_u32(&indices, index)
		}
	}

	skins := make([dynamic]byte, 0, SKIN_SIZE * len(model.skins))
	for skin in model.skins {
		put_u32(&skins, skin.first_joint)
		put_u32(&skins, skin.joint_count)
		put_i32(&skins, skin.root)
	}

	skin_joints := make([dynamic]byte, 0, SKIN_JOINT_SIZE * len(model.skin_joints))
	for joint in model.skin_joints {
		put_u32(&skin_joints, joint.node)
		for column in 0 ..< 4 {
			for row in 0 ..< 4 {
				put_f32s(&skin_joints, {joint.inverse_bind[row, column]})
			}
		}
	}

	animations := make([dynamic]byte, 0, ANIMATION_SIZE * len(model.animations))
	for animation in model.animations {
		put_name(&animations, &strings_table, animation.name)
		put_f32s(&animations, {animation.duration})
		put_u32(&animations, animation.first_channel)
		put_u32(&animations, animation.channel_count)
	}

	channels := make([dynamic]byte, 0, CHANNEL_SIZE * len(model.channels))
	for channel in model.channels {
		put_u32(&channels, channel.node)
		put_u32(&channels, u32(channel.path))
		put_u32(&channels, u32(channel.interpolation))
		put_u32(&channels, channel.first_key)
		put_u32(&channels, channel.key_count)
		put_u32(&channels, channel.first_value)
	}

	key_times := make([dynamic]byte, 0, 4 * len(model.key_times))
	put_f32s(&key_times, model.key_times)
	key_values := make([dynamic]byte, 0, 4 * len(model.key_values))
	put_f32s(&key_values, model.key_values)

	sections := []Section {
		{.Strings, 1, strings_table[:]},
		{.Nodes, NODE_SIZE, nodes[:]},
		{.Meshes, MESH_SIZE, meshes[:]},
		{.Submeshes, SUBMESH_SIZE, submeshes[:]},
		{.Materials, MATERIAL_SIZE, materials[:]},
		{.Vertices, VERTEX_SIZE, vertices[:]},
		{.Skin_Vertices, SKIN_VERTEX_SIZE, skin_vertices[:]},
		{.Indices, index_size, indices[:]},
		{.Skins, SKIN_SIZE, skins[:]},
		{.Skin_Joints, SKIN_JOINT_SIZE, skin_joints[:]},
		{.Animations, ANIMATION_SIZE, animations[:]},
		{.Channels, CHANNEL_SIZE, channels[:]},
		{.Key_Times, 4, key_times[:]},
		{.Key_Values, 4, key_values[:]},
	}
	return encode_file(MODEL_MAGIC, u64(id), sections, allocator)
}

// Everything is copied out of data, and checked the same way encode_model
// checks its input, so indices can be trusted. A failed decode keeps nothing.
decode_model :: proc(
	data: []byte,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	Model,
	File_Error,
) {
	model, err := read_model(data, id, allocator)
	if err == .None {
		err = validate_model(model)
	}
	if err != .None {
		destroy_model(&model, allocator)
		return {}, err
	}
	return model, .None
}

@(private = "file")
read_model :: proc(
	data: []byte,
	id: Asset_ID,
	allocator := context.allocator,
) -> (
	model: Model,
	err: File_Error,
) {
	sections := decode_file(data, MODEL_MAGIC, u64(id), context.temp_allocator) or_return
	table := find_section(sections, .Strings, 1) or_return
	context.allocator = allocator

	r := Reader {
		table = table,
	}

	r.data = find_section(sections, .Nodes, NODE_SIZE) or_return
	model.nodes = make_records(Node, len(r.data) / NODE_SIZE) or_return
	for &node in model.nodes {
		node.name = read_name(&r) or_return
		node.parent = read_i32(&r)
		node.mesh = read_i32(&r)
		node.skin = read_i32(&r)
		node.translation = emath.Vec3(read_vec3(&r))
		x, y, z, w := read_f32(&r), read_f32(&r), read_f32(&r), read_f32(&r)
		node.rotation = quaternion(x = x, y = y, z = z, w = w)
		node.scale = emath.Vec3(read_vec3(&r))
	}

	r.data = find_section(sections, .Meshes, MESH_SIZE) or_return
	model.meshes = make_records(Mesh, len(r.data) / MESH_SIZE) or_return
	for &mesh in model.meshes {
		mesh.name = read_name(&r) or_return
		mesh.first_submesh = read_u32(&r)
		mesh.submesh_count = read_u32(&r)
	}

	r.data = find_section(sections, .Submeshes, SUBMESH_SIZE) or_return
	model.submeshes = make_records(Submesh, len(r.data) / SUBMESH_SIZE) or_return
	for &submesh in model.submeshes {
		submesh.first_index = read_u32(&r)
		submesh.index_count = read_u32(&r)
		submesh.material = read_i32(&r)
		submesh.bounds = {emath.Vec3(read_vec3(&r)), read_f32(&r)}
	}

	r.data = find_section(sections, .Materials, MATERIAL_SIZE) or_return
	model.materials = make_records(Material, len(r.data) / MATERIAL_SIZE) or_return
	for &material in model.materials {
		material.name = read_name(&r) or_return
		material.base_color = {read_f32(&r), read_f32(&r), read_f32(&r), read_f32(&r)}
		material.emissive = {read_f32(&r), read_f32(&r), read_f32(&r)}
		material.metallic = read_f32(&r)
		material.roughness = read_f32(&r)
		material.alpha_cutoff = read_f32(&r)
		material.alpha_mode = Alpha_Mode(read_u32(&r))
		material.double_sided = read_u32(&r) != 0
		for &texture in material.textures {
			texture = Asset_ID(read_u64(&r))
		}
	}

	r.data = find_section(sections, .Vertices, VERTEX_SIZE) or_return
	model.vertices = make_records(geometry.Vertex, len(r.data) / VERTEX_SIZE) or_return
	for &vertex in model.vertices {
		vertex.position = read_vec3(&r)
		vertex.normal = read_vec3(&r)
		vertex.uv = {read_f32(&r), read_f32(&r)}
		vertex.tangent = read_vec3(&r)
		vertex.bitangent = read_vec3(&r)
	}

	r.data = find_section(sections, .Skin_Vertices, SKIN_VERTEX_SIZE) or_return
	model.skin_vertices = make_records(Skin_Vertex, len(r.data) / SKIN_VERTEX_SIZE) or_return
	for &vertex in model.skin_vertices {
		for &joint in vertex.joints {
			joint = read_u16(&r)
		}
		vertex.weights = {read_f32(&r), read_f32(&r), read_f32(&r), read_f32(&r)}
	}

	r.data, err = find_section(sections, .Indices, 2)
	if err == .None {
		indices := make_records(u16, len(r.data) / 2) or_return
		for &index in indices {
			index = read_u16(&r)
		}
		model.indices = indices
	} else if err == .Wrong_Stride {
		r.data = find_section(sections, .Indices, 4) or_return
		indices := make_records(u32, len(r.data) / 4) or_return
		for &index in indices {
			index = read_u32(&r)
		}
		model.indices = indices
	} else {
		return
	}

	r.data = find_section(sections, .Skins, SKIN_SIZE) or_return
	model.skins = make_records(Skin, len(r.data) / SKIN_SIZE) or_return
	for &skin in model.skins {
		skin.first_joint = read_u32(&r)
		skin.joint_count = read_u32(&r)
		skin.root = read_i32(&r)
	}

	r.data = find_section(sections, .Skin_Joints, SKIN_JOINT_SIZE) or_return
	model.skin_joints = make_records(Skin_Joint, len(r.data) / SKIN_JOINT_SIZE) or_return
	for &joint in model.skin_joints {
		joint.node = read_u32(&r)
		for column in 0 ..< 4 {
			for row in 0 ..< 4 {
				joint.inverse_bind[row, column] = read_f32(&r)
			}
		}
	}

	r.data = find_section(sections, .Animations, ANIMATION_SIZE) or_return
	model.animations = make_records(Animation, len(r.data) / ANIMATION_SIZE) or_return
	for &animation in model.animations {
		animation.name = read_name(&r) or_return
		animation.duration = read_f32(&r)
		animation.first_channel = read_u32(&r)
		animation.channel_count = read_u32(&r)
	}

	r.data = find_section(sections, .Channels, CHANNEL_SIZE) or_return
	model.channels = make_records(Channel, len(r.data) / CHANNEL_SIZE) or_return
	for &channel in model.channels {
		channel.node = read_u32(&r)
		channel.path = Channel_Path(read_u32(&r))
		channel.interpolation = Interpolation(read_u32(&r))
		channel.first_key = read_u32(&r)
		channel.key_count = read_u32(&r)
		channel.first_value = read_u32(&r)
	}

	r.data = find_section(sections, .Key_Times, 4) or_return
	model.key_times = make_records(f32, len(r.data) / 4) or_return
	for &time in model.key_times {
		time = read_f32(&r)
	}

	r.data = find_section(sections, .Key_Values, 4) or_return
	model.key_values = make_records(f32, len(r.data) / 4) or_return
	for &value in model.key_values {
		value = read_f32(&r)
	}

	return model, .None
}

destroy_model :: proc(model: ^Model, allocator := context.allocator) {
	context.allocator = allocator
	for node in model.nodes {
		delete(node.name)
	}
	for mesh in model.meshes {
		delete(mesh.name)
	}
	for material in model.materials {
		delete(material.name)
	}
	for animation in model.animations {
		delete(animation.name)
	}
	switch indices in model.indices {
	case []u16:
		delete(indices)
	case []u32:
		delete(indices)
	}
	delete(model.nodes)
	delete(model.meshes)
	delete(model.submeshes)
	delete(model.materials)
	delete(model.vertices)
	delete(model.skin_vertices)
	delete(model.skins)
	delete(model.skin_joints)
	delete(model.animations)
	delete(model.channels)
	delete(model.key_times)
	delete(model.key_values)
	model^ = {}
}

// Every index and range points inside what it names, enums hold values this
// version defines, and key times are finite and never go backward.
validate_model :: proc(model: Model) -> File_Error {
	inside :: proc(first, count: u32, length: int) -> bool {
		return u64(first) + u64(count) <= u64(length)
	}
	optional :: proc(index: i32, length: int) -> bool {
		return index == NO_INDEX || (index >= 0 && int(index) < length)
	}

	for node, i in model.nodes {
		if !(node.parent == NO_INDEX || (node.parent >= 0 && int(node.parent) < i)) ||
		   !optional(node.mesh, len(model.meshes)) ||
		   !optional(node.skin, len(model.skins)) {
			return .Invalid_Reference
		}
	}
	for mesh in model.meshes {
		if !inside(mesh.first_submesh, mesh.submesh_count, len(model.submeshes)) {
			return .Invalid_Reference
		}
	}

	index_count := 0
	switch indices in model.indices {
	case []u16:
		index_count = len(indices)
		for index in indices {
			if int(index) >= len(model.vertices) {
				return .Invalid_Reference
			}
		}
	case []u32:
		index_count = len(indices)
		for index in indices {
			if u64(index) >= u64(len(model.vertices)) {
				return .Invalid_Reference
			}
		}
	}
	for submesh in model.submeshes {
		if !inside(submesh.first_index, submesh.index_count, index_count) ||
		   !optional(submesh.material, len(model.materials)) {
			return .Invalid_Reference
		}
	}
	for material in model.materials {
		if material.alpha_mode > .Blend {
			return .Invalid_Value
		}
	}

	joint_limit := 0
	for skin in model.skins {
		if !inside(skin.first_joint, skin.joint_count, len(model.skin_joints)) ||
		   !optional(skin.root, len(model.nodes)) {
			return .Invalid_Reference
		}
		joint_limit = max(joint_limit, int(skin.joint_count))
	}
	for joint in model.skin_joints {
		if u64(joint.node) >= u64(len(model.nodes)) {
			return .Invalid_Reference
		}
	}
	if len(model.skin_vertices) != 0 && len(model.skin_vertices) != len(model.vertices) {
		return .Invalid_Reference
	}
	for vertex in model.skin_vertices {
		for joint in vertex.joints {
			if int(joint) >= joint_limit {
				return .Invalid_Reference
			}
		}
	}

	for animation in model.animations {
		if !inside(animation.first_channel, animation.channel_count, len(model.channels)) {
			return .Invalid_Reference
		}
	}
	for channel in model.channels {
		if channel.path > .Scale || channel.interpolation > .Cubic_Spline {
			return .Invalid_Value
		}
		components := u32(4 if channel.path == .Rotation else 3)
		if channel.interpolation == .Cubic_Spline {
			components *= 3
		}
		if u64(channel.node) >= u64(len(model.nodes)) ||
		   !inside(channel.first_key, channel.key_count, len(model.key_times)) ||
		   u64(channel.first_value) + u64(channel.key_count) * u64(components) >
			   u64(len(model.key_values)) {
			return .Invalid_Reference
		}

		previous := math.inf_f32(-1)
		for time in model.key_times[channel.first_key:][:channel.key_count] {
			if !emath.finite(time) || time < previous {
				return .Invalid_Value
			}
			previous = time
		}
	}
	return .None
}
