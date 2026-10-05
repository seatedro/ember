package kiln

import "core:encoding/base64"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"
import "ember:assets"
import "vendor:cgltf"

@(private = "file")
MODEL_ID :: assets.Asset_ID(0x6f3a9c2e81d4b705)

@(private = "file")
Fixture :: struct {
	primitive: string,
	root:      string,
	tangents:  bool,
}

@(private = "file")
fixture_json :: proc(fixture: Fixture) -> string {
	context.allocator = context.temp_allocator

	buffer: [dynamic]byte
	views, accessors, attributes: strings.Builder
	add :: proc(
		buffer: ^[dynamic]byte,
		views, accessors: ^strings.Builder,
		bytes: []byte,
		component, type: string,
	) -> int {
		index := len(views.buf) == 0 ? 0 : strings.count(strings.to_string(views^), "{")
		fmt.sbprintf(
			views,
			"%s{{\"buffer\": 0, \"byteOffset\": %d, \"byteLength\": %d}}",
			index == 0 ? "" : ", ",
			len(buffer),
			len(bytes),
		)
		fmt.sbprintf(
			accessors,
			"%s{{\"bufferView\": %d, \"componentType\": %s, \"count\": 3, \"type\": \"%s\"}}",
			index == 0 ? "" : ", ",
			index,
			component,
			type,
		)
		append(buffer, ..bytes)
		return index
	}

	positions := [9]f32{0, 0, 0, 1, 0, 0, 0, 1, 0}
	normals := [9]f32{0, 0, 1, 0, 0, 1, 0, 0, 1}
	uvs := [6]f32{0, 0, 1, 0, 0, 1}
	tangents := [12]f32{1, 0, 0, 1, 1, 0, 0, -1, 1, 0, 0, 1}
	joints := [2][12]u16 {
		{0, 1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0},
		{4, 5, 6, 7, 0, 0, 0, 0, 0, 0, 0, 0},
	}
	weights := [2][12]f32 {
		{0.15, 0.05, 0.02, 0.03, 1, 0, 0, 0, 1, 0, 0, 0},
		{0.4, 0.25, 0.06, 0.04, 0, 0, 0, 0, 0, 0, 0, 0},
	}
	times := [3]f32{0, 1, 2}

	FLOAT :: "5126"
	SHORT :: "5123"
	add(&buffer, &views, &accessors, mem.slice_to_bytes(times[:]), FLOAT, "SCALAR")
	attribute :: proc(b: ^strings.Builder, name: string, accessor: int) {
		fmt.sbprintf(b, ", \"%s\": %d", name, accessor)
	}
	attribute(
		&attributes,
		"POSITION",
		add(&buffer, &views, &accessors, mem.slice_to_bytes(positions[:]), FLOAT, "VEC3"),
	)
	attribute(
		&attributes,
		"NORMAL",
		add(&buffer, &views, &accessors, mem.slice_to_bytes(normals[:]), FLOAT, "VEC3"),
	)
	attribute(
		&attributes,
		"TEXCOORD_0",
		add(&buffer, &views, &accessors, mem.slice_to_bytes(uvs[:]), FLOAT, "VEC2"),
	)
	if fixture.tangents {
		attribute(
			&attributes,
			"TANGENT",
			add(&buffer, &views, &accessors, mem.slice_to_bytes(tangents[:]), FLOAT, "VEC4"),
		)
	}
	for set in 0 ..< 2 {
		attribute(
			&attributes,
			fmt.tprintf("JOINTS_%d", set),
			add(&buffer, &views, &accessors, mem.slice_to_bytes(joints[set][:]), SHORT, "VEC4"),
		)
		attribute(
			&attributes,
			fmt.tprintf("WEIGHTS_%d", set),
			add(&buffer, &views, &accessors, mem.slice_to_bytes(weights[set][:]), FLOAT, "VEC4"),
		)
	}

	encoded, _ := base64.encode(buffer[:])
	return fmt.tprintf(
		`{{
	"asset": {{"version": "2.0"}},
	"buffers": [{{"byteLength": %d, "uri": "data:application/octet-stream;base64,%s"}}],
	"bufferViews": [%s],
	"accessors": [%s],
	"meshes": [{{"primitives": [{{"attributes": {{%s}}%s}}]}}],
	"skins": [{{"joints": [0, 1, 2, 3, 4, 5, 6, 7]}}],
	"nodes": [
		{{"name": "child", "mesh": 0, "skin": 0}},
		{{"name": "root", "children": [0, 2, 3, 4, 5, 6, 7]}},
		{{}}, {{}}, {{}}, {{}}, {{}}, {{}}
	]%s
}}`,
		len(buffer),
		encoded,
		strings.to_string(views),
		strings.to_string(accessors),
		strings.to_string(attributes)[2:],
		fixture.primitive,
		fixture.root,
	)
}

