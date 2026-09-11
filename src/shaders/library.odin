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
	path:   string,
	shader: Shader,
}

create :: proc(device: ^rhi.Device, allocator := context.allocator) -> Library {
	return {device = device, allocator = allocator, entries = make([dynamic]Entry, allocator)}
}

load :: proc(library: ^Library, base_path: string) -> (Shader, Error) {
	if library.device == nil || library.closing {return {}, .Invalid_Library}
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
	if allocation_error != .None {return {}, .Allocation_Failed}
	keep_path := false
	defer if !keep_path {delete(path, library.allocator)}
	for entry in library.entries {
		if entry.path == path {return entry.shader, .None}
	}
	shader: Shader
	keep_shader := false
	defer if !keep_shader {release(library.device, &shader)}
	err: Error
	shader.vertex, err = load_stage(library, path, ".vert", .Vertex)
	if err != .None {return {}, err}
	shader.fragment, err = load_stage(library, path, ".frag", .Fragment)
	if err != .None {return {}, err}
	if _, append_error := append(&library.entries, Entry{path, shader}); append_error != .None {
		return {}, .Allocation_Failed
	}
	keep_path, keep_shader = true, true
	return shader, .None
}

@(private)
load_stage :: proc(
	library: ^Library,
	base_path, extension: string,
	stage: rhi.Shader_Stage,
) -> (
	rhi.Shader_Handle,
	Error,
) {
	path, allocation_error := strings.concatenate({base_path, extension}, library.allocator)
	if allocation_error != .None {return {}, .Allocation_Failed}
	defer delete(path, library.allocator)
	source, read_error := os.read_entire_file(path, library.allocator)
	defer delete(source, library.allocator)
	if read_error != nil {
		log.errorf("Cannot read shader %s: %v", path, read_error)
		return {}, .Read_Failed
	}
	handle, gpu_error := rhi.create_shader(
		library.device,
		{stage = stage, source = string(source), label = path},
	)
	if gpu_error != .None {
		log.errorf("Cannot compile shader %s: %v", path, gpu_error)
		return {}, .GPU_Failed
	}
	return handle, .None
}

destroy :: proc(library: ^Library) -> (result: Error) {
	library.closing = true
	for &entry in library.entries {
		if release(library.device, &entry.shader) != .None {result = .GPU_Failed}
	}
	if result != .None {return}
	for entry in library.entries {delete(entry.path, library.allocator)}
	delete(library.entries)
	library^ = {}
	return
}

@(private)
release :: proc(device: ^rhi.Device, shader: ^Shader) -> (result: rhi.Error) {
	for handle in ([2]^rhi.Shader_Handle{&shader.fragment, &shader.vertex}) {
		if handle.generation == 0 {continue}
		err := rhi.destroy_shader(device, handle^)
		if err == .None {handle^ = {}} else if result == .None {result = err}
	}
	return
}
