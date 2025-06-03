const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const build_config = @import("../build_config.zig");

pub const BackendType = enum {
    SDL,
    OpenGL,
    Metal,

    pub fn default(
        target: std.Target,
    ) BackendType {
        if (target.os.tag.isDarwin()) return .Metal;
        return .SDL;
    }
};

pub const Error = error{
    InitializationFailed,
    BeginFrameFailed,
    EndFrameFailed,
    RenderImGuiFailed,
    ResizeFailed,
    UnsupportedBackend,
    SdlError,
    VSyncFailed,
    OutOfMemory,
};

pub const Backend = switch (build_config.renderer) {
    .SDL => @import("backend/sdl.zig"),
    .OpenGL => @import("backend/opengl.zig"),
    .Metal => @import("backend/metal.zig"),
};
pub const Context = Backend.Context;

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !*Context {
    const ctx = try Backend.init(allocator, window);
    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    Backend.deinit(allocator, ctx);
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    try Backend.beginFrame(ctx, clear_color);
}

pub fn endFrame(ctx: *Context) Error!void {
    try Backend.endFrame(ctx);
}

pub fn initImGuiBackend(ctx: *Context) Error!void {
    try Backend.initImGuiBackend(ctx);
}

pub fn deinitImGuiBackend() void {
    Backend.deinitImGuiBackend();
}

pub fn newImGuiFrame(ctx: *Context) void {
    Backend.newImGuiFrame(ctx);
}

pub fn renderImGui(ctx: *Context, draw_data: *ig.c.ImDrawData) void {
    Backend.renderImGui(ctx, draw_data);
}

pub fn resize(ctx: *Context, width: i32, height: i32) Error!void {
    try Backend.resize(ctx, width, height);
}

pub fn setVSync(ctx: *Context, enabled: bool) Error!void { // Add this method
    try Backend.setVSync(ctx, enabled);
}

pub const Texture = Backend.Texture;
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

pub fn loadTexture(ctx: *Context, path: []const u8) !Texture {
    return Backend.loadTexture(ctx, path);
}

pub fn destroyTexture(tex: Texture) void {
    Backend.destroyTexture(tex);
}

pub fn drawTexture(
    ctx: *Context,
    texture: Texture,
    src: ?Rect,
    dst: Rect,
) !void {
    try Backend.drawTexture(ctx, texture, src, dst);
}

pub fn drawTextureBatch(
    ctx: *Context,
    texture: Texture,
    src: ?Rect,
    dst: []Rect,
) !void {
    try Backend.drawTextureBatch(ctx, texture, src, dst);
}
