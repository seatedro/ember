#pragma once

#include "core/core.h"

namespace ember {

struct WindowConfig {
    const char* title;
    u32         width;
    u32         height;
    b32         vsync;
    b32         fullscreen;
};

struct Window {
    void* handle; // GLFWwindow*
    u32   width;
    u32   height;
    b32   should_close;
    b32   minimized;
};

b32 window_create(Window* w, const WindowConfig* cfg);
void window_destroy(Window* w);
void window_poll_events(Window* w);
void window_swap_buffers(Window* w);
f64 window_get_time(Window* w);

#if defined(EMBER_RHI_OPENGL)
void* get_gl_proc_address(const char* name);
#endif

} // namespace ember
