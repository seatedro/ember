#pragma once

#include "core/core.h"

namespace ember {

struct Window {
    void* handle; // GLFWwindow*
    u32   height;
    u32   width;
    b32   should_close;
};

b32  create_window(Window* w, u32 width, u32 height, const char* title);
void destroy_window(Window* w);
void poll_events(Window* w);
void swap_buffers(Window* w);

#if defined(EMBER_RHI_OPENGL)
void* get_gl_proc_address(const char* name);
#endif

} // namespace ember