@(private = "file")
convert_fixture :: proc(fixture: Fixture) -> (converted: Converted, problem: string) {
	json := fixture_json(fixture)
	data: ^cgltf.data
	if data, problem = parse_gltf(transmute([]byte)json, "fixture.gltf"); problem != "" {
		return
	}
	defer cgltf.free(data)
	context.allocator = context.temp_allocator
	return convert_model(data, MODEL_ID)
}

@(test)
test_influences_vertices_and_nodes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	converted, problem := convert_fixture({tangents = true})
	testing.expect_value(t, problem, "")
	model := converted.model

	influence := model.skin_vertices[0]
	testing.expect_value(t, influence.joints, [4]u16{4, 5, 0, 6})
	want := [4]f32{0.4, 0.25, 0.15, 0.06} / 0.86
	for weight, k in influence.weights {
		testing.expectf(
			t,
			abs(weight - want[k]) < 1e-6,
			"weight %d is %v, want %v",
			k,
			weight,
			want[k],
		)
	}
	testing.expect_value(t, model.skin_vertices[1].weights, [4]f32{1, 0, 0, 0})

	testing.expect_value(t, model.vertices[0].bitangent, [3]f32{0, 1, 0})
	testing.expect_value(t, model.vertices[1].bitangent, [3]f32{0, -1, 0})

	testing.expect_value(t, model.nodes[0].name, "root")
	testing.expect_value(t, model.nodes[1].name, "child")
	testing.expect_value(t, model.nodes[1].parent, 0)
	testing.expect_value(t, model.skin_joints[0].node, 1)
}

@(test)
test_refuses_unsupported_input :: proc(t: ^testing.T) {
	TEXTURED :: `, "materials": [{{"pbrMetallicRoughness": {{"baseColorTexture": {{"index": 0, %s}}}}}}],
	"textures": [{{"source": 0}}], "images": [{{"uri": "a.png"}}]`
	cases := []struct {
		fixture: Fixture,
		want:    string,
	} {
		{{tangents = false}, "has no TANGENT"},
		{{primitive = `, "mode": 1`, tangents = true}, "not triangles"},
		{{primitive = `, "targets": [{"POSITION": 1}]`, tangents = true}, "morph targets"},
		{
			{
				primitive = `, "extensions": {"KHR_draco_mesh_compression": {"bufferView": 0, "attributes": {"POSITION": 0}}}`,
				tangents = true,
			},
			"Draco",
		},
		{
			{
				primitive = `, "material": 0`,
				root = fmt.tprintf(
					TEXTURED,
					`"extensions": {"KHR_texture_transform": {"scale": [2, 2]}}`,
				),
				tangents = true,
			},
			"KHR_texture_transform",
		},
		{
			{
				primitive = `, "material": 0`,
				root = fmt.tprintf(TEXTURED, `"texCoord": 1`),
				tangents = true,
			},
			"TEXCOORD_1",
		},
		{
			{
				root = `, "extensionsUsed": ["EXT_future"], "extensionsRequired": ["EXT_future"]`,
				tangents = true,
			},
			"EXT_future",
		},
	}
	for c in cases {
		_, problem := convert_fixture(c.fixture)
		testing.expectf(t, strings.contains(problem, c.want), "got %q, want %q", problem, c.want)
	}
	free_all(context.temp_allocator)
}
