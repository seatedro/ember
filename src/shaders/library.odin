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

// Each language supplies a complete pair; stages may share the same module
// source and select different entry points (as with a Metal library).
Source :: struct {
	vertex, fragment: rhi.Shader_Source,
}

Sources :: [rhi.Shader_Language]Source

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

// Loads .vert/.frag for GLSL, or one .metal module with vertex_main and
// fragment_main entry points for MSL. The base path has no extension.
load :: proc(library: ^Library, base_path: string) -> (Shader, Error) {
	if library.device == nil || library.closing {
		return {}, .Invalid_Library
	}

	// The base has no file extension and need not exist as a filesystem entry.
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

	when rhi.SHADER_LANGUAGE == .GLSL {
		vertex, vertex_error := read_source(path, ".vert", library.allocator)
		defer delete(vertex, library.allocator)
		if vertex_error != .None {
			return {}, vertex_error
		}

		fragment, fragment_error := read_source(path, ".frag", library.allocator)
		defer delete(fragment, library.allocator)
		if fragment_error != .None {
			return {}, fragment_error
		}

		return load_source(
			library,
			path,
			#partial Sources {
				.GLSL = {
					vertex = {entry_point = "main", code = string(vertex)},
					fragment = {entry_point = "main", code = string(fragment)},
				},
			},
		)
	} else when rhi.SHADER_LANGUAGE == .MSL {
		module, err := read_source(path, ".metal", library.allocator)
		defer delete(module, library.allocator)
		if err != .None {
			return {}, err
		}

		return load_source(
			library,
			path,
			#partial Sources {
				.MSL = {
					vertex = {code = string(module), entry_point = "vertex_main"},
					fragment = {code = string(module), entry_point = "fragment_main"},
				},
			},
		)
	} else {
		#panic("File loading is not defined for this shader language")
	}
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
