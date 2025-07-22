const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const build_config = @import("../build_config.zig");

const buffer_vec = @import("buffer_vec.zig");
const resource_handles = @import("../core/resource.zig");
const TextureAtlas = @import("../core/atlas.zig").TextureAtlas;
const renderer = @import("renderer_2d.zig");
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

pub const TextureHandle = resource_handles.TextureHandle;
pub const AssetManager = resource_handles.AssetManager;
pub const Renderer2D = renderer.Renderer2D;
pub const Renderer2DConfig = renderer.Renderer2DConfig;
pub const Transform2D = renderer.Transform2D;
pub const SpriteDrawData = renderer.SpriteDrawData;
pub const Color = renderer.Color;
pub const DrawList = renderer.DrawList;

pub const Context = struct {
    allocator: std.mem.Allocator,
    backend_ctx: Backend.Context,
    asset_manager: AssetManager,
    renderer: Renderer2D,
    atlas: TextureAtlas,
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !Context {
    const r = try Renderer2D.init(allocator);
    const backend_ctx = try Backend.init(allocator, window);

    const atlas = try TextureAtlas.init(allocator, 4);

    return Context{
        .backend_ctx = backend_ctx,
        .renderer = r,
        .asset_manager = try AssetManager.init(allocator),
        .allocator = allocator,
        .atlas = atlas,
    };
}

pub fn deinit(ctx: *Context) void {
    Backend.deinit(&ctx.backend_ctx);
    ctx.renderer.deinit();
    ctx.asset_manager.deinit();
    ctx.atlas.deinit();
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    try Backend.beginFrame(&ctx.backend_ctx, clear_color);
    ctx.renderer.clearFrame();

    try Backend.syncAtlas(&ctx.backend_ctx, &ctx.atlas);
    ctx.renderer.dl.data.tex_uv_white_pixel = ctx.atlas.white_uv;
}

pub fn endFrame(ctx: *Context) Error!void {
    try Backend.endFrame(&ctx.backend_ctx);
}

pub fn initImGuiBackend(ctx: *Context) Error!void {
    try Backend.initImGuiBackend(&ctx.backend_ctx);
}

pub fn deinitImGuiBackend() void {
    Backend.deinitImGuiBackend();
}

pub fn newImGuiFrame() void {
    Backend.newImGuiFrame();
}

pub fn render(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    try Backend.render(&ctx.backend_ctx, clear_color, &ctx.renderer.dl);
}

pub fn resize(ctx: *Context, width: i32, height: i32) Error!void {
    try Backend.resize(&ctx.backend_ctx, width, height);
}

pub fn setVSync(ctx: *Context, enabled: bool) Error!void {
    try Backend.setVSync(&ctx.backend_ctx, enabled);
}

pub const Texture = Backend.Texture;

pub fn loadTexture(ctx: *Context, path: []const u8) !TextureHandle {
    const backend_texture = try Backend.loadTexture(&ctx.backend_ctx, path);
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
    try ctx.renderer.drawSprite(sprite_data);
}

pub fn drawCircle(ctx: *Context, center: @Vector(2, f32), radius: f32, color: @Vector(4, f32)) !void {
    try ctx.renderer.drawCircle(center, radius, color);
}

pub fn drawCircleFilled(ctx: *Context, center: @Vector(2, f32), radius: f32, color: @Vector(4, f32)) !void {
    try ctx.renderer.drawCircleFilled(center, radius, color);
}

pub fn drawLine(ctx: *Context, start: @Vector(2, f32), end: @Vector(2, f32), thickness: f32, color: @Vector(4, f32)) !void {
    try ctx.renderer.drawLine(start, end, thickness, color);
}

pub fn drawRect(ctx: *Context, position: @Vector(2, f32), size: @Vector(2, f32), color: @Vector(4, f32)) !void {
    try ctx.renderer.drawRect(position, size, color);
}
