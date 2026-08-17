package rhi

import gl "vendor:OpenGL"
import "vendor:glfw"


Device :: struct {
	initialized: bool,
}

create_device :: proc() -> Device {
	when ODIN_OS == .Darwin {
		gl.load_up_to(4, 1, glfw.gl_set_proc_address)
	} else {
		gl.load_up_to(4, 6, glfw.gl_set_proc_address)
	}

	gl.Enable(gl.DEPTH_TEST)

	return Device{initialized = true}
}

destroy_device :: proc(device: ^Device) {
	device.initialized = false
}

set_viewport :: proc(device: ^Device, width, height: i32) {
	assert(device.initialized)
	gl.Viewport(0, 0, width, height)
}

clear :: proc(device: ^Device, color: [4]f32, depth: f64) {
	assert(device.initialized)
	gl.ClearColor(color[0], color[1], color[2], color[3])
	gl.ClearDepth(f64(depth))
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}
