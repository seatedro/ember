package shaders

import "../rhi"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Shader :: struct {
	vertex, fragment: rhi.Shader_Handle,
}

// Each language supplies a full pair. Both stages can share one module and use
// different entry points, like a Metal library.
Source :: struct {
	vertex, fragment: rhi.Shader_Source,
}

Sources :: [rhi.Shader_Language]Source

// tools/shadergen compiles each <name>.vert and <name>.frag source into
// generated/<name>.vert<EXTENSION> and generated/<name>.frag<EXTENSION>.
when rhi.SHADER_LANGUAGE == .GLSL {
	EXTENSION :: ".glsl"
	ENTRY_POINTS :: [rhi.Shader_Stage]string {
		.Vertex   = "main",
		.Fragment = "main",
	}
} else when rhi.SHADER_LANGUAGE == .MSL {
	EXTENSION :: ".metal"
	// Must match MSL_ENTRY_POINTS in tools/shadergen.
	ENTRY_POINTS :: [rhi.Shader_Stage]string {
		.Vertex   = "vertex_main",
		.Fragment = "fragment_main",
	}
} else {
	#panic("Generated shaders are not defined for this shader language")
}

Error :: enum {
	None,
	Invalid_Library,
	Missing_Source,
	Read_Failed,
	GPU_Failed,
	Allocation_Failed,
}

Library :: struct {
	device:    ^rhi.Device,
	entries:   [dynamic]Entry,
	allocator: mem.Allocator,
	closing:   bool,
}

@(private)
Entry :: struct {
	name:   string,
	shader: Shader,
}

create :: proc(device: ^rhi.Device, allocator := context.allocator) -> Library {
	return {device = device, allocator = allocator, entries = make([dynamic]Entry, allocator)}
}

// Pairs generated stage code for the compiled language.
generated_sources :: proc(vertex, fragment: string) -> (sources: Sources) {
	sources[rhi.SHADER_LANGUAGE] = {
		vertex = {code = vertex, entry_point = ENTRY_POINTS[.Vertex]},
		fragment = {code = fragment, entry_point = ENTRY_POINTS[.Fragment]},
	}
	return
}

// Loads the generated files for base_path, which is generated/<name> with no
// extension.
load :: proc(library: ^Library, base_path: string) -> (Shader, Error) {
	if library.device == nil || library.closing {
		return {}, .Invalid_Library
	}

	// No file extension, and it doesn't have to exist on disk as is.
	directory: string
	if !filepath.is_abs(base_path) {
		path_error: os.Error
		directory, path_error = os.get_working_directory(library.allocator)
		if path_error != nil {
			log.errorf("Cannot resolve shader path %s: %v", base_path, path_error)
			return {}, .Read_Failed
		}
	}

	defer delete(directory, library.allocator)
	path, allocation_error := filepath.join({directory, base_path}, library.allocator)
	if allocation_error != .None {
		return {}, .Allocation_Failed
	}

	defer delete(path, library.allocator)
	for entry in library.entries {
		if entry.name == path {
			return entry.shader, .None
		}
	}

	vertex, vertex_error := read_source(path, ".vert" + EXTENSION, library.allocator)
	defer delete(vertex, library.allocator)
	if vertex_error != .None {
		return {}, vertex_error
	}

	fragment, fragment_error := read_source(path, ".frag" + EXTENSION, library.allocator)
	defer delete(fragment, library.allocator)
	if fragment_error != .None {
		return {}, fragment_error
	}

	return load_source(library, path, generated_sources(string(vertex), string(fragment)))
}

@(private)
read_source :: proc(base_path, suffix: string, allocator: mem.Allocator) -> ([]u8, Error) {
	path, allocation_error := strings.concatenate({base_path, suffix}, allocator)
	if allocation_error != .None {
		return nil, .Allocation_Failed
	}

	defer delete(path, allocator)
	bytes, err := os.read_entire_file(path, allocator)
	if err != nil {
		delete(bytes, allocator)
		log.errorf("Cannot read shader %s: %v", path, err)
		return nil, .Read_Failed
	}

	return bytes, .None
}

load_source :: proc(library: ^Library, name: string, sources: Sources) -> (Shader, Error) {
	if library.device == nil || library.closing {
		return {}, .Invalid_Library
	}

	for entry in library.entries {
		if entry.name == name {
			return entry.shader, .None
		}
	}

	selected := sources[rhi.SHADER_LANGUAGE]
	if len(selected.vertex.code) == 0 || len(selected.fragment.code) == 0 {
		log.errorf("Shader %s has no complete %v source", name, rhi.SHADER_LANGUAGE)
		return {}, .Missing_Source
	}

	owned_name, allocation_error := strings.clone(name, library.allocator)
	if allocation_error != .None {
		return {}, .Allocation_Failed
	}

	shader: Shader
	keep := false
	defer if !keep {
		release(library.device, &shader)
		delete(owned_name, library.allocator)
	}

	for source, i in ([2]rhi.Shader_Source{selected.vertex, selected.fragment}) {
		stage := rhi.Shader_Stage.Vertex if i == 0 else .Fragment
		handle, err := rhi.create_shader(
			library.device,
			{stage = stage, language = rhi.SHADER_LANGUAGE, source = source, label = name},
		)
		if err != .None {
			return {}, .GPU_Failed
		}

		if i == 0 {
			shader.vertex = handle
		} else {
			shader.fragment = handle
		}
	}

	if _, err := append(&library.entries, Entry{owned_name, shader}); err != .None {
		return {}, .Allocation_Failed
	}

	keep = true
	return shader, .None
}

destroy :: proc(library: ^Library) -> (result: Error) {
	library.closing = true

	for &entry in library.entries {
		if release(library.device, &entry.shader) != .None {
			result = .GPU_Failed
		}
	}

	if result != .None {
		return
	}

	for entry in library.entries {
		delete(entry.name, library.allocator)
	}

	delete(library.entries)
	library^ = {}

	return
}

@(private)
release :: proc(device: ^rhi.Device, shader: ^Shader) -> (result: rhi.Error) {
	for handle in ([2]^rhi.Shader_Handle{&shader.fragment, &shader.vertex}) {
		if handle.generation == 0 {
			continue
		}

		err := rhi.destroy_shader(device, handle^)
		if err == .None {
			handle^ = {}
		} else if result == .None {
			result = err
		}
	}

	return
}
