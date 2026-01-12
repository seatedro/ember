#pragma once

#include "core/core.h"

namespace ember {

struct EmberConfig {
    const char* title;
    u32         width;
    u32         height;
    b32         vsync;
    u32         sample_count;
    f32         fixed_timestep; // 0 = variable, >0 = fixed

    void* userdata;

    void (*init)(void* userdata);
    void (*update)(void* userdata, f32 dt);
    void (*draw)(void* userdata);
    void (*quit)(void* userdata);
};

struct EmberContext {
    struct Window* window;
    struct Device* device;
    Arena          frame_arena;
    f32            dt;
    f64            time;
    u64            frame_count;
    b32            running;
};

void ember_run(EmberConfig* cfg);

f32           ember_frame_duration();
f64           ember_elapsed_time();
u64           ember_frame_count();
EmberContext* ember_context();
void          ember_request_quit();

} // namespace ember
