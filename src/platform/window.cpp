#include "window.h"
#include "core/core.h"
#include <GLFW/glfw3.h>

namespace ember {

internal void glfw_error_callback(int error, const char* desc) {
    LOG_ERROR("glfw", "[%d] %s", error, desc);
}

Window Window::create(u32 width, u32 height, const char* title) {
    glfwSetErrorCallback(glfw_error_callback);

    if (glfwInit() != GLFW_TRUE) {
        LOG_ERROR("window", "failed to init glfw");
        Window w = {};
        w.should_close = 1;
        return w;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* handle = glfwCreateWindow(width, height, title, null, null);
    if (!handle) {
        LOG_ERROR("window", "failed to create window");
        glfwTerminate();
        Window w = {};
        w.should_close = 1;
        return w;
    }

    EMBER_ASSERT(handle != null);

    glfwMakeContextCurrent(handle);
    glfwSwapInterval(1); // vsync

    LOG_INFO("window", "created window : %dx%d", width, height);

    return {
        .handle = handle,
        .height = height,
        .width = width,
        .should_close = false,
    };
}

void Window::destroy(Window* w) {
    if (w->handle) {
        glfwDestroyWindow((GLFWwindow*)w->handle);
        glfwTerminate();
        w->handle = null;
    }
}

void Window::poll_events(Window* w) {
    glfwPollEvents();
    w->should_close = glfwWindowShouldClose((GLFWwindow*)w->handle);
}

void Window::swap_buffers(Window* w) {
    glfwSwapBuffers((GLFWwindow*)w->handle);
}

} // namespace ember
