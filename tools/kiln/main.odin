package kiln

import "base:runtime"
import "core:fmt"
import "core:hash/xxhash"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "ember:assets"
import "vendor:cgltf"

USAGE :: `usage: kiln [PROJECT_ROOT]

Converts every model registered in PROJECT_ROOT/assets.toml into Ember model
and texture files under PROJECT_ROOT/build/assets, with the index the engine
reads. Only models whose source, referenced files, or converter changed are
rebuilt. PROJECT_ROOT defaults to the current directory.`

OUTPUT_DIRECTORY :: "build/assets"

main :: proc() {
	if len(os.args) > 2 || (len(os.args) == 2 && strings.has_prefix(os.args[1], "-")) {
		fmt.eprintln(USAGE)
		os.exit(2)
	}
	root := os.args[1] if len(os.args) == 2 else "."
	output := filepath.join({root, OUTPUT_DIRECTORY}) or_else panic("out of memory")

	registry, registry_err := assets.load(filepath.join({root, "assets.toml"}) or_else "")
	if registry_err.kind != .None {
		report_registry_error(registry_err)
		os.exit(1)
	}

	if err := os.make_directory_all(output); err != nil && err != .Exist {
		fmt.eprintfln("kiln: cannot create %s: %v", output, err)
		os.exit(1)
	}

	manifest_path := filepath.join({output, MANIFEST_FILE}) or_else ""
	previous, manifest_problem := load_manifest(manifest_path)
	if manifest_problem != "" {
		fmt.eprintfln("kiln: %s: %s; rebuilding everything", manifest_path, manifest_problem)
	}

	entries := slice.clone(registry.entries[:])
	slice.sort_by(entries, proc(a, b: assets.Entry) -> bool {
		return a.path < b.path
	})

	built := make(Manifest)
	converted, failed := 0, 0
	for entry in entries {
		defer free_all(context.temp_allocator)

		reason, rebuild := rebuild_reason(previous, entry, root, output)
		if !rebuild {
			built[entry.id] = previous[entry.id]
			continue
		}

		model, problem := build_model(entry, root, output)
		if problem != "" {
			fmt.eprintfln("kiln: %s: %s", entry.path, problem)
			failed += 1
			continue
		}
		fmt.printfln("kiln: %s: converted (%s)", entry.path, reason)
		built[entry.id] = model
		converted += 1
	}

	failed += remove_colliding_textures(&built, entries)

	if !write_index(built, entries, output) {
		fmt.eprintfln("kiln: cannot write %s", assets.INDEX_FILE)
		failed += 1
	}
	if !save_manifest(built, manifest_path) {
		fmt.eprintfln("kiln: cannot write %s", manifest_path)
		failed += 1
	}
	remove_orphans(built, output)

	fmt.printfln(
		"kiln: %d converted, %d up to date, %d failed",
		converted,
		len(built) - converted,
		failed,
	)
	if failed > 0 {
		os.exit(1)
	}
}

report_registry_error :: proc(err: assets.Error) {
	switch {
	case err.kind == .Syntax:
		fmt.eprintfln(
			"kiln: assets.toml:%d:%d: %v",
			err.syntax.line,
			err.syntax.column,
			err.syntax.kind,
		)
	case err.entry > 0:
		fmt.eprintfln("kiln: assets.toml: asset %d: %v", err.entry, err.kind)
	case:
		fmt.eprintfln("kiln: assets.toml: %v", err.kind)
	}
}

