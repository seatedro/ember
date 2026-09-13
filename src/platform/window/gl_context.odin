package window

import platform_gl "../gl_context"
import "../graphics"
import "vendor:glfw"

when !graphics.METAL {
	device_context :: proc(window: ^Window) -> platform_gl.Context {
		if window == nil || window.handle == nil {
			return {}
		}

		return platform_gl.Context {
			id = rawptr(window.handle),
			major = int(glfw.GetWindowAttrib(window.handle, glfw.CONTEXT_VERSION_MAJOR)),
			minor = int(glfw.GetWindowAttrib(window.handle, glfw.CONTEXT_VERSION_MINOR)),
			is_current = gl_context_is_current,
			load_proc = glfw.gl_set_proc_address,
			swap_buffers = gl_swap_buffers,
		}
	}

	@(private)
	gl_context_is_current :: proc(id: rawptr) -> bool {
		return id != nil && rawptr(glfw.GetCurrentContext()) == id
	}

	@(private)
	gl_swap_buffers :: proc(id: rawptr) {
		glfw.SwapBuffers(cast(glfw.WindowHandle)id)
	}
}
