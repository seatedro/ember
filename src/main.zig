const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const math = std.math;
const build_config = @import("build_config.zig");

const rendering = @import("rendering/renderer.zig");
const sprite = @import("sprite/sprite.zig");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;
const SPRITE_W = 32;
const SPRITE_H = 32;
const MOVE_SPEED = 50.0;
const SPRITES_PER_CLICK = 100;

const SpriteData = struct {
    transform: rendering.Transform2D,
    velocity: @Vector(2, f32),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // try sdl.errify(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
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
        "Ember Engine - High Performance Renderer",
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

    const renderer_ctx = rendering.init(allocator, window.?) catch {
        cimgui.c.igDestroyContext(ig_context);
        sdl.c.SDL_DestroyWindow(window);
        sdl.c.SDL_Quit();
        return error.InitializationFailed;
    };
    defer rendering.deinit(allocator, renderer_ctx);

    try sdl.errify(sdl.c.SDL_ShowWindow(window));
    try rendering.setVSync(renderer_ctx, true);

    try rendering.initImGuiBackend(renderer_ctx);
    defer rendering.deinitImGuiBackend();

    const clear_color = cimgui.c.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    const sprite_path = "assets/amogus.png";
    const stress_texture = try rendering.loadTexture(renderer_ctx, sprite_path);
    defer rendering.destroyTexture(renderer_ctx, stress_texture);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 49;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var sprites = std.ArrayList(SpriteData).init(allocator);
    defer sprites.deinit();

    var done = false;
    var left_down: bool = false;
    var event: sdl.c.SDL_Event = undefined;
    var win_w: c_int = 0;
    var win_h: c_int = 0;
    var last_ticks = sdl.c.SDL_GetTicks();

    try sdl.errify(sdl.c.SDL_GetWindowSize(window, &win_w, &win_h));

    std.log.debug("Window size: {}x{}", .{ win_w, win_h });

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
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = true;
                    for (0..SPRITES_PER_CLICK) |_| {
                        try spawnSprite(&sprites, rand, event.button.x, event.button.y);
                    }
                },
                sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = false;
                },
                sdl.c.SDL_EVENT_MOUSE_MOTION => if (left_down) {
                    for (0..SPRITES_PER_CLICK) |_| {
                        try spawnSprite(&sprites, rand, event.motion.x, event.motion.y);
                    }
                },
                else => {},
            }
        }

        for (sprites.items) |*s| {
            s.transform.position += s.velocity * @as(@Vector(2, f32), @splat(dt));
        }

        if ((sdl.c.SDL_GetWindowFlags(window) & sdl.c.SDL_WINDOW_MINIMIZED) != 0) {
            sdl.c.SDL_Delay(10);
            continue;
        }

        cimgui.ImGui_ImplSDL3_NewFrame();
        rendering.newImGuiFrame();
        cimgui.c.igNewFrame();

        {
            if (cimgui.c.igBegin("Ember Debug Console", null, 0)) {
                cimgui.c.igText("Sprites: %d", @as(c_int, @intCast(sprites.items.len)));
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

        try rendering.beginFrame(renderer_ctx, clear_color);

        for (sprites.items) |s| {
            const sprite_data = rendering.SpriteDrawData{
                .transform = s.transform,
                .texture_handle = stress_texture,
                .color = rendering.Color.WHITE,
            };
            try rendering.drawSprite(renderer_ctx, sprite_data);
        }

        try rendering.drawCircle(renderer_ctx, @Vector(2, f32){ 100.0, 100.0 }, 25.0, rendering.Color.RED);
        try rendering.drawLine(renderer_ctx, @Vector(2, f32){ 50.0, 50.0 }, @Vector(2, f32){ 150.0, 150.0 }, 2.0, rendering.Color.GREEN);
        try rendering.drawRect(renderer_ctx, @Vector(2, f32){ 200.0, 200.0 }, @Vector(2, f32){ 50.0, 30.0 }, rendering.Color.BLUE);

        try rendering.render(renderer_ctx, clear_color);

        try rendering.endFrame(renderer_ctx);
    }
}

fn spawnSprite(sprites: *std.ArrayList(SpriteData), rand: std.Random, mx: f32, my: f32) !void {
    const angle = rand.float(f32) * math.pi * 2.0;
    const velocity = @Vector(2, f32){
        math.cos(angle) * MOVE_SPEED,
        math.sin(angle) * MOVE_SPEED,
    };
    const position = @Vector(2, f32){
        mx - (@as(f32, @floatFromInt(SPRITE_W / 2))),
        my - (@as(f32, @floatFromInt(SPRITE_H / 2))),
    };
    try sprites.append(SpriteData{
        .transform = rendering.Transform2D{
            .position = position,
            .scale = @Vector(2, f32){ 1.0, 1.0 },
        },
        .velocity = velocity,
    });
}
