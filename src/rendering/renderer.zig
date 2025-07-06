const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const build_config = @import("../build_config.zig");

const buffer_vec = @import("buffer_vec.zig");
const resource_handles = @import("../core/resource.zig");
const renderer_2d = @import("renderer_2d.zig");
const errors = @import("errors.zig");

pub const BackendType = enum {
    SDL,
    OpenGL,
    WGPU,

    pub fn default(
        _: std.Target,
    ) BackendType {
        return .WGPU;
    }
};

pub const Error = errors.RenderError;

pub const Backend = switch (build_config.renderer) {
    .SDL => @import("backend/sdl.zig"),
    .OpenGL => @import("backend/opengl.zig"),
    .WGPU => @import("backend/wgpu.zig"),
};

pub const BufferVec = buffer_vec.BufferVec;
pub const SpriteInstance = buffer_vec.SpriteInstance;
pub const TextureHandle = resource_handles.TextureHandle;
pub const AssetManager = resource_handles.AssetManager;
pub const Renderer2D = renderer_2d.Renderer2D;
pub const Renderer2DConfig = renderer_2d.Renderer2DConfig;
pub const Transform2D = renderer_2d.Transform2D;
pub const SpriteDrawData = renderer_2d.SpriteDrawData;
pub const Color = renderer_2d.Color;

pub const Context = struct {
    allocator: std.mem.Allocator,
    backend_ctx: *Backend.Context,
    asset_manager: AssetManager,
    renderer_2d: Renderer2D,
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !*Context {
    const backend_ctx = try Backend.init(allocator, window);

    const renderer_2d_config = Renderer2DConfig{
        .initial_sprite_capacity = 10000, // Pre-allocate for 10K sprites
        .initial_shape_capacity = 2000, // Pre-allocate for 2K shapes
        .initial_batch_capacity = 128, // Pre-allocate for 128 draw batches
    };

    const ctx = try allocator.create(Context);
    ctx.* = Context{
        .backend_ctx = backend_ctx,
        .renderer_2d = try Renderer2D.init(allocator, renderer_2d_config),
        .asset_manager = try AssetManager.init(allocator),
        .allocator = allocator,
    };

    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    Backend.deinit(allocator, ctx.backend_ctx);
    ctx.renderer_2d.deinit();
    ctx.asset_manager.deinit();
    allocator.destroy(ctx);
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    try Backend.beginFrame(ctx.backend_ctx, clear_color);
    ctx.renderer_2d.clearFrame();
}

pub fn endFrame(ctx: *Context) Error!void {
    try Backend.endFrame(ctx.backend_ctx);
}

fn renderBatches(ctx: *Context) !void {
    const batches = ctx.renderer_2d.getBatches();

    for (batches) |batch| {
        switch (batch.batch_type) {
            .Sprites => {
                const instances = ctx.renderer_2d.getSpriteInstances();
                const batch_instances = instances[batch.start_index .. batch.start_index + batch.count];

                if (ctx.asset_manager.getTexture(batch.texture_handle)) |texture| {
                    try Backend.renderSpriteInstances(ctx.backend_ctx, texture.backend_data, batch_instances);
                }
            },
            .Circles => {
                const instances = ctx.renderer_2d.getCircleInstances();
                const batch_instances = instances[batch.start_index .. batch.start_index + batch.count];
                try Backend.renderCircleInstances(ctx.backend_ctx, batch_instances);
            },
            .Lines => {
                const instances = ctx.renderer_2d.getLineInstances();
                const batch_instances = instances[batch.start_index .. batch.start_index + batch.count];
                try Backend.renderLineInstances(ctx.backend_ctx, batch_instances);
            },
            .Rectangles => {
                const instances = ctx.renderer_2d.getRectInstances();
                const batch_instances = instances[batch.start_index .. batch.start_index + batch.count];
                try Backend.renderRectInstances(ctx.backend_ctx, batch_instances);
            },
        }
    }
}

pub fn initImGuiBackend(ctx: *Context) Error!void {
    try Backend.initImGuiBackend(ctx.backend_ctx);
}

pub fn deinitImGuiBackend() void {
    Backend.deinitImGuiBackend();
}

pub fn newImGuiFrame() void {
    Backend.newImGuiFrame();
}

pub fn render(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    try ctx.renderer_2d.generateBatches();
    try renderBatches(ctx);
    Backend.render(ctx.backend_ctx, clear_color);
}

pub fn resize(ctx: *Context, width: i32, height: i32) Error!void {
    try Backend.resize(ctx.backend_ctx, width, height);
}

pub fn setVSync(ctx: *Context, enabled: bool) Error!void {
    try Backend.setVSync(ctx.backend_ctx, enabled);
}

pub const Texture = Backend.Texture;

pub fn loadTexture(ctx: *Context, path: []const u8) !TextureHandle {
    const backend_texture = try Backend.loadTexture(ctx.backend_ctx, path);
    return try ctx.asset_manager.loadTexture(path, backend_texture);
}

pub fn destroyTexture(ctx: *Context, handle: TextureHandle) void {
    // Only destroy if handle is valid and texture exists
    if (handle.isValid()) {
        if (ctx.asset_manager.getTexture(handle)) |texture| {
            Backend.destroyTexture(texture.backend_data.texture);
            ctx.asset_manager.destroyTexture(handle);
        }
    }
}

pub fn drawSprite(ctx: *Context, sprite_data: SpriteDrawData) !void {
    try ctx.renderer_2d.drawSprite(sprite_data);
}

pub fn drawCircle(ctx: *Context, center: @Vector(2, f32), radius: f32, color: @Vector(4, f32)) !void {
    try ctx.renderer_2d.drawCircle(center, radius, color);
}

pub fn drawLine(ctx: *Context, start: @Vector(2, f32), end: @Vector(2, f32), thickness: f32, color: @Vector(4, f32)) !void {
    try ctx.renderer_2d.drawLine(start, end, thickness, color);
}

pub fn drawRect(ctx: *Context, position: @Vector(2, f32), size: @Vector(2, f32), color: @Vector(4, f32)) !void {
    try ctx.renderer_2d.drawRect(position, size, color);
}
