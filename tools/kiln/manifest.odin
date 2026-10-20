package kiln

import "core:fmt"
import "core:hash/xxhash"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "ember:assets"
import "ember:core/toml"

MANIFEST_FILE :: "manifest.toml"
MANIFEST_VERSION :: 1

CONVERTER_VERSION :: 2

Source :: struct {
	path: string,
	hash: u64,
}

Built_Model :: struct {
	id:        assets.Asset_ID,
	converter: int,
	format:    int,
	sources:   []Source,
	textures:  []assets.Asset_ID,
}

Manifest :: map[assets.Asset_ID]Built_Model

load_manifest :: proc(path: string) -> (manifest: Manifest, problem: string) {
	manifest = make(Manifest)
	if !os.exists(path) {
		return manifest, ""
	}

	text, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return manifest, fmt.tprintf("cannot read: %v", read_err)
	}
	document, syntax := toml.parse(string(text))
	if syntax.kind != .None {
		return manifest, fmt.tprintf("line %d: %v", syntax.line, syntax.kind)
	}
	defer toml.destroy(document)

	if version, _ := document.root["version"].(toml.Integer); version != MANIFEST_VERSION {
		return manifest, "unsupported version"
	}
	models, _ := document.root["model"].(toml.Array)
	for value in models {
		built, ok := parse_built_model(value)
		if !ok {
			clear(&manifest)
			return manifest, "malformed model entry"
		}
		manifest[built.id] = built
	}
	return manifest, ""
}

@(private = "file")
parse_built_model :: proc(value: toml.Value) -> (built: Built_Model, ok: bool) {
	table := value.(toml.Table) or_return
	built.id = assets.parse_id(table["id"].(toml.String) or_return) or_return
	built.converter = int(table["converter"].(toml.Integer) or_return)
	built.format = int(table["format"].(toml.Integer) or_return)

	sources := table["source"].(toml.Array) or_return
	built.sources = make([]Source, len(sources))
	for item, i in sources {
		source := item.(toml.Table) or_return
		path := source["path"].(toml.String) or_return
		hash := strconv.parse_u64_of_base(source["hash"].(toml.String) or_return, 16) or_return
		built.sources[i] = {strings.clone(path), hash}
	}

	textures := table["textures"].(toml.Array) or_return
	built.textures = make([]assets.Asset_ID, len(textures))
	for item, i in textures {
		built.textures[i] = assets.parse_id(item.(toml.String) or_return) or_return
	}
	return built, len(built.sources) > 0
}

save_manifest :: proc(manifest: Manifest, path: string) -> bool {
	context.allocator = context.temp_allocator

	built_models, _ := slice.map_values(manifest)
	slice.sort_by(built_models, proc(a, b: Built_Model) -> bool {
		return a.id < b.id
	})

	models := make(toml.Array, 0, len(built_models))
	for built in built_models {
		sources := make(toml.Array, 0, len(built.sources))
		for source in built.sources {
			table := make(toml.Table)
			table["path"] = source.path
			table["hash"] = fmt.aprintf("%016x", source.hash)
			append(&sources, table)
		}
		textures := make(toml.Array, 0, len(built.textures))
		for id in built.textures {
			append(&textures, assets.format_id(id))
		}

		table := make(toml.Table)
		table["id"] = assets.format_id(built.id)
		table["converter"] = toml.Integer(built.converter)
		table["format"] = toml.Integer(built.format)
		table["source"] = sources
		table["textures"] = textures
		append(&models, table)
	}

	root := make(toml.Table)
	root["version"] = toml.Integer(MANIFEST_VERSION)
	if len(models) > 0 {
		root["model"] = models
	}

	b := strings.builder_make()
	if toml.write(&b, root) != .None {
		return false
	}
	return write_atomically(path, transmute([]byte)strings.to_string(b))
}

rebuild_reason :: proc(
	manifest: Manifest,
	entry: assets.Entry,
	root, output: string,
) -> (
	reason: string,
	rebuild: bool,
) {
	built, found := manifest[entry.id]
	switch {
	case !found:
		return "new", true
	case built.sources[0].path != entry.path:
		return fmt.tprintf("moved from %s", built.sources[0].path), true
	case built.converter != CONVERTER_VERSION || built.format != assets.FILE_VERSION:
		return "converter changed", true
	}

	for source in built.sources {
		hash, ok := hash_file(
			filepath.join({root, source.path}, context.temp_allocator) or_else "",
		)
		if !ok || hash != source.hash {
			return fmt.tprintf("%s changed", source.path), true
		}
	}

	if !os.exists(output_path(output, entry.id, .Model)) {
		return "output missing", true
	}
	for id in built.textures {
		if !os.exists(output_path(output, id, .Texture)) {
			return "output missing", true
		}
	}
	return "", false
}

hash_file :: proc(path: string) -> (u64, bool) {
	bytes, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return 0, false
	}
	defer delete(bytes)
	return xxhash.XXH3_64_default(bytes), true
}
