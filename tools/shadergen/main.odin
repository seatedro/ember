// Compiles each .vert and .frag file under the given directories into GLSL 410
// and MSL, written to a generated/ directory beside the source. Outputs are
// rebuilt when the source, anything it includes, or this program is newer.
//
//	shadergen [-include:DIR]... DIR...
package shadergen

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

Language :: enum {
	GLSL,
	MSL,
}

Stage :: enum {
	Vertex,
	Fragment,
}

@(rodata)
EXTENSIONS := [Language]string {
	.GLSL = ".glsl",
	.MSL  = ".metal",
}

@(rodata)
DEFINES := [Language]string {
	.GLSL = "-DEMBER_GLSL",
	.MSL  = "-DEMBER_MSL",
}

@(rodata)
STAGE_NAMES := [Stage]string {
	.Vertex   = "vert",
	.Fragment = "frag",
}

// Must match shaders.ENTRY_POINTS for MSL.
@(rodata)
MSL_ENTRY_POINTS := [Stage]string {
	.Vertex   = "vertex_main",
	.Fragment = "fragment_main",
}

// The Metal backend keeps vertex buffers 0 and 1 for the vertex and instance
// streams, so uniform block binding N becomes buffer(N + 2).
METAL_UNIFORM_BUFFER_SHIFT :: "2"

GENERATED_DIRECTORY :: "generated"

main :: proc() {
	includes, roots: [dynamic]string
	for arg in os.args[1:] {
		if strings.has_prefix(arg, "-include:") {
			append(&includes, strings.concatenate({"-I", arg[len("-include:"):]}))
		} else {
			append(&roots, arg)
		}
	}

	if len(roots) == 0 {
		fmt.eprintln("usage: shadergen [-include:DIR]... DIR...")
		os.exit(2)
	}

	executable, executable_error := os.get_executable_path(context.allocator)
	if executable_error != nil {
		fmt.eprintfln("shadergen: cannot find own executable: %v", executable_error)
		os.exit(1)
	}

	generator_time, time_error := os.modification_time_by_path(executable)
	if time_error != nil {
		fmt.eprintfln("shadergen: cannot read %s: %v", executable, time_error)
		os.exit(1)
	}

	working_directory, directory_error := os.get_working_directory(context.allocator)
	if directory_error != nil {
		fmt.eprintfln("shadergen: cannot find working directory: %v", directory_error)
		os.exit(1)
	}

	failed := false
	for root in roots {
		walker := os.walker_create(root)
		defer os.walker_destroy(&walker)

		for info in os.walker_walk(&walker) {
			defer free_all(context.temp_allocator)

			if path, err := os.walker_error(&walker); err != nil {
				fmt.eprintfln("shadergen: cannot read %s: %v", path, err)
				failed = true
				continue
			}

			if info.type == .Directory {
				if info.name == GENERATED_DIRECTORY {
					os.walker_skip_dir(&walker)
					failed |= !remove_orphans(info.fullpath)
				}
				continue
			}

			stage: Stage
			switch os.ext(info.name) {
			case ".vert":
				stage = .Vertex
			case ".frag":
				stage = .Fragment
			case:
				continue
			}

			source, relative_error := os.get_relative_path(
				working_directory,
				info.fullpath,
				context.temp_allocator,
			)
			if relative_error != nil {
				source = info.fullpath
			}

			failed |= !generate(source, stage, includes[:], generator_time)
		}
	}

	if failed {
		os.exit(1)
	}
}

