package renderer

import "../shaders"

Builtin_Shader :: enum {
	Unlit,
	Lit,
	Grid,
	Presentation,
	Bloom,
}

Tint_Parameters :: struct {
	tint: [4]f32,
}

GLSL_INSTANCE_SOURCE :: "#version 410 core\n" + string(#load("glsl/instance.glsl"))
GLSL_MESH_VERTEX_SOURCE :: GLSL_INSTANCE_SOURCE + string(#load("glsl/mesh.vert"))
GLSL_LIGHTING_SOURCE :: "#version 410 core\n" + string(#load("glsl/lighting.glsl"))

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
			#partial shaders.Sources {
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/unlit.vert")),
					},
					fragment = {entry_point = "main", code = string(#load("glsl/unlit.frag"))},
				},
			},
		)
	case .Lit:
		return shaders.load_source(
			library,
			"ember/lit",
			#partial shaders.Sources {
				.GLSL = {
					vertex = {entry_point = "main", code = GLSL_MESH_VERTEX_SOURCE},
					fragment = {
						entry_point = "main",
						code = GLSL_LIGHTING_SOURCE + string(#load("glsl/lit.frag")),
					},
				},
			},
		)
	case .Grid:
		return shaders.load_source(
			library,
			"ember/grid",
			#partial shaders.Sources {
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/grid.vert")),
					},
					fragment = {entry_point = "main", code = string(#load("glsl/grid.frag"))},
				},
			},
		)
	case .Bloom:
		return shaders.load_source(
			library,
			"ember/bloom",
			#partial shaders.Sources {
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/present.vert")),
					},
					fragment = {entry_point = "main", code = string(#load("glsl/bloom.frag"))},
				},
			},
		)
	case .Presentation:
		return shaders.load_source(
			library,
			"ember/presentation",
			#partial shaders.Sources {
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/present.vert")),
					},
					fragment = {entry_point = "main", code = string(#load("glsl/present.frag"))},
				},
			},
		)
	}

	return {}, .GPU_Failed
}
