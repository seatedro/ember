const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const math = std.math;
const build_config = @import("build_config.zig");
const objc = @import("objc");

const rendering = @import("rendering/renderer.zig");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;
const SPRITE_W = 32;
const SPRITE_H = 32;
const MOVE_SPEED = 50.0;
const SPRITES_PER_CLICK = 100;

pub const Sprite = struct {
    rects: std.ArrayList(rendering.Rect),
    vx: std.ArrayList(f32),
    vy: std.ArrayList(f32),

    pub fn init(allocator: std.mem.Allocator) !Sprite {
        return Sprite{
            .rects = std.ArrayList(rendering.Rect).init(allocator),
            .vx = std.ArrayList(f32).init(allocator),
            .vy = std.ArrayList(f32).init(allocator),
        };
    }

    pub fn deinit(self: *Sprite) void {
        self.rects.deinit();
        self.vx.deinit();
        self.vy.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const perf_file = try std.fs.cwd().createFile("perf.csv", .{ .truncate = true });
    defer perf_file.close();

    try perf_file.writer().print("sprite_count,fps\n", .{});

    try sdl.errify(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    defer sdl.c.SDL_Quit();

    const backend = build_config.renderer;

    var window_flags = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_HIDDEN;
    if (backend == .OpenGL) {
        // Example: Add OpenGL flag if needed by that backend's init
        window_flags |= sdl.c.SDL_WINDOW_OPENGL;
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DOUBLEBUFFER, 1));
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DEPTH_SIZE, 24));
        try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_STENCIL_SIZE, 8));
        std.log.warn("OpenGL backend selected - Ensure necessary SDL_GL attributes are set BEFORE window creation if required.", .{});
    } else if (backend == .Metal) {
        window_flags |= sdl.c.SDL_WINDOW_METAL;
        std.log.warn("Metal backend selected - Ensure necessary SDL_METAL attributes are set BEFORE window creation if required.", .{});
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

    try sdl.errify(sdl.c.SDL_SetWindowPosition(
        window,
        sdl.c.SDL_WINDOWPOS_CENTERED,
        sdl.c.SDL_WINDOWPOS_CENTERED,
    ));

    // Setup Dear ImGui context
    const ig_context = cimgui.c.igCreateContext(null); // Store the returned context pointer
    if (ig_context == null) {
        // Check if context creation failed
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
    // Create renderer
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

    // State
    const clear_color = cimgui.c.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    const sprite_path = "assets/amogus.png";
    const stress_texture = try rendering.loadTexture(renderer_ctx, sprite_path);
    defer rendering.destroyTexture(stress_texture);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 49;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var sprites = try allocator.create(Sprite);
    defer sprites.deinit();
    defer allocator.destroy(sprites);
    sprites.* = try Sprite.init(allocator);

    var done = false;
    var left_down: bool = false;
    var event: sdl.c.SDL_Event = undefined;
    var win_w: c_int = 0;
    var win_h: c_int = 0;
    var last_ticks = sdl.c.SDL_GetTicks();
    // var last_log_time: u64 = 0;

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
                        try spawnSprite(sprites, rand.float(f32), event.button.x, event.button.y);
                    }
                    // try sprites.append(sdl.c.SDL_FRect{
                    //     .x = event.button.x,
                    //     .y = event.button.y,
                    //     .w = SPRITE_W,
                    //     .h = SPRITE_H,
                    // });
                },
                sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = false;
                },
                sdl.c.SDL_EVENT_MOUSE_MOTION => if (left_down) {
                    // try sprites.append(sdl.c.SDL_FRect{
                    //     .x = event.motion.x,
                    //     .y = event.motion.y,
                    //     .w = SPRITE_W,
                    //     .h = SPRITE_H,
                    // });
                    for (0..SPRITES_PER_CLICK) |_| {
                        try spawnSprite(sprites, rand.float(f32), event.motion.x, event.motion.y);
                    }
                },
                else => {},
            }
        }

        for (0..sprites.rects.items.len) |i| {
            sprites.rects.items[i].x += sprites.vx.items[i] * dt;
            sprites.rects.items[i].y += sprites.vy.items[i] * dt;
        }

        // Minimized? Sleep and skip frame
        if ((sdl.c.SDL_GetWindowFlags(window) & sdl.c.SDL_WINDOW_MINIMIZED) != 0) {
            sdl.c.SDL_Delay(10);
            continue;
        }

        // Start ImGui frame
        rendering.newImGuiFrame(renderer_ctx);
        cimgui.ImGui_ImplSDL3_NewFrame();
        cimgui.c.igNewFrame();

        {
            if (cimgui.c.igBegin("Ember Debug Console", null, 0)) {
                cimgui.c.igText("Sprites: %d", @as(c_int, @intCast(sprites.rects.items.len)));
                cimgui.c.igText(
                    "Perf: %.3f ms/frame (%.1f FPS)",
                    1000.0 / io.*.Framerate,
                    io.*.Framerate,
                );
            }
            // if (now - last_log_time >= 500) { // log every 500ms
            //     try perf_file.writer().print("{d},{d:.2}\n", .{
            //         sprites.rects.items.len,
            //         io.*.Framerate,
            //     });
            //     last_log_time = now;
            // }
            cimgui.c.igEnd();
        }

        // Rendering
        cimgui.c.igRender();
        const draw_data = cimgui.igGetDrawData();
        // SDL_RenderSetScale(renderer, io.*.DisplayFramebufferScale.x, io.*.DisplayFramebufferScale.y);
        try rendering.beginFrame(renderer_ctx, clear_color);

        // old
        // for (sprites.items) |s| {
        //     try rendering.drawTexture(renderer_ctx, stress_texture, null, s.rect);
        // }

        try rendering.drawTextureBatch(renderer_ctx, stress_texture, null, sprites.rects.items);

        if (draw_data) |data| { // Check draw_data is not null
            if (data.Valid and data.CmdListsCount > 0) {
                rendering.renderImGui(renderer_ctx, data);
            }
        } else {
            std.log.warn("ImGui draw data was null!", .{});
        }

        // End rendering
        try rendering.endFrame(renderer_ctx);
    }
}

fn spawnSprite(sprites: *Sprite, r: f32, mx: f32, my: f32) !void {
    const angle = r * math.pi * 2.0;
    const vx = math.cos(angle) * MOVE_SPEED;
    const vy = math.sin(angle) * MOVE_SPEED;
    try sprites.rects.append(rendering.Rect{
        .x = mx - (@as(f32, @floatFromInt(SPRITE_W / 2))),
        .y = my - (@as(f32, @floatFromInt(SPRITE_H / 2))),
        .w = SPRITE_W,
        .h = SPRITE_H,
    });
    try sprites.vx.append(vx);
    try sprites.vy.append(vy);
}
