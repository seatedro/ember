#include "platform/window.h"
#include <cstdlib>

int main() {
    ember::Window window = ember::Window::create(1280, 720, "ember");

    LOG_INFO("main", "window created: handle=%p, should_close=%d",
        window.handle, window.should_close);

    while (!window.should_close) {
        ember::Window::poll_events(&window);
        ember::Window::swap_buffers(&window);
    }

    ember::Window::destroy(&window);
    return 0;
}
