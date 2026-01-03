#pragma once

#include "core/core.h"

namespace ember {

struct Window {
    void* handle; // GLFWwindow*
    u32   height;
    u32   width;
    b32   should_close;

    static Window create(u32 width, u32 height, const char* title);
    static void   destroy(Window* w);
    static void   poll_events(Window* w);
    static void   swap_buffers(Window* w);
};

} // namespace ember