generate :: proc(
	source: string,
	stage: Stage,
	includes: []string,
	generator_time: time.Time,
) -> bool {
	directory, file := os.split_path(source)
	output_directory, _ := os.join_path({directory, GENERATED_DIRECTORY}, context.temp_allocator)
	if err := os.make_directory_all(output_directory); err != nil && err != .Exist {
		fmt.eprintfln("shadergen: cannot create %s: %v", output_directory, err)
		return false
	}

	for language in Language {
		name := strings.concatenate({file, EXTENSIONS[language]}, context.temp_allocator)
		output, _ := os.join_path({output_directory, name}, context.temp_allocator)
		depfile := strings.concatenate({output, ".d"}, context.temp_allocator)
		if is_current(output, depfile, generator_time) {
			continue
		}

		spirv := strings.concatenate({output, ".spv"}, context.temp_allocator)
		defer os.remove(spirv)

		glslang := slice.clone_to_dynamic(
			[]string{"glslang", "-V", DEFINES[language], "--depfile", depfile, "-o", spirv},
			context.temp_allocator,
		)
		append(&glslang, ..includes)
		if language == .MSL {
			append(&glslang, "--shift-UBO-binding", METAL_UNIFORM_BUFFER_SHIFT)
		}
		append(&glslang, source)
		if !run(glslang[:]) {
			return false
		}

		cross: [dynamic]string
		cross.allocator = context.temp_allocator
		switch language {
		case .GLSL:
			append(&cross, "spirv-cross", spirv, "--version", "410", "--no-420pack-extension")
		case .MSL:
			if !name_blocks_in_file(spirv) {
				fmt.eprintfln("shadergen: cannot name uniform blocks in %s", source)
				return false
			}

			append(
				&cross,
				"spirv-cross",
				spirv,
				"--msl",
				"--msl-decoration-binding",
				"--msl-combined-sampler-suffix",
				"_sampler",
				"--rename-entry-point",
				"main",
				MSL_ENTRY_POINTS[stage],
				STAGE_NAMES[stage],
			)
			if stage == .Vertex {
				// Metal leaves the point size undefined unless the vertex shader
				// writes it.
				append(&cross, "--msl-default-point-size", "1")
			}
		}
		append(&cross, "--output", output)
		if !run(cross[:]) {
			return false
		}

		fmt.println("generated", output)
	}

	return true
}

// Up to date when the output is newer than this program and everything
// glslang listed in the depfile, which includes the source itself.
is_current :: proc(output, depfile: string, generator_time: time.Time) -> bool {
	output_time, output_error := os.modification_time_by_path(output)
	if output_error != nil || time.diff(output_time, generator_time) > 0 {
		return false
	}

	contents, read_error := os.read_entire_file(depfile, context.temp_allocator)
	if read_error != nil {
		return false
	}

	_, separator, dependencies := strings.partition(string(contents), ": ")
	if separator == "" {
		return false
	}

	for dependency in strings.fields(dependencies, context.temp_allocator) {
		dependency_time, err := os.modification_time_by_path(dependency)
		if err != nil || time.diff(output_time, dependency_time) > 0 {
			return false
		}
	}

	return true
}

name_blocks_in_file :: proc(path: string) -> bool {
	bytes, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil || len(bytes) % size_of(u32) != 0 {
		return false
	}

	named := name_uniform_blocks(slice.reinterpret([]u32, bytes), context.temp_allocator) or_return
	return os.write_entire_file(path, slice.to_bytes(named)) == nil
}

// A source that was renamed or deleted would otherwise leave outputs that still
// build until the next clean checkout.
remove_orphans :: proc(directory: string) -> bool {
	entries, read_error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("shadergen: cannot read %s: %v", directory, read_error)
		return false
	}

	parent, _ := os.split_path(directory)
	for entry in entries {
		source := strings.trim_suffix(entry.name, ".d")
		for extension in EXTENSIONS {
			source = strings.trim_suffix(source, extension)
		}

		source_path, _ := os.join_path({parent, source}, context.temp_allocator)
		if !os.exists(source_path) {
			os.remove(entry.fullpath)
		}
	}

	return true
}

run :: proc(command: []string) -> bool {
	state, stdout, stderr, err := os.process_exec({command = command}, context.temp_allocator)
	if err != nil {
		fmt.eprintfln(
			"shadergen: cannot run %s: %v (shell.nix provides glslang and spirv-cross)",
			command[0],
			err,
		)
		return false
	}

	if !state.success || state.exit_code != 0 {
		os.write(os.stderr, stdout)
		os.write(os.stderr, stderr)
		return false
	}

	return true
}
