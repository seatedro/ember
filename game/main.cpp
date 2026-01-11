#include "GLFW/glfw3.h"
#include "core/core.h"
#include "core/math.h"
#include "platform/window.h"
#include "rhi/rhi.h"
#include <cstdlib>

using namespace ember;

// clang-format off
global f32 cube_verts[] = {
    // front(red)
    -0.5f, -0.5f,  0.5f, 1, 0, 0,
     0.5f, -0.5f,  0.5f, 1, 0, 0,
     0.5f,  0.5f,  0.5f, 1, 0, 0,
    -0.5f,  0.5f,  0.5f, 1, 0, 0,
    // back(green)
    -0.5f, -0.5f, -0.5f, 0, 1, 0,
     0.5f, -0.5f, -0.5f, 0, 1, 0,
     0.5f,  0.5f, -0.5f, 0, 1, 0,
    -0.5f,  0.5f, -0.5f, 0, 1, 0,
    // top(blue)
    -0.5f,  0.5f, -0.5f, 0, 0, 1,
     0.5f,  0.5f, -0.5f, 0, 0, 1,
     0.5f,  0.5f,  0.5f, 0, 0, 1,
    -0.5f,  0.5f,  0.5f, 0, 0, 1,
    // bottom(yellow)
    -0.5f, -0.5f, -0.5f, 1, 1, 0,
     0.5f, -0.5f, -0.5f, 1, 1, 0,
     0.5f, -0.5f,  0.5f, 1, 1, 0,
    -0.5f, -0.5f,  0.5f, 1, 1, 0,
    // right(magenta)
     0.5f, -0.5f, -0.5f, 1, 0, 1,
     0.5f,  0.5f, -0.5f, 1, 0, 1,
     0.5f,  0.5f,  0.5f, 1, 0, 1,
     0.5f, -0.5f,  0.5f, 1, 0, 1,
    // left(cyan)
    -0.5f, -0.5f, -0.5f, 0, 1, 1,
    -0.5f,  0.5f, -0.5f, 0, 1, 1,
    -0.5f,  0.5f,  0.5f, 0, 1, 1,
    -0.5f, -0.5f,  0.5f, 0, 1, 1,
};

global u32 cube_indices[] = {
    0,  1,  2,   2,  3,  0,  // front
    4,  7,  6,   6,  5,  4,  // back
    8,  11, 10,  10, 9,  8,  // top
    12, 13, 14,  14, 15, 12, // bottom
    16, 17, 18,  18, 19, 16, // right
    20, 22, 21,  22, 20, 23, // left
};
// clang-format on

#if defined(__APPLE__)
global const char* vert_src = R"(
    #version 410 core
    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec3 a_color;
    uniform mat4 u_mvp;
    out vec3 v_color;
    void main() {
        gl_Position = u_mvp * vec4(a_position, 1.0);
        v_color = a_color;
    }
)";

global const char* frag_src = R"(
    #version 410 core
    in vec3 v_color;
    out vec4 frag_color;
    void main() {
        frag_color = vec4(v_color, 1.0);
    }
)";
#else
global const char* vert_src = R"(
    #version 460 core
    layout(location = 0) in vec3 a_position;
    layout(location = 1) in vec3 a_color;
    uniform mat4 u_mvp;
    out vec3 v_color;
    void main() {
        gl_Position = u_mvp * vec4(a_position, 1.0);
        v_color = a_color;
    }
)";

global const char* frag_src = R"(
    #version 460 core
    in vec3 v_color;
    out vec4 frag_color;
    void main() {
        frag_color = vec4(v_color, 1.0);
    }
)";
#endif

int main() {
    Window       w = Window {};
    WindowConfig cfg = {
        .title = "ember",
        .width = 1280,
        .height = 720,
        .vsync = true,
        .fullscreen = false,
    };
    b32 ok = window_create(&w, &cfg);

    if (!ok) {
        LOG_ERROR("main", "window failed to create");
        return 1;
    }

    Device* d = device_create(&w);
    if (!d) {
        LOG_ERROR("main", "failed to create rhi device");
        window_destroy(&w);
    }

    BufferDesc vb_desc = { .type = BufferType::Vertex,
        .usage = BufferUsage::Static,
        .data = cube_verts,
        .size = sizeof(cube_verts) };

    BufferHandle vbo = buffer_create(d, &vb_desc);

    BufferDesc ib_desc = { .type = BufferType::Index,
        .usage = BufferUsage::Static,
        .data = cube_indices,
        .size = sizeof(cube_indices) };

    BufferHandle ibo = buffer_create(d, &ib_desc);

    ShaderDesc sh_desc
        = { .vertex_src = vert_src, .fragment_src = frag_src, .name = "basic shader" };

    ShaderHandle shader = shader_create(d, &sh_desc);

    VertexAttrib attribs[] = {
        { .format = VertexFormat::F32x3, .offset = 0 }, // pos
        { .format = VertexFormat::F32x3, .offset = sizeof(f32) * 3 } // color
    };

    VertexLayout layout = { .attribs = attribs, .attrib_count = 2, .stride = sizeof(f32) * 6 };

    PipelineDesc pip_desc = {
        .shader = shader,
        .layout = layout,
        .depth = { .test_enabled = true, .write_enabled = true, .compare = CompareFn::Less },
        .raster = { .cull = CullMode::Back, .winding = Winding::CCW, .wireframe = false },
        .primitive = Primitive::Triangles,
    };

    PipelineHandle pipeline = pipeline_create(d, &pip_desc);

    f32  aspect = (f32)w.width / (f32)w.height;
    mat4 proj = perspective(0.785f, aspect, 0.1f, 100.0f); // 45deg
    mat4 view = look_at({ 0, 1.5f, 4 }, { 0, 0, 0 }, { 0, 1, 0 });

    f64 last_time = glfwGetTime();

    while (!w.should_close) {
        window_poll_events(&w);

        f64 now = window_get_time(&w);
        f32 dt = (f32)(now - last_time);
        last_time = now;

        static f32 rx = 0.0f, ry = 0.0f;
        rx += dt * 1.0f;
        ry += dt * 2.0f;
        mat4 model = rotate_y(ry) * rotate_x(rx);
        mat4 mvp = proj * view * model;

        set_viewport(0, 0, w.width, w.height);
        clear(0.1f, 0.1f, 0.1f, 1.0f, 1.0f);

        bind_pipeline(d, pipeline);
        bind_vertex_buffer(d, vbo);
        bind_index_buffer(d, ibo);
        set_uniform_mat4(d, shader, "u_mvp", &mvp);

        DrawDesc dd = {};
        dd.index_count = sizeof(cube_indices) / sizeof(cube_indices[0]);
        draw(d, &dd);

        window_swap_buffers(&w);
    }

    pipeline_destroy(d, pipeline);
    shader_destroy(d, shader);
    buffer_destroy(d, ibo);
    buffer_destroy(d, vbo);
    device_destroy(d);
    window_destroy(&w);

    return 0;
}
