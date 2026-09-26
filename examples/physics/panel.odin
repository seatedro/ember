package game

import "../common"

import "core:fmt"
import "core:log"
import "core:os"
import "ember:engine"
import "ember:input"
import "ember:ui"

DEFAULT_WINDOW :: ui.Window {
	bounds       = {{24, 24}, {384, 464}},
	minimum_size = {336, 160},
	open         = true,
}

// The physics window and its docking layout, saved to the user's config
// directory once a second when it changes.
Panel :: struct {
	window:      ui.Window,
	scroll:      [2]f32,
	layout_path: string,
	saved:       []u8,
	next_save:   f64,
}

init_panel :: proc(game: ^State) {
	panel := &game.panel
	panel.window = DEFAULT_WINDOW
	panel.window.id = ui.id("physics-window")
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

	panel.layout_path = fmt.aprintf("%s/physics-ui-layout.json", directory)
	if !os.exists(panel.layout_path) {
		return
	}
	data, read_error := os.read_entire_file(panel.layout_path, context.allocator)
	if read_error != nil {
		log.warnf("Read UI layout: %v", read_error)
		return
	}
	defer delete(data)

	windows := [1]^ui.Window{&panel.window}
	if layout_error := ui.decode_layout(&game.overlay.interface, data, windows[:]);
	   layout_error != .None {
		log.warnf("Load UI layout: %v", layout_error)
	}
}

destroy_panel :: proc(game: ^State) {
	delete(game.panel.layout_path)
	delete(game.panel.saved)
	game.panel = {}
}

build_ui :: proc(app: ^engine.Context, game: ^State) -> bool {
	panel := &game.panel
	ctx := &game.overlay.interface
	if input.pressed(app.input, .F5) {
		reset_panel_layout(game)
	}
	if input.pressed(app.input, .F1) {
		panel.window.open = !panel.window.open
	}

	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	windows := [1]^ui.Window{&panel.window}
	if !common.check_ui(ui.begin(ctx, app.input^, size, size, windows[:])) {
		return false
	}

	ok := build_window(game)
	ok = common.check_ui(ui.end(ctx)) && ok
	if app.elapsed_time >= panel.next_save {
		save_panel_layout(game)
		panel.next_save = app.elapsed_time + 1
	}
	return ok
}

@(private = "file")
build_window :: proc(game: ^State) -> bool {
	panel := &game.panel
	ctx := &game.overlay.interface
	buffer: [128]u8
	title := fmt.bprintf(buffer[:], "PHYSICS  FPS %3.0f", game.overlay.fps)
	if panel.window.collapsed {
		title = fmt.bprintf(buffer[:], "FPS %3.0f", game.overlay.fps)
	}
	body, visible, window_error := ui.begin_window(ctx, &panel.window, title)
	if !common.check_ui(window_error) {
		return false
	}
	if !visible {
		return true
	}

	tab_rect := ui.Rect{body.position, {body.size.x, 28}}
	changed, tab_error := ui.tabs(
		ctx,
		ui.id("physics-tabs"),
		tab_rect,
		{"MOTION", "QUERIES", "CONTACTS"},
		(^int)(&game.tab),
	)
	if !common.check_ui(tab_error) {
		common.check_ui(ui.end_window(ctx))
		return false
	}
	if changed {
		panel.scroll = {}
	}
	body.position.y += 36
	body.size.y = max(body.size.y - 36, 0)

	heights := [Tab]f32 {
		.Motion   = 280,
		.Queries  = 360,
		.Contacts = 320,
	}
	controls := [Tab]proc(game: ^State, column: ^ui.Layout) -> bool {
		.Motion   = motion_controls,
		.Queries  = query_controls,
		.Contacts = contact_controls,
	}
	content, scroll_error := ui.begin_scroll(
		ctx,
		ui.id("physics-content"),
		body,
		{max(body.size.x - 12, 0), heights[game.tab]},
		&panel.scroll,
	)
	if !common.check_ui(scroll_error) {
		common.check_ui(ui.end_window(ctx))
		return false
	}

	column, layout_error := ui.layout(content, .Column, spacing = 8)
	ok := common.check_ui(layout_error) && controls[game.tab](game, &column)
	ok = common.check_ui(ui.end_scroll(ctx)) && ok
	return common.check_ui(ui.end_window(ctx)) && ok
}

save_panel_layout :: proc(game: ^State) {
	panel := &game.panel
	ctx := &game.overlay.interface
	if panel.layout_path == "" || ui.layout_busy(ctx) {
		return
	}
	data, err := ui.encode_layout(ctx)
	if err != .None {
		log.warnf("Encode UI layout: %v", err)
		return
	}
	defer delete(data)
	if string(data) == string(panel.saved) {
		return
	}

	temporary := fmt.aprintf("%s.tmp", panel.layout_path)
	defer delete(temporary)
	if file_error := os.write_entire_file(temporary, data); file_error != nil {
		log.warnf("Write UI layout: %v", file_error)
		return
	}
	if file_error := os.rename(temporary, panel.layout_path); file_error != nil {
		log.warnf("Save UI layout: %v", file_error)
		return
	}
	delete(panel.saved)
	panel.saved = make([]u8, len(data))
	copy(panel.saved, data)
}

@(private = "file")
reset_panel_layout :: proc(game: ^State) {
	panel := &game.panel
	windows := [1]^ui.Window{&panel.window}
	if !common.check_ui(ui.reset_layout(&game.overlay.interface, windows[:])) {
		return
	}
	id := panel.window.id
	panel.window = DEFAULT_WINDOW
	panel.window.id = id
	panel.scroll = {}
}
