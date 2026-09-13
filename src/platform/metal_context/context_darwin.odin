package metal_context

import NS "core:sys/darwin/Foundation"

// The window owns this view and must outlive the rendering device.
Context :: struct {
	view:  ^NS.View,
	vsync: bool,
}
