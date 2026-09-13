package window

import "../graphics"
import platform_metal "../metal_context"
import "vendor:glfw"

when graphics.METAL {
	device_context :: proc(window: ^Window) -> platform_metal.Context {
		if window == nil || window.handle == nil {
			return {}
		}

		return {view = glfw.GetCocoaWindow(window.handle)->contentView(), vsync = window.vsync}
	}
}
