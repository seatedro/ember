const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");
const build_config = @import("build_config.zig");
const ember = @import("ember.zig");

const core = @import("core/types.zig");
const physics = @import("physics/verlet.zig");
const math = std.math;

const rendering = @import("rendering/renderer.zig");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;
const PARTICLES_PER_CLICK = 1;
const PARTICLE_SPAWN_INTERVAL: f32 = 0.05;
const PHYS_GRAVITY = core.Vec2{ 0.0, 1000.0 };
const PARTICLE_RADIUS = 10.0;

pub const ember_systems = ember.Systems{
    .init = init,
    .draw = draw,
    .update = update,
    .quit = quit,
    .event = event,
};

pub const cfg = ember.Config{
    .fps_limit = .{ .capped = 144 },
    .title = "verlet integration",
    .window_size = .maximized,
};

var world: ember.World = undefined;
var prng: std.Random.Xoshiro256 = undefined;
var rand: std.Random = undefined;
var left_down: bool = false;
var space_held: bool = false;
var particle_spawn_timer: f32 = 0.0;
var boundary_center: core.Vec2 = undefined;
var boundary_radius: f32 = 0.0;

pub fn init(ctx: *ember.Context) !void {
    world = try physics.World.init(ctx.allocator, PHYS_GRAVITY);
    defer world.deinit();

    prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 0;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
            std.log.warn("Failed to get random seed: {}, using default", .{err});
            seed = @as(u64, @intCast(std.time.timestamp()));
        };
        break :blk seed;
    });
    rand = prng.random();

    const win_size = try ctx.window.getWindowSize();

    boundary_center = core.Vec2{
        @as(f32, @floatFromInt(win_size.width)) / 2.0,
        @as(f32, @floatFromInt(win_size.height)) / 2.0,
    };
    boundary_radius = @min(
        @as(f32, @floatFromInt(win_size.width)),
        @as(f32, @floatFromInt(win_size.height)),
    ) / 2.0 - 20.0;
    world.setBoundaryCircle(boundary_center, boundary_radius, 2);
}

pub fn update(ctx: *ember.Context) !void {
    if (space_held) {
        particle_spawn_timer += ctx.dt;
        while (particle_spawn_timer >= PARTICLE_SPAWN_INTERVAL) {
            particle_spawn_timer -= PARTICLE_SPAWN_INTERVAL;

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

    world.step(ctx.dt);

    if (ctx.window.isMinimized()) {
        sdl.c.SDL_Delay(10);
    }
}

pub fn draw(ctx: *ember.Context) !void {
    {
        if (cimgui.c.igBegin("Ember Debug Console", null, 0)) {
            cimgui.c.igText("Particles: %d", @as(c_int, @intCast(world.len())));
            cimgui.c.igText(
                "Perf: %.3f ms/frame (%.1f FPS)",
                1000.0 / ctx.fps,
                ctx.fps,
            );
            cimgui.c.igText("Ember: A silly little game engine");
        }
        cimgui.c.igEnd();
    }
    for (world.particles.items) |p| {
        try rendering.drawCircleFilled(&ctx.renderer_ctx, p.position, PARTICLE_RADIUS, p.color);
    }
    try rendering.drawCircle(&ctx.renderer_ctx, boundary_center, boundary_radius, rendering.Color.WHITE);
}
pub fn quit(ctx: *ember.Context) !void {
    _ = ctx;
    world.deinit();
}
pub fn event(ctx: *ember.Context, e: ember.io.Event) !void {
    _ = ctx;
    switch (e) {
        .mouse_button_down => |me| if (me.button == .left) {
            left_down = true;
            for (0..PARTICLES_PER_CLICK) |_| {
                const color = @Vector(4, f32){
                    rand.float(f32), // Red
                    rand.float(f32), // Green
                    rand.float(f32), // Blue
                    1.0, // Alpha
                };
                try world.addParticle(
                    core.Vec2{ me.x, me.y },
                    PARTICLE_RADIUS,
                    color,
                );
            }
        },
        .mouse_button_up => |me| if (me.button == .left) {
            left_down = false;
        },
        .key_down => |ke| if (ke.keycode == .space) {
            space_held = true;
        },
        .key_up => |ke| if (ke.keycode == .space) {
            space_held = false;
            particle_spawn_timer = 0.0;
        },
        else => {},
    }
}
