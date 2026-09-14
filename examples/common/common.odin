package common

import "core:fmt"
import "core:log"
import "core:time"
import "ember:draw2d"
import "ember:engine"
import "ember:input"
import render "ember:renderer"
import "ember:rhi"
import "ember:shaders"
import "ember:ui"

RESOLUTION :: [2]i32{320, 180}
BACKGROUND :: [4]f32{0.012, 0.016, 0.025, 1}
SAMPLE_SCALE :: 4

Pixel_Target :: struct {
	world, pixels: render.Render_Target,
	filter:        render.Downsample,
}

create_pixel_target :: proc(
	renderer: ^render.Renderer,
	library: ^shaders.Library,
	resolution: [2]i32 = RESOLUTION,
	sample_scale: i32 = SAMPLE_SCALE,
) -> (
	target: Pixel_Target,
	err: render.Error,
) {
	if resolution.x <= 0 ||
	   resolution.y <= 0 ||
	   sample_scale <= 0 ||
	   i64(resolution.x) * i64(sample_scale) > 0x7fff_ffff ||
	   i64(resolution.y) * i64(sample_scale) > 0x7fff_ffff {
		return {}, .Invalid_Size
	}

	defer {
		if err != .None {
			destroy_pixel_target(renderer, &target)
		}
	}

	target.world, err = render.create_render_target(
		renderer,
		{
			width = resolution.x * sample_scale,
			height = resolution.y * sample_scale,
			color_format = .RGBA16F,
			color_filter = .Nearest,
		},
	)
	if err != .None {
		return
	}

	target.pixels, err = render.create_render_target(
		renderer,
		{
			width = resolution.x,
			height = resolution.y,
			color_format = .RGBA16F,
			color_filter = .Nearest,
		},
	)
	if err != .None {
		return
	}

	target.filter, err = render.create_downsample(renderer, library)
	return
}

resolve_pixels :: proc(renderer: ^render.Renderer, target: ^Pixel_Target) -> render.Error {
	return render.downsample(renderer, &target.filter, target.world, &target.pixels)
}

destroy_pixel_target :: proc(renderer: ^render.Renderer, target: ^Pixel_Target) {
	check(render.destroy_downsample(renderer, &target.filter), "destroy downsample")
	check(render.destroy_render_target(renderer, &target.pixels), "destroy pixels")
	check(render.destroy_render_target(renderer, &target.world), "destroy world target")
}

Overlay :: struct {
	renderer:  draw2d.Renderer,
	interface: ui.Context,
	font:      draw2d.Font,
	fps:       f64,
	tick:      time.Tick,
	frame:     u64,
}

init_overlay :: proc(overlay: ^Overlay, app: ^engine.Context) -> bool {
	err: render.Error
	overlay.renderer, err = draw2d.create(app.device)
	if !check(err, "create overlay") {
		return false
	}

	overlay.interface = ui.create()
	overlay.interface.clipboard = app.clipboard
	font_error: draw2d.Font_Error
	overlay.font, font_error = draw2d.load_font(
		app.device,
		"assets/fonts/press-start-2p.json",
		"assets/fonts/press-start-2p.png",
	)
	if font_error != .None {
		log.errorf("Load example font: %v", font_error)
		return false
	}

	overlay.interface.style = {
		font         = &overlay.font,
		font_size    = 12,
		padding      = {8, 4},
		border_width = 2,
		thumb_width  = 12,
		text         = {0.88, 0.85, 0.77, 1},
		background   = {0.14, 0.13, 0.17, 1},
		hover        = {0.24, 0.22, 0.28, 1},
		active       = {0.32, 0.28, 0.36, 1},
		border       = {0.68, 0.64, 0.55, 1},
		focus        = {0.94, 0.81, 0.49, 1},
		disabled     = {0.5, 0.47, 0.48, 1},
		thumb        = {0.88, 0.85, 0.77, 1},
	}
	overlay.tick, overlay.frame = time.tick_now(), app.frame_count
	return true
}

