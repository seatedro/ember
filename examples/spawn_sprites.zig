const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const ember = @import("../src/ember.zig");
const build_config = @import("../src/build_config.zig");
const math = std.math;

// ---------------------------------------------------------------------------
//                               Constants
// ---------------------------------------------------------------------------
const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;
const SPRITE_W = 32;
const SPRITE_H = 32;
const MOVE_SPEED = 50.0;
const SPRITES_PER_CLICK = 100;
const SPRITE_PATH = "assets/amogus.png";

const SpriteData = struct {
    transform: ember.Renderer.Transform2D,
    velocity: @Vector(2, f32),
};

pub const ember_systems = ember.Systems{
    .init = init,
    .draw = draw,
    .update = update,
    .quit = quit,
    .event = event,
};

pub const cfg = ember.Config{
    .fps_limit = .{ .capped = 60 },
    .window_size = .maximized,
    .title = "Sprite Stress Test",
};

const State = struct {
    tex: ember.Renderer.TextureHandle,
    rand: std.Random,
    sprites: std.ArrayList(SpriteData),
    left_down: bool = false,
};

var state: State = undefined;

pub fn init(ctx: *ember.Context) !void {
    state.tex = try ember.Renderer.loadTexture(&ctx.renderer_ctx, SPRITE_PATH);
    defer ember.Renderer.destroyTexture(&ctx.renderer_ctx, state.tex);

    const prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 1234;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    state.rand = prng.random();

    state.sprites = std.ArrayList(SpriteData).init(ctx.allocator);
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

pub fn update(ctx: *ember.Context) !void {
    // Update sprite positions.
    for (state.sprites.items) |*s| {
        s.transform.position += s.velocity * @as(@Vector(2, f32), @splat(ctx.dt));
    }
}

pub fn draw(ctx: *ember.Context) !void {
    for (state.sprites.items) |s| {
        try ember.Renderer.drawSprite(&ctx.renderer_ctx, .{
            .transform = s.transform,
            .texture_handle = state.tex,
            .color = ember.Renderer.Color.WHITE,
        });
    }
}

pub fn event(ctx: *ember.Context, e: ember.io.Event) !void {
    _ = ctx;
    return switch (e) {
        .mouse_button_down => |me| if (me.button == .left) {
            state.left_down = true;
            for (0..SPRITES_PER_CLICK) |_|
                try spawnSprite(&state.sprites, state.rand, event.button.x, event.button.y);
        },
        .mouse_button_up => |me| if (me.button == .left) {
            state.left_down = false;
        },
        .mouse_motion => |me| {
            for (0..SPRITES_PER_CLICK) |_|
                try spawnSprite(&state.sprites, state.rand, me.x, me.y);
        },
        else => {},
    };
}

pub fn quit(ctx: *ember.Context) !void {
    _ = ctx;
    state.sprites.deinit();
}
