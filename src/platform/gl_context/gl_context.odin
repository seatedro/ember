package gl_context

Context :: struct {
	id:           rawptr,
	major:        int,
	minor:        int,
	is_current:   proc(id: rawptr) -> bool,
	load_proc:    proc(destination: rawptr, name: cstring),
	swap_buffers: proc(id: rawptr),
}