build_model :: proc(
	entry: assets.Entry,
	root, output: string,
) -> (
	built: Built_Model,
	problem: string,
) {
	persistent := context.allocator
	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		return {}, "out of memory"
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	full := filepath.join({root, entry.path}) or_else ""
	source, read_err := os.read_entire_file(full, context.allocator)
	if read_err != nil {
		return {}, fmt.tprintf("cannot read: %v", read_err)
	}
	sources: [dynamic]Source
	append(&sources, Source{entry.path, xxhash.XXH3_64_default(source)})

	data: ^cgltf.data
	if data, problem = parse_gltf(source, strings.clone_to_cstring(full)); problem != "" {
		return
	}
	defer cgltf.free(data)

	directory := filepath.dir(entry.path)
	for &buffer in data.buffers {
		uri := string(buffer.uri)
		if uri == "" || strings.has_prefix(uri, "data:") {
			continue
		}
		file, inside := external_file(uri, directory)
		if !inside {
			return {}, fmt.tprintf("buffer points outside the project: %s", uri)
		}
		hash, _ := hash_file(filepath.join({root, file}) or_else "")
		append(&sources, Source{file, hash})
	}

	converted: Converted
	if converted, problem = convert_model(data, entry.id); problem != "" {
		return
	}

	for texture in converted.textures {
		image := &data.images[texture.image]
		bytes: Image_Bytes
		if bytes, problem = read_image(data, image, root, directory); problem != "" {
			return
		}
		if bytes.file != "" && !has_source(sources[:], bytes.file) {
			append(&sources, Source{bytes.file, xxhash.XXH3_64_default(bytes.bytes)})
		}

		encoded: []byte
		encoded, problem = convert_texture(
			bytes.bytes,
			texture.format,
			texture.id,
			runtime.heap_allocator(),
		)
		if problem != "" {
			return {}, fmt.tprintf("image %q: %s", image.name, problem)
		}
		written := write_atomically(output_path(output, texture.id, .Texture), encoded)
		delete(encoded, runtime.heap_allocator())
		if !written {
			return {}, fmt.tprintf("cannot write the texture for image %q", image.name)
		}
	}

	encoded, err := assets.encode_model(converted.model, entry.id)
	if err != .None {
		return {}, fmt.tprintf("cannot encode: %v", err)
	}
	if !write_atomically(output_path(output, entry.id, .Model), encoded) {
		return {}, "cannot write the model file"
	}

	context.allocator = persistent
	built = {
		id        = entry.id,
		converter = CONVERTER_VERSION,
		format    = assets.FILE_VERSION,
		sources   = make([]Source, len(sources)),
		textures  = make([]assets.Asset_ID, len(converted.textures)),
	}
	for source, i in sources {
		built.sources[i] = {strings.clone(source.path), source.hash}
	}
	for texture, i in converted.textures {
		built.textures[i] = texture.id
	}
	return built, ""
}

has_source :: proc(sources: []Source, path: string) -> bool {
	for source in sources {
		if source.path == path {
			return true
		}
	}
	return false
}

remove_colliding_textures :: proc(built: ^Manifest, entries: []assets.Entry) -> (failed: int) {
	owners := make(map[assets.Asset_ID]string, context.temp_allocator)
	for entry in entries {
		owners[entry.id] = entry.path
	}
	for entry in entries {
		model, found := built[entry.id]
		if !found {
			continue
		}
		for id in model.textures {
			if owner, taken := owners[id]; taken {
				fmt.eprintfln(
					"kiln: %s: texture %s has the same ID as %s",
					entry.path,
					assets.format_id(id),
					owner,
				)
				delete_key(built, entry.id)
				failed += 1
				break
			}
			owners[id] = fmt.tprintf("a texture of %s", entry.path)
		}
	}
	return failed
}

write_index :: proc(built: Manifest, entries: []assets.Entry, output: string) -> bool {
	context.allocator = context.temp_allocator

	index: [dynamic]assets.Index_Entry
	for entry in entries {
		model, found := built[entry.id]
		if !found {
			continue
		}
		append(&index, assets.Index_Entry{id = entry.id, kind = .Model, path = entry.path})
		for id in model.textures {
			append(&index, assets.Index_Entry{id = id, kind = .Texture})
		}
	}
	slice.sort_by(index[:], proc(a, b: assets.Index_Entry) -> bool {
		return a.id < b.id
	})

	encoded, err := assets.encode_index(index[:])
	if err != .None {
		return false
	}
	return write_atomically(filepath.join({output, assets.INDEX_FILE}) or_else "", encoded)
}

remove_orphans :: proc(built: Manifest, output: string) {
	textures := make(map[assets.Asset_ID]bool, context.temp_allocator)
	for _, model in built {
		for id in model.textures {
			textures[id] = true
		}
	}

	files, err := os.read_all_directory_by_path(output, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("kiln: cannot list %s: %v", output, err)
		return
	}
	for file in files {
		extension := filepath.ext(file.name)
		id, is_id := assets.parse_id(filepath.stem(file.name))
		keep := true
		if extension == assets.FILE_EXTENSIONS[.Model] {
			keep = is_id && id in built
		} else if extension == assets.FILE_EXTENSIONS[.Texture] {
			keep = is_id && id in textures
		} else if extension == ".tmp" {
			keep = false
		}
		if !keep {
			os.remove(file.fullpath)
		}
	}
}

output_path :: proc(output: string, id: assets.Asset_ID, kind: assets.File_Kind) -> string {
	return filepath.join({output, assets.file_name(id, kind)}, context.temp_allocator) or_else ""
}

write_atomically :: proc(path: string, bytes: []byte) -> bool {
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, bytes) != nil {
		return false
	}
	if os.rename(temporary, path) != nil {
		os.remove(temporary)
		return false
	}
	return true
}
