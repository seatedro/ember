const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const build_config = @import("../build_config.zig");

pub const BackendType = enum {
    SDL,
    OpenGL,
    Metal,

    pub fn default(
        _: std.Target,
    ) BackendType {
        // TODO: Uncomment this once we add metal as a backend
        // if (target.os.tag.isDarwin()) return .Metal;
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
    .OpenGL => unreachable,
    .Metal => unreachable,
};
pub const Context = Backend.Context;

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !*Context {
    const ctx = try Backend.init(window, allocator);
    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    Backend.deinit(ctx, allocator);
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) Error!void {
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

pub fn newImGuiFrame() void {
    Backend.newImGuiFrame();
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

pub fn drawTexture(
    ctx: *Context,
    texture: *sdl.c.SDL_Texture,
    src: ?*const sdl.c.SDL_FRect,
    dst: *const sdl.c.SDL_FRect,
) Error!void {
    try Backend.drawTexture(ctx, texture, src, dst);
}