draw_overlay :: proc(overlay: ^Overlay, app: ^engine.Context) -> rhi.Error {
	now := time.tick_now()
	seconds := time.duration_seconds(time.tick_diff(overlay.tick, now))
	if seconds >= 0.5 {
		overlay.fps = f64(app.frame_count - overlay.frame) / seconds
		overlay.tick, overlay.frame = now, app.frame_count
	}

	if err := rhi.begin_pass(app.device, {color_load = .Load, depth_load = .Load}); err != .None {
		return err
	}

	draw_error := draw2d.draw(&overlay.renderer, &overlay.interface.draws)
	end_error := rhi.end_pass(app.device)
	return draw_error if draw_error != .None else end_error
}

destroy_overlay :: proc(overlay: ^Overlay, device: ^rhi.Device) {
	ui.destroy(&overlay.interface)
	check(draw2d.destroy_font(device, &overlay.font), "destroy font")
	check(draw2d.destroy(&overlay.renderer), "destroy overlay")
}

info_window :: proc(name: string, height: f32) -> ui.Window {
	return {
		id = ui.id(name),
		bounds = {{24, 24}, {336, height}},
		minimum_size = {264, 100},
		open = true,
	}
}

info_panel :: proc(
	overlay: ^Overlay,
	app: ^engine.Context,
	window: ^ui.Window,
	name, text: string,
) -> bool {
	if input.pressed(app.input, .F1) {
		window.open = !window.open
	}

	ctx := &overlay.interface
	size := [2]f32{f32(app.window_size.x), f32(app.window_size.y)}
	if !check_ui(ui.begin(ctx, app.input^, size, size, {window})) {
		return false
	}

	buffer: [128]u8
	title := fmt.bprintf(buffer[:], "%s  FPS %3.0f", name, overlay.fps)
	if window.collapsed {
		title = fmt.bprintf(buffer[:], "FPS %3.0f", overlay.fps)
	}

	body, visible, err := ui.begin_window(ctx, window, title)
	ok := check_ui(err)
	if visible && ok {
		ok = check_ui(ui.label(ctx, body, text))
		ok = check_ui(ui.end_window(ctx)) && ok
	}

	return check_ui(ui.end(ctx)) && ok
}

Surface :: struct {
	renderer:     render.Renderer,
	shaders:      shaders.Library,
	target:       Pixel_Target,
	presentation: render.Presentation,
}

init_surface :: proc(surface: ^Surface, device: ^rhi.Device) -> bool {
	err: render.Error
	surface.renderer, err = render.create(device)
	if !check(err, "create example renderer") {
		return false
	}

	surface.shaders = shaders.create(device)
	surface.target, err = create_pixel_target(&surface.renderer, &surface.shaders)
	if !check(err, "create pixel target") {
		return false
	}

	surface.presentation, err = render.create_presentation(&surface.renderer, &surface.shaders)
	return check(err, "create example presentation")
}

present_surface :: proc(surface: ^Surface, app: ^engine.Context) -> rhi.Error {
	if err := resolve_pixels(&surface.renderer, &surface.target); err != .None {
		return err
	}

	return render.present(
		&surface.renderer,
		&surface.presentation,
		surface.target.pixels.color,
		render.pixel_viewport(RESOLUTION, {app.width, app.height}),
	)
}

destroy_surface :: proc(surface: ^Surface) {
	check(
		render.destroy_presentation(&surface.renderer, &surface.presentation),
		"destroy presentation",
	)
	destroy_pixel_target(&surface.renderer, &surface.target)
	if err := shaders.destroy(&surface.shaders); err != .None {
		log.errorf("Destroy example shaders: %v", err)
	}

	check(render.destroy(&surface.renderer), "destroy example renderer")
}

check :: proc(err: rhi.Error, operation: string) -> bool {
	if err != .None {
		log.errorf("%s: %v", operation, err)
	}

	return err == .None
}

check_ui :: proc(err: ui.Error) -> bool {
	if err != .None {
		log.errorf("UI: %v", err)
	}

	return err == .None
}
