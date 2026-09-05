package game

import "core:log"
import "ember:rhi"
import win "ember:platform/window"

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)

	context.logger = logger

	config := win.Config{
		title = "Ember",
		width = 1280,
		height = 720,
		vsync = true,
	}

	window: win.Window
	if !win.create(&window, config) {
		log.error("Failed to create window")
		return
	}
	defer win.destroy(&window)

	device, device_error := rhi.create_device(win.gl_context(&window))
	if device_error != .None {
		log.errorf("Failed to create rendering device: %v", device_error)
		return
	}
	defer {
		if err := rhi.destroy_device(&device); err != .None {
			log.errorf("Failed to destroy rendering device: %v", err)
		}
	}

	clear_color := [4]f32{ 0.1, 0.1, 0.1, 1.0 }

	for !win.should_close(&window) {
		win.poll_events()

		if window.framebuffer_resized {
			window.framebuffer_resized = false

			if !window.minimized {
				rhi.set_viewport(&device, window.width, window.height)
			}
		}

		if window.minimized {
			continue
		}

		rhi.clear(&device, clear_color, 1.0)

		win.swap_buffers(&window)
	}
}
