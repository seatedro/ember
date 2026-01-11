#include "window.h"
#include "core/core.h"
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#if defined(EMBER_RHI_OPENGL)
#include <glad/glad.h>
#endif

namespace ember {

internal void glfw_error_callback(int error, const char* desc) {
    LOG_ERROR("glfw", "[%d] %s", error, desc);
}

b32 window_create(Window* w, const WindowConfig* cfg) {
    glfwSetErrorCallback(glfw_error_callback);

    if (glfwInit() != GLFW_TRUE) {
        LOG_ERROR("window", "failed to init glfw");
        return false;
    }

#if defined(EMBER_RHI_OPENGL)
#if defined(__APPLE__)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#else
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#endif
#elif defined(EMBER_RHI_VULKAN)
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
#else
#error "No RHI backend defined"
#endif

    GLFWwindow* handle = glfwCreateWindow(cfg->width, cfg->height, cfg->title, null, null);
    if (!handle) {
        LOG_ERROR("window", "failed to create window");
        glfwTerminate();
        return false;
    }

    EMBER_ASSERT(handle != null);

#if defined(EMBER_RHI_OPENGL)
    glfwMakeContextCurrent(handle);
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        LOG_ERROR("window", "failed to load OpenGL");
        return false;
    }
    LOG_INFO("window", "OpenGL %s", glGetString(GL_VERSION));
    glfwSwapInterval(1); // vsync
#endif

    w->handle = handle;
    w->height = cfg->height;
    w->width = cfg->width;
    w->should_close = false;

    LOG_INFO("window", "created window : %dx%d", cfg->width, cfg->height);

    return true;
}

void window_destroy(Window* w) {
    if (w->handle) {
        glfwDestroyWindow((GLFWwindow*)w->handle);
        glfwTerminate();
        w->handle = null;
    }
}

void window_poll_events(Window* w) {
    glfwPollEvents();
    w->should_close = glfwWindowShouldClose((GLFWwindow*)w->handle);
}

void window_swap_buffers(Window* w) { glfwSwapBuffers((GLFWwindow*)w->handle); }

f64 window_get_time(Window* w) {
    (void)w;
    return glfwGetTime();
}

} // namespace ember
