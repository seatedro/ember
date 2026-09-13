package window

import "../../input"
import "base:runtime"
import "core:log"
import "core:strings"
import "vendor:glfw"

Config :: struct {
	title:  string,
	width:  i32,
	height: i32,
	vsync:  bool,
	hidden: bool,
}

Window :: struct {
	handle:              glfw.WindowHandle,
	width:               i32,
	height:              i32,
	framebuffer_resized: bool,
	minimized:           bool,
	input:               input.State,
}

glfw_callback_context: runtime.Context

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = glfw_callback_context
	log.errorf("glfw: %i: %s", error, description)
}

create :: proc(window: ^Window, config: Config) -> bool {
	glfw_callback_context = context
	glfw.SetErrorCallback(glfw_error_callback)

	if !bool(glfw.Init()) {
		return false
	}

	when ODIN_OS == .Darwin {
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
		glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	} else {
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	}

	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE if config.hidden else glfw.TRUE)

	title := strings.clone_to_cstring(config.title, context.temp_allocator)
	handle := glfw.CreateWindow(config.width, config.height, title, nil, nil)

	if handle == nil {
		glfw.Terminate()
		return false
	}

	glfw.MakeContextCurrent(handle)
	if config.vsync {
		glfw.SwapInterval(1)
	} else {
		glfw.SwapInterval(0)
	}

	window.handle = handle
	glfw.SetWindowUserPointer(handle, rawptr(window))
	glfw.SetFramebufferSizeCallback(handle, framebuffer_size_callback)
	init_input(window)

	window.width, window.height = glfw.GetFramebufferSize(handle)
	window.framebuffer_resized = true
	window.minimized = window.width == 0 || window.height == 0

	return true
}

destroy :: proc(window: ^Window) {
	input.destroy(&window.input)
	if window.handle != nil {
		glfw.DestroyWindow(window.handle)
		window.handle = nil
	}

	glfw.Terminate()
}

poll_events :: proc() {
	glfw.PollEvents()
}

wait_events :: proc(timeout: f64) {
	glfw.WaitEventsTimeout(timeout)
}

should_close :: proc(window: ^Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

framebuffer_size_callback :: proc "c" (handle: glfw.WindowHandle, width, height: i32) {
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	if window == nil {
		return
	}

	window.width = width
	window.height = height
	window.framebuffer_resized = true
	window.minimized = width == 0 || height == 0
}

size :: proc(window: ^Window) -> [2]i32 {
	width, height := glfw.GetWindowSize(window.handle)
	return {width, height}
}
