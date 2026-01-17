#include "ember.h"
#include "platform/window.h"
#include "rhi/rhi.h"

namespace ember {

internal EmberConfig config_defaults(EmberConfig* cfg) {
    EmberConfig result = *cfg;

    if (!result.title)
        result.title = "ember";
    if (!result.width)
        result.width = 1280;
    if (!result.height)
        result.height = 720;
    if (!result.sample_count)
        result.sample_count = 1;
    if (result.fixed_timestep == 0.0f)
        result.fixed_timestep = 1.0f / 60.0f;

    return result;
}

global EmberContext g_ctx;
global EmberConfig  g_cfg;

EmberContext* ember_context() { return &g_ctx; }

f32 ember_frame_duration() { return g_ctx.dt; }

f64 ember_elapsed_time() { return g_ctx.time; }

u64 ember_frame_count() { return g_ctx.frame_count; }

void ember_request_quit() { g_ctx.running = false; }

internal void ember_init() {
    if (g_cfg.init) {
        g_cfg.init(g_cfg.userdata);
    }
}

internal void ember_update(f32 dt) {
    if (g_cfg.update) {
        g_cfg.update(g_cfg.userdata, dt);
    }
}

internal void ember_draw() {
    if (g_cfg.draw) {
        g_cfg.draw(g_cfg.userdata);
    }
}

internal void ember_quit() {
    if (g_cfg.quit) {
        g_cfg.quit(g_cfg.userdata);
    }
}

void ember_run(EmberConfig* cfg) {
    EMBER_ASSERT(cfg);

    g_cfg = config_defaults(cfg);
    g_ctx = {};

    WindowConfig win_cfg = {
        .title = g_cfg.title,
        .width = g_cfg.width,
        .height = g_cfg.height,
        .vsync = g_cfg.vsync,
        .fullscreen = false,
    };

    Window win = {};
    if (!window_create(&win, &win_cfg)) {
        LOG_ERROR("ember", "failed to create window");
        return;
    }
    g_ctx.window = &win;
    defer(window_destroy(&win));

    Device* dev = device_create(&win);
    if (!dev) {
        LOG_ERROR("ember", "failed to create device");
        return;
    }

    g_ctx.device = dev;
    defer(device_destroy(dev));

    g_ctx.frame_arena = Arena::create(MB(1));
    defer(Arena::destroy(&g_ctx.frame_arena));

    g_ctx.running = true;
    g_ctx.frame_count = 0;
    g_ctx.time = 0.0;

    ember_init();

    f64 last_time = window_get_time(&win);
    f64 acc = 0.0;
    f32 fixed_dt = g_cfg.fixed_timestep;
    f32 max_frame_time = 1.0f / 15.0f;

    // ember main loop
    while (g_ctx.running && !win.should_close) {
        window_poll_events(&win);

        f64 now = window_get_time(&win);
        f32 frame_time = (f32)(now - last_time);
        last_time = now;

        if (frame_time > max_frame_time) {
            frame_time = max_frame_time;
        }

        g_ctx.dt = frame_time;
        g_ctx.time = now;

        if (fixed_dt > 0.0f) {
            acc += frame_time;
            while (acc >= fixed_dt) {
                ember_update(fixed_dt);
                acc -= fixed_dt;
            }
        } else {
            ember_update(frame_time);
        }

        Arena::reset(&g_ctx.frame_arena);

        set_viewport(0, 0, win.width, win.height);
        ember_draw();

        window_swap_buffers(&win);
        g_ctx.frame_count++;
    }

    ember_quit();
}

} // namespace ember
