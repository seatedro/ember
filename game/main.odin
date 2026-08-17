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

	device := rhi.create_device()
	defer rhi.destroy_device(&device)

	clear_color := [4]f32{ 0.1, 0.1, 0.1, 1.0 }

	for !win.should_close(&window) {
		win.poll_events()

		if window.framebuffer_resized {
			window.framebuffer_resized = false

			if !window.minimized {
				rhi.set_viewport(&device, window.width, window.height)
			}
		}

		rhi.clear(&device, clear_color, 1.0)

		win.swap_buffers(&window)
	}
}
