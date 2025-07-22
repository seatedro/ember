const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const build_config = @import("../src/build_config.zig");
const math = std.math;

const rendering = @import("../src/rendering/renderer.zig");

// ---------------------------------------------------------------------------
//                               Constants                                     
// ---------------------------------------------------------------------------
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

/// Example entry-point: run with `zig run examples/spawn_sprites.zig` or wire it
/// into `build.zig` as needed.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialise SDL3 video.
    if (sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO) != 0) {
        return error.SDLInitFailed;
    }
    defer sdl.c.SDL_Quit();

    const backend = build_config.renderer;

    var window_flags: u32 = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_HIDDEN;
    if (backend == .OpenGL) {
        window_flags |= sdl.c.SDL_WINDOW_OPENGL;
    }

    const window = sdl.c.SDL_CreateWindow("Sprite Stress Test", WIN_WIDTH, WIN_HEIGHT, window_flags);
    if (window == null) return error.WindowCreateFailed;
    defer sdl.c.SDL_DestroyWindow(window);

    const renderer_ctx = try rendering.init(allocator, window.?);
    defer rendering.deinit(allocator, renderer_ctx);
    try rendering.setVSync(renderer_ctx, true);

    const sprite_path = "assets/amogus.png";
    const texture = try rendering.loadTexture(renderer_ctx, sprite_path);
    defer rendering.destroyTexture(renderer_ctx, texture);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 1234;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var sprites = std.ArrayList(SpriteData).init(allocator);
    defer sprites.deinit();

    var done = false;
    var left_down = false;
    var event: sdl.c.SDL_Event = undefined;
    var last_ticks = sdl.c.SDL_GetTicks();

    try sdl.errify(sdl.c.SDL_ShowWindow(window));

    while (!done) {
        const now = sdl.c.SDL_GetTicks();
        const dt: f32 = @as(f32, @floatFromInt(now - last_ticks)) / 1000.0;
        last_ticks = now;

        while (sdl.c.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.c.SDL_EVENT_QUIT => done = true,
                sdl.c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => done = true,
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = true;
                    for (0..SPRITES_PER_CLICK) |_|
                        try spawnSprite(&sprites, rand, event.button.x, event.button.y);
                },
                sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => if (event.button.button == sdl.c.SDL_BUTTON_LEFT) {
                    left_down = false;
                },
                sdl.c.SDL_EVENT_MOUSE_MOTION => if (left_down) {
                    for (0..SPRITES_PER_CLICK) |_|
                        try spawnSprite(&sprites, rand, event.motion.x, event.motion.y);
                },
                else => {},
            }
        }

        // Update sprite positions.
        for (sprites.items) |*s| {
            s.transform.position += s.velocity * @as(@Vector(2, f32), @splat(dt));
        }

        // Render.
        try rendering.beginFrame(renderer_ctx, .{ .x = 0.1, .y = 0.1, .z = 0.1, .w = 1.0 });

        for (sprites.items) |s| {
            try rendering.drawSprite(renderer_ctx, .{
                .transform = s.transform,
                .texture_handle = texture,
                .color = rendering.Color.WHITE,
            });
        }

        try rendering.render(renderer_ctx, .{ .x = 0.1, .y = 0.1, .z = 0.1, .w = 1.0 });
        try rendering.endFrame(renderer_ctx);
    }
}

fn spawnSprite(sprites: *std.ArrayList(SpriteData), rand: std.Random, mx: f32, my: f32) !void {
    const angle = rand.float(f32) * math.pi * 2.0;
    const velocity = @Vector(2, f32){ math.cos(angle) * MOVE_SPEED, math.sin(angle) * MOVE_SPEED };
    const position = @Vector(2, f32){ mx - SPRITE_W / 2.0, my - SPRITE_H / 2.0 };

    try sprites.append(.{
        .transform = .{ .position = position, .scale = @Vector(2, f32){ 1.0, 1.0 } },
        .velocity = velocity,
    });
} 