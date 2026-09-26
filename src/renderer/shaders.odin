package renderer

import "../shaders"

Builtin_Shader :: enum {
	Unlit,
	Lit,
	Lit_Shadowed,
	Shadow_Depth,
	Grid,
	Presentation,
	Bloom,
	Downsample,
	Environment_Filter,
	Environment_BRDF,
	Sky,
}

Tint_Parameters :: struct {
	tint: [4]f32,
}

Lit_Parameters :: struct {
	tint:           [4]f32,
	emission:       f32,
	use_normal_map: b32,
	metallic:       f32,
	roughness:      f32,
}

#assert(size_of(Lit_Parameters) == 32)

@(private)
GENERATED :: "shaders/generated/"

// Custom mesh shaders pair their fragment stage with this, as the sphere
// example does.
MESH_VERTEX_SOURCE :: #load(GENERATED + "mesh.vert" + shaders.EXTENSION, string)

@(private)
UNLIT_VERTEX_SOURCE :: #load(GENERATED + "unlit.vert" + shaders.EXTENSION, string)
@(private)
SCREEN_VERTEX_SOURCE :: #load(GENERATED + "screen.vert" + shaders.EXTENSION, string)

load_builtin_shader :: proc(
	library: ^shaders.Library,
	kind: Builtin_Shader,
) -> (
	shaders.Shader,
	shaders.Error,
) {
	name, vertex, fragment: string
	switch kind {
	case .Unlit:
		name, vertex = "ember/unlit", UNLIT_VERTEX_SOURCE
		fragment = #load(GENERATED + "unlit.frag" + shaders.EXTENSION, string)
	case .Lit:
		name, vertex = "ember/lit", MESH_VERTEX_SOURCE
		fragment = #load(GENERATED + "lit.frag" + shaders.EXTENSION, string)
	case .Lit_Shadowed:
		name, vertex = "ember/lit-shadowed", MESH_VERTEX_SOURCE
		fragment = #load(GENERATED + "lit_shadowed.frag" + shaders.EXTENSION, string)
	case .Shadow_Depth:
		name, vertex = "ember/shadow-depth", UNLIT_VERTEX_SOURCE
		fragment = #load(GENERATED + "shadow_depth.frag" + shaders.EXTENSION, string)
	case .Grid:
		name = "ember/grid"
		vertex = #load(GENERATED + "grid.vert" + shaders.EXTENSION, string)
		fragment = #load(GENERATED + "grid.frag" + shaders.EXTENSION, string)
	case .Presentation:
		name, vertex = "ember/presentation", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "present.frag" + shaders.EXTENSION, string)
	case .Bloom:
		name, vertex = "ember/bloom", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "bloom.frag" + shaders.EXTENSION, string)
	case .Downsample:
		name, vertex = "ember/downsample", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "downsample.frag" + shaders.EXTENSION, string)
	case .Environment_Filter:
		name, vertex = "ember/environment_filter", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "environment_filter.frag" + shaders.EXTENSION, string)
	case .Environment_BRDF:
		name, vertex = "ember/environment_brdf", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "environment_brdf.frag" + shaders.EXTENSION, string)
	case .Sky:
		name, vertex = "ember/sky", SCREEN_VERTEX_SOURCE
		fragment = #load(GENERATED + "sky.frag" + shaders.EXTENSION, string)
	}

	return shaders.load_source(library, name, shaders.generated_sources(vertex, fragment))
}
