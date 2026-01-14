#include "core/core.h"
#include "core/math.h"
#include "ember.h"
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

struct GameState {
    PipelineHandle pip;
    BufferHandle   vbo;
    BufferHandle   ibo;
    ShaderHandle   shader;

    mat4 proj;
    mat4 view;
    f32  rx;
    f32  ry;
};

void game_init(void* userdata) {
    GameState* game = (GameState*)userdata;
    Device*    d = ember_context()->device;
    Window*    w = ember_context()->window;
    Arena*     arena = &ember_context()->frame_arena;

    BufferConfig vb_desc = { .type = BufferType::Vertex,
                             .usage = BufferUsage::Static,
                             .data = cube_verts,
                             .size = sizeof(cube_verts) };

    game->vbo = buffer_create(d, &vb_desc);

    BufferConfig ib_desc = { .type = BufferType::Index,
                             .usage = BufferUsage::Static,
                             .data = cube_indices,
                             .size = sizeof(cube_indices) };

    game->ibo = buffer_create(d, &ib_desc);

    game->shader = shader_load_combined(arena, d, "shaders/basic.glsl", "basic");

    VertexLayout layout = { .attribs = {
        { .format = VertexFormat::F32x3, .offset = 0 }, // pos
        { .format = VertexFormat::F32x3, .offset = sizeof(f32) * 3 } // color
    }, .attrib_count = 2, .stride = sizeof(f32) * 6 };

    PipelineConfig pip_desc = {
        .shader = game->shader,
        .layout = layout,
        .depth = { .test_enabled = true, .write_enabled = true, .compare = CompareFn::Less },
        .raster = { .cull = CullMode::Back, .winding = Winding::CCW, .wireframe = false },
        .blend = BlendPresets::Opaque,
        .primitive = Primitive::Triangles,
    };

    game->pip = pipeline_create(d, &pip_desc);

    f32 aspect = (f32)w->width / (f32)w->height;
    game->proj = perspective(0.785f, aspect, 0.1f, 100.0f); // 45deg
    game->view = look_at({ 0, 1.5f, 4 }, { 0, 0, 0 }, { 0, 1, 0 });
    game->rx = 0.0f;
    game->ry = 0.0f;
}

void game_update(void* userdata, f32 dt) {
    GameState* game = (GameState*)userdata;

    game->rx += dt * 1.0f;
    game->ry += dt * 2.0f;
}

void game_draw(void* userdata) {
    GameState* game = (GameState*)userdata;
    Device*    d = ember_context()->device;
    Window*    w = ember_context()->window;

    mat4 model = rotate_x(game->rx) * rotate_y(game->ry);
    mat4 mvp = game->proj * game->view * model;

    set_viewport(0, 0, w->width, w->height);
    clear(0.1f, 0.1f, 0.1f, 1.0f, 1.0f);

    bind_pipeline(d, game->pip);
    bind_vertex_buffer(d, game->vbo);
    bind_index_buffer(d, game->ibo);
    set_uniform_mat4(d, game->shader, "u_mvp", &mvp);

    DrawConfig dd = {};
    dd.index_count = sizeof(cube_indices) / sizeof(cube_indices[0]);
    draw(d, &dd);
}

void game_quit(void* userdata) {
    GameState* game = (GameState*)userdata;
    Device*    dev = ember_context()->device;

    pipeline_destroy(dev, game->pip);
    shader_destroy(dev, game->shader);
    buffer_destroy(dev, game->ibo);
    buffer_destroy(dev, game->vbo);
}

global GameState g_state;

EmberConfig cfg = {
    .title = "ember",
    .width = 1280,
    .height = 720,
    .vsync = true,
    .sample_count = 0,
    .fixed_timestep = 0,
    .userdata = &g_state,
    .init = game_init,
    .update = game_update,
    .draw = game_draw,
    .quit = game_quit,
};
