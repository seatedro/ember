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

Error :: enum {
	None,
	Invalid_Library,
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

	vertex_path, vp_error := strings.concatenate({path, ".vert"}, library.allocator)
	if vp_error != .None {
		return {}, .Allocation_Failed
	}

	defer delete(vertex_path, library.allocator)
	fragment_path, fp_error := strings.concatenate({path, ".frag"}, library.allocator)
	if fp_error != .None {
		return {}, .Allocation_Failed
	}

	defer delete(fragment_path, library.allocator)
	vertex, vertex_error := os.read_entire_file(vertex_path, library.allocator)
	defer delete(vertex, library.allocator)
	fragment, fragment_error := os.read_entire_file(fragment_path, library.allocator)
	defer delete(fragment, library.allocator)
	if vertex_error != nil {
		log.errorf("Cannot read shader %s: %v", vertex_path, vertex_error)
		return {}, .Read_Failed
	}

	if fragment_error != nil {
		log.errorf("Cannot read shader %s: %v", fragment_path, fragment_error)
		return {}, .Read_Failed
	}

	return load_source(library, path, string(vertex), string(fragment))
}

load_source :: proc(library: ^Library, name, vertex, fragment: string) -> (Shader, Error) {
	if library.device == nil || library.closing {
		return {}, .Invalid_Library
	}

	for entry in library.entries {
		if entry.name == name {
			return entry.shader, .None
		}
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

	for source, i in ([2]string{vertex, fragment}) {
		stage := rhi.Shader_Stage.Vertex if i == 0 else .Fragment
		handle, err := rhi.create_shader(
			library.device,
			{stage = stage, source = source, label = name},
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
