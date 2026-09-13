package renderer

import "../shaders"

Builtin_Shader :: enum {
	Unlit,
	Lit,
	Grid,
	Presentation,
	Bloom,
	Downsample,
}

Tint_Parameters :: struct {
	tint: [4]f32,
}

MSL_COMMON_SOURCE :: #load("msl/common.metal", string)

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
				.MSL = {
					vertex = {entry_point = "unlit_vertex", code = MSL_COMMON_SOURCE},
					fragment = {entry_point = "unlit_fragment", code = MSL_COMMON_SOURCE},
				},
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
				.MSL = {
					vertex = {
						entry_point = "mesh_vertex",
						code = MSL_COMMON_SOURCE + #load("msl/lit.metal", string),
					},
					fragment = {
						entry_point = "lit_fragment",
						code = MSL_COMMON_SOURCE + #load("msl/lit.metal", string),
					},
				},
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
				.MSL = {
					vertex = {entry_point = "grid_vertex", code = MSL_COMMON_SOURCE},
					fragment = {entry_point = "grid_fragment", code = MSL_COMMON_SOURCE},
				},
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
				.MSL = {
					vertex = {
						entry_point = "screen_vertex",
						code = MSL_COMMON_SOURCE + #load("msl/bloom.metal", string),
					},
					fragment = {
						entry_point = "bloom_fragment",
						code = MSL_COMMON_SOURCE + #load("msl/bloom.metal", string),
					},
				},
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/present.vert")),
					},
					fragment = {entry_point = "main", code = string(#load("glsl/bloom.frag"))},
				},
			},
		)
	case .Downsample:
		return shaders.load_source(
			library,
			"ember/downsample",
			#partial shaders.Sources {
				.MSL = {
					vertex = {
						entry_point = "screen_vertex",
						code = MSL_COMMON_SOURCE + #load("msl/downsample.metal", string),
					},
					fragment = {
						entry_point = "downsample_fragment",
						code = MSL_COMMON_SOURCE + #load("msl/downsample.metal", string),
					},
				},
				.GLSL = {
					vertex = {
						entry_point = "main",
						code = GLSL_INSTANCE_SOURCE + string(#load("glsl/present.vert")),
					},
					fragment = {
						entry_point = "main",
						code = string(#load("glsl/downsample.frag")),
					},
				},
			},
		)
	case .Presentation:
		return shaders.load_source(
			library,
			"ember/presentation",
			#partial shaders.Sources {
				.MSL = {
					vertex = {
						entry_point = "screen_vertex",
						code = MSL_COMMON_SOURCE + #load("msl/present.metal", string),
					},
					fragment = {
						entry_point = "present_fragment",
						code = MSL_COMMON_SOURCE + #load("msl/present.metal", string),
					},
				},
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
