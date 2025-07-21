const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const build_config = @import("build_config.zig");

const core = @import("core/types.zig");
const physics = @import("physics/verlet.zig");
const math = std.math;

const rendering = @import("rendering/renderer.zig");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;
const PARTICLES_PER_CLICK = 1;

const PHYS_GRAVITY = core.Vec2{ 0.0, 1000.0 };
const PARTICLE_RADIUS = 10.0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const rval = sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO);
    if (!rval) {
        std.log.err("SDL_Init failed: {s}", .{sdl.c.SDL_GetError()});
    }
    defer sdl.c.SDL_Quit();

    const backend = build_config.renderer;

    var window_flags = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_HIDDEN;
    if (backend == .OpenGL) {
        window_flags |= sdl.c.SDL_WINDOW_OPENGL;
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DOUBLEBUFFER, 1));
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DEPTH_SIZE, 24));
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_STENCIL_SIZE, 8));
        std.log.warn("OpenGL backend selected - Ensure necessary SDL_GL attributes are set BEFORE window creation if required.", .{});
    }

    const window = sdl.c.SDL_CreateWindow(
        "Ember Engine",
        WIN_WIDTH,
        WIN_HEIGHT,
        window_flags,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow failed: {s}", .{sdl.c.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    }
    defer sdl.c.SDL_DestroyWindow(window);

    // Setting the position is not supported by the Wayland backend; skip it there.
    const video_driver_cstr = sdl.c.SDL_GetCurrentVideoDriver() orelse null;
    const skip_set_pos = if (video_driver_cstr) |cstr| blk: {
        const name = std.mem.span(cstr);
        break :blk std.mem.eql(u8, name, "wayland");
    } else false;

    if (!skip_set_pos) {
        sdl.errify(sdl.c.SDL_SetWindowPosition(
            window,
            sdl.c.SDL_WINDOWPOS_CENTERED,
            sdl.c.SDL_WINDOWPOS_CENTERED,
        )) catch {
            std.log.err("SDL_SetWindowPosition failed: {s}", .{sdl.c.SDL_GetError()});
            // Non-fatal; just continue running.
        };
    } else {
        std.log.debug("Skipping SDL_SetWindowPosition – not supported by Wayland backend", .{});
    }

    const ig_context = cimgui.c.igCreateContext(null);
    if (ig_context == null) {
        std.log.err("Failed to create ImGui context!", .{});
        sdl.c.SDL_DestroyWindow(window);
        sdl.c.SDL_Quit();
        return error.ImGuiContextCreationFailed;
    }
    defer cimgui.c.igDestroyContext(ig_context);

    const io = cimgui.c.igGetIO();
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableGamepad;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_ViewportsEnable;

    cimgui.c.igStyleColorsDark(null);

    defer cimgui.ImGui_ImplSDL3_Shutdown();

    var renderer_ctx = rendering.init(allocator, window.?) catch {
        cimgui.c.igDestroyContext(ig_context);
        sdl.c.SDL_DestroyWindow(window);
        sdl.c.SDL_Quit();
        return error.InitializationFailed;
    };
    defer rendering.deinit(&renderer_ctx);

    try sdl.errify(sdl.c.SDL_ShowWindow(window));
    try rendering.setVSync(&renderer_ctx, true);

    try rendering.initImGuiBackend(&renderer_ctx);
    defer rendering.deinitImGuiBackend();

    const clear_color = cimgui.c.ImVec4{ .x = 0.01, .y = 0.01, .z = 0.01, .w = 1.00 };

    var world = try physics.World.init(allocator, PHYS_GRAVITY);
    defer world.deinit();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 0;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
            std.log.warn("Failed to get random seed: {}, using default", .{err});
            seed = @as(u64, @intCast(std.time.timestamp()));
        };
        break :blk seed;
    });
    const rand = prng.random();

    var done = false;
    var left_down: bool = false;
    var space_held: bool = false;
    var particle_spawn_timer: f32 = 0.0;
    const particle_spawn_interval: f32 = 0.05;
    var event: sdl.c.SDL_Event = undefined;
    var win_w: c_int = 0;
    var win_h: c_int = 0;
    var last_ticks = sdl.c.SDL_GetTicks();

    try sdl.errify(sdl.c.SDL_GetWindowSize(window, &win_w, &win_h));

    const boundary_center = core.Vec2{ @as(f32, @floatFromInt(win_w)) / 2.0, @as(f32, @floatFromInt(win_h)) / 2.0 };
    const boundary_radius = @min(@as(f32, @floatFromInt(win_w)), @as(f32, @floatFromInt(win_h))) / 2.0 - 20.0;
    world.setBoundaryCircle(boundary_center, boundary_radius, 2);

    while (!done) {
        const now = sdl.c.SDL_GetTicks();
        const dt: f32 = @as(f32, @floatFromInt(now - last_ticks)) / 1000.0;
        last_ticks = now;

        while (sdl.c.SDL_PollEvent(&event)) {
            _ = cimgui.ImGui_ImplSDL3_ProcessEvent(&event);
            if (io.*.WantCaptureMouse) {
                continue;
            }

            switch (event.type) {
                sdl.c.SDL_EVENT_QUIT => done = true,
                sdl.c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (event.window.windowID == sdl.c.SDL_GetWindowID(window)) {
                        done = true;
                    }
                },
                sdl.c.SDL_EVENT_WINDOW_RESIZED => {
                    const w = event.window.data1;
                    const h = event.window.data2;
                    try rendering.resize(&renderer_ctx, w, h);
                },
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = true;
                    for (0..PARTICLES_PER_CLICK) |_| {
                        const color = @Vector(4, f32){
                            rand.float(f32), // Red
                            rand.float(f32), // Green
                            rand.float(f32), // Blue
                            1.0, // Alpha
                        };
                        try world.addParticle(core.Vec2{ event.button.x, event.button.y }, PARTICLE_RADIUS, color);
                    }
                },
                sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = false;
                },
                sdl.c.SDL_EVENT_KEY_DOWN => if (event.key.key == sdl.c.SDLK_SPACE) {
                    space_held = true;
                },
                sdl.c.SDL_EVENT_KEY_UP => if (event.key.key == sdl.c.SDLK_SPACE) {
                    space_held = false;
                    particle_spawn_timer = 0.0;
                },
                else => {},
            }
        }

        if (space_held) {
            particle_spawn_timer += dt;
            while (particle_spawn_timer >= particle_spawn_interval) {
                particle_spawn_timer -= particle_spawn_interval;

                const color = @Vector(4, f32){
                    rand.float(f32), // Red
                    rand.float(f32), // Green
                    rand.float(f32), // Blue
                    1.0, // Alpha
                };
                var x: f32 = 0;
                var y: f32 = 0;
                _ = sdl.c.SDL_GetMouseState(&x, &y);
                try world.addParticle(core.Vec2{ x, y }, PARTICLE_RADIUS, color);
            }
        }

        world.step(dt);

        if ((sdl.c.SDL_GetWindowFlags(window) & sdl.c.SDL_WINDOW_MINIMIZED) != 0) {
            sdl.c.SDL_Delay(10);
            continue;
        }

        cimgui.ImGui_ImplSDL3_NewFrame();
        rendering.newImGuiFrame();
        cimgui.c.igNewFrame();

        {
            if (cimgui.c.igBegin("Ember Debug Console", null, 0)) {
                cimgui.c.igText("Particles: %d", @as(c_int, @intCast(world.len())));
                cimgui.c.igText(
                    "Perf: %.3f ms/frame (%.1f FPS)",
                    1000.0 / io.*.Framerate,
                    io.*.Framerate,
                );
                cimgui.c.igText("Ember: A silly little game engine");
            }
            cimgui.c.igEnd();
        }

        cimgui.c.igRender();

        try rendering.beginFrame(&renderer_ctx, clear_color);

        for (world.particles.items) |p| {
            try rendering.drawCircleFilled(&renderer_ctx, p.position, PARTICLE_RADIUS, p.color);
        }

        try rendering.drawCircle(&renderer_ctx, boundary_center, boundary_radius, rendering.Color.WHITE);

        try rendering.render(&renderer_ctx, clear_color);

        try rendering.endFrame(&renderer_ctx);
    }
}
