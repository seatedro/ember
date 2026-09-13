package renderer

import "../shaders"

Builtin_Shader :: enum {
	Unlit,
	Lit,
	Grid,
	Presentation,
}

Tint_Parameters :: struct {
	tint: [4]f32,
}

MESH_VERTEX_SOURCE :: string(#load("glsl/mesh.vert"))
LIGHTING_SOURCE :: "#version 410 core\n" + string(#load("glsl/lighting.glsl"))

load_builtin_shader :: proc(
	library: ^shaders.Library,
	kind: Builtin_Shader,
) -> (
	shaders.Shader,
	shaders.Error,
) {
	switch kind {
	case .Unlit:
		return shaders.load_source(
			library,
			"ember/unlit",
			string(#load("glsl/unlit.vert")),
			string(#load("glsl/unlit.frag")),
		)
	case .Lit:
		return shaders.load_source(
			library,
			"ember/lit",
			MESH_VERTEX_SOURCE,
			LIGHTING_SOURCE + string(#load("glsl/lit.frag")),
		)
	case .Grid:
		return shaders.load_source(
			library,
			"ember/grid",
			string(#load("glsl/grid.vert")),
			string(#load("glsl/grid.frag")),
		)
	case .Presentation:
		return shaders.load_source(
			library,
			"ember/presentation",
			string(#load("glsl/present.vert")),
			string(#load("glsl/present.frag")),
		)
	}

	return {}, .GPU_Failed
}
