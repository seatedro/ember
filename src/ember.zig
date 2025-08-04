pub const Config = @import("core/config.zig").Config;
pub const Context = @import("core/internal.zig").Context;
pub const types = @import("core/types.zig");
pub const io = @import("core/io.zig");

pub const BackendType = @import("rendering/renderer.zig").BackendType;
pub const Renderer = @import("rendering/renderer.zig");
pub const RendererCtx = Renderer.Context;
pub const Renderer2D = @import("rendering/renderer.zig").Renderer2D;

pub const World = @import("physics/verlet.zig").World;
pub const Particle = @import("physics/verlet.zig").Particle;

const InitFn = fn (ctx: *Context) anyerror!void;
const UpdateFn = fn (ctx: *Context) anyerror!void;
const DrawFn = fn (ctx: *Context) anyerror!void;
const QuitFn = fn (ctx: *Context) anyerror!void;
const EventFn = fn (ctx: *Context, e: io.Event) anyerror!void;
pub const Systems = struct {
    init: InitFn,
    update: UpdateFn,
    draw: DrawFn,
    quit: QuitFn,
    event: EventFn,
};

pub const CLEAR_COLOR = ig.c.ImVec4{ .x = 0.01, .y = 0.01, .z = 0.01, .w = 1.00 };

// Vendor
pub const sdl = @import("sdl");
pub const ig = @import("cimgui");
