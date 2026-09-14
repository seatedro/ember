package game

import "core:fmt"
import "core:log"
import "core:os"
import "ember:ui"

ui_windows :: proc(game: ^State) -> [4]^ui.Window {
	return {&game.render_window, &game.camera_window, &game.bloom_window, &game.lighting_window}
}

init_ui_layout :: proc(game: ^State) {
	windows := ui_windows(game)
	for window, i in windows {
		game.default_windows[i] = window^
	}
	config, err := os.user_config_dir(context.allocator)
	if err != nil {
		log.warnf("Locate UI layout directory: %v", err)
		return
	}
	defer delete(config)
	directory := fmt.aprintf("%s/ember", config)
	defer delete(directory)
	if err = os.mkdir_all(directory); err != nil && !os.is_dir(directory) {
		log.warnf("Create UI layout directory: %v", err)
		return
	}
	game.ui_layout_path = fmt.aprintf("%s/ui-layout.json", directory)
	if !os.exists(game.ui_layout_path) {
		return
	}
	data, read_error := os.read_entire_file(game.ui_layout_path, context.allocator)
	if read_error != nil {
		log.warnf("Read UI layout: %v", read_error)
		return
	}
	defer delete(data)
	if layout_error := ui.decode_layout(&game.overlay.interface, data, windows[:]);
	   layout_error != .None {
		log.warnf("Load UI layout: %v", layout_error)
	}
}

save_ui_layout :: proc(game: ^State) {
	ctx := &game.overlay.interface
	if game.ui_layout_path == "" || ui.layout_busy(ctx) {
		return
	}
	data, err := ui.encode_layout(ctx)
	if err != .None {
		log.warnf("Encode UI layout: %v", err)
		return
	}
	defer delete(data)
	if string(data) == string(game.saved_ui_layout) {
		return
	}
	temporary := fmt.aprintf("%s.tmp", game.ui_layout_path)
	defer delete(temporary)
	if file_error := os.write_entire_file(temporary, data); file_error != nil {
		log.warnf("Write UI layout: %v", file_error)
		return
	}
	if file_error := os.rename(temporary, game.ui_layout_path); file_error != nil {
		log.warnf("Save UI layout: %v", file_error)
		return
	}
	delete(game.saved_ui_layout)
	game.saved_ui_layout = make([]u8, len(data))
	copy(game.saved_ui_layout, data)
}

reset_ui_layout :: proc(game: ^State) {
	windows := ui_windows(game)
	if !check_ui(ui.reset_layout(&game.overlay.interface, windows[:])) {
		return
	}
	for window, i in windows {
		window^ = game.default_windows[i]
	}
	game.reset_ui_layout = false
	game.ui_scroll = {}
}
