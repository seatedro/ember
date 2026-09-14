package engine

import "../input"
import win "../platform/window"
import "../rhi"
import "core:log"
import "core:math"
import "core:time"

Config :: struct {
	title:          string,
	width, height:  i32,
	vsync:          bool,
	hidden:         bool,
	fixed_timestep: f64,
	userdata:       rawptr,
	init:           proc(app: ^Context, userdata: rawptr) -> bool,
	update:         proc(app: ^Context, userdata: rawptr, dt: f32),
	draw:           proc(app: ^Context, userdata: rawptr) -> bool,
	quit:           proc(app: ^Context, userdata: rawptr),
}

Context :: struct {
	cursor:        input.Cursor,
	device:        ^rhi.Device,
	width, height: i32,
	window_size:   [2]i32,
	delta_time:    f32,
	elapsed_time:  f64,
	frame_count:   u64,
	running:       bool,
	clipboard:     input.Clipboard,
	input:         ^input.State,
}

Error :: enum {
	None,
	Invalid_Config,
	Window_Failed,
	Device_Failed,
	Init_Failed,
	Draw_Failed,
	Shutdown_Failed,
}

request_quit :: proc(app: ^Context) {
	app.running = false
}

// quit also runs after failed init, while the device is alive, to clean up partial state.
run :: proc(config: Config) -> (result: Error) {
	if config.width <= 0 ||
	   config.height <= 0 ||
	   !(config.fixed_timestep >= 0) ||
	   math.is_inf(config.fixed_timestep) {
		return .Invalid_Config
	}
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger

	window: win.Window
	if !win.create(
		&window,
		win.Config {
			title = config.title,
			width = config.width,
			height = config.height,
			vsync = config.vsync,
			hidden = config.hidden,
		},
	) {
		log.error("Failed to create window")
		return .Window_Failed
	}
	defer win.destroy(&window)

	device, device_error := rhi.create_device(win.device_context(&window))
	if device_error != .None {
		log.errorf("Failed to create rendering device: %v", device_error)
		return .Device_Failed
	}
	defer {
		if err := rhi.destroy_device(&device); err != .None {
			log.errorf("Failed to destroy rendering device: %v", err)
			if result == .None {
				result = .Shutdown_Failed
			}
		}
	}

	app := Context {
		device      = &device,
		width       = window.width,
		height      = window.height,
		running     = true,
		input       = &window.input,
		clipboard   = win.clipboard(&window),
		window_size = win.size(&window),
	}
	defer {
		// Close unfinished GPU work before the game releases its resources.
		if err := rhi.discard_frame(&device); err != .None {
			log.errorf("Failed to discard frame: %v", err)
			if result == .None {
				result = .Shutdown_Failed
			}
		}

		if config.quit != nil {
			config.quit(&app, config.userdata)
		}
	}

	if config.init != nil && !config.init(&app, config.userdata) {
		log.error("Game initialization failed")
		return .Init_Failed
	}

	last_time := time.tick_now()
	accumulator: f64
	for app.running && !win.should_close(&window) {
		win.poll_events()
		if win.should_close(&window) {
			break
		}
		app.width, app.height = window.width, window.height
		app.window_size = win.size(&window)
		if window.minimized {
			win.wait_events(0.05)
			last_time = time.tick_now()
			accumulator = 0
			continue
		}
		if window.framebuffer_resized {
			window.framebuffer_resized = false
		}

		now := time.tick_now()
		dt := min(time.duration_seconds(time.tick_diff(last_time, now)), 1.0 / 15.0)
		last_time = now
		app.delta_time = f32(dt)
		app.elapsed_time += dt
		app.cursor = .Arrow
		run_updates(config, &app, dt, &accumulator)
		if !app.running {
			break
		}

		if err := rhi.begin_frame(&device, {app.width, app.height}); err != .None {
			if err == .Surface_Unavailable {
				win.wait_events(0.01)
				continue
			}
			log.errorf("Failed to begin frame: %v", err)
			return .Draw_Failed
		}

		if config.draw != nil && !config.draw(&app, config.userdata) {
			log.error("Game draw failed")
			return .Draw_Failed
		}

		if err := rhi.end_frame(&device); err != .None {
			log.errorf("Failed to end frame: %v", err)
			return .Draw_Failed
		}

		win.set_cursor(&window, app.cursor)
		app.frame_count += 1
	}
	return .None
}

@(private)
run_updates :: proc(config: Config, app: ^Context, dt: f64, accumulator: ^f64) {
	if config.update == nil {
		return
	}
	if config.fixed_timestep > 0 {
		accumulator^ += dt
		for accumulator^ >= config.fixed_timestep && app.running {
			config.update(app, config.userdata, f32(config.fixed_timestep))
			input.clear(app.input)
			accumulator^ -= config.fixed_timestep
		}
	} else {
		config.update(app, config.userdata, f32(dt))
		input.clear(app.input)
	}
}
