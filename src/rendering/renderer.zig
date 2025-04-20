const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");

pub const BackendType = enum { SDL, OpenGL };

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

pub const Renderer = struct {
    /// Initializes the specific rendering backend.
    /// Takes the SDL window handle (as it's needed by many backends)
    /// and an allocator.
    /// Returns a pointer to the backend-specific context/state (`*anyopaque`).
    initFn: *const fn (window: *sdl.c.SDL_Window, allocator: std.mem.Allocator) Error!*anyopaque,

    /// Deinitializes the rendering backend and cleans up resources.
    /// Takes the backend-specific context and the allocator used for its creation.
    deinitFn: *const fn (context: *anyopaque, allocator: std.mem.Allocator) void,

    /// Called at the beginning of each frame. Typically clears the screen.
    beginFrameFn: *const fn (context: *anyopaque, clear_color: ig.c.ImVec4) Error!void,

    /// Called at the end of each frame. Presents the rendered image.
    endFrameFn: *const fn (context: *anyopaque) Error!void,

    /// Initializes ImGui backend
    initImGuiBackendFn: *const fn (context: *anyopaque) Error!void,

    /// Deinitializes ImGui backend
    deinitImGuiBackendFn: *const fn () void,

    /// ImGui Begin frame fn
    newImGuiFrameFn: *const fn () void,

    /// Renders Dear ImGui draw data using the specific backend.
    renderImGuiFn: *const fn (context: *anyopaque, draw_data: *ig.c.ImDrawData) void,

    /// Handles window resize events.
    resizeFn: *const fn (context: *anyopaque, width: i32, height: i32) Error!void,

    /// Set VSync
    setVSyncFn: *const fn (context: *anyopaque, enabled: bool) Error!void,

    /// Draw Texture
    drawTextureFn: *const fn (
        context: *anyopaque,
        texture: *sdl.c.SDL_Texture,
        src: ?*const sdl.c.SDL_FRect,
        dst: *const sdl.c.SDL_FRect,
    ) Error!void,
};

pub const RendererContext = struct {
    vtable: Renderer,
    context: *anyopaque,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RendererContext) void {
        self.vtable.deinitFn(self.context, self.allocator);
    }

    pub fn beginFrame(self: *RendererContext, clear_color: ig.c.ImVec4) Error!void {
        try self.vtable.beginFrameFn(self.context, clear_color);
    }

    pub fn endFrame(self: *RendererContext) Error!void {
        try self.vtable.endFrameFn(self.context);
    }

    pub fn initImGuiBackend(self: *RendererContext) Error!void {
        try self.vtable.initImGuiBackendFn(self.context);
    }

    pub fn deinitImGuiBackend(self: *RendererContext) void {
        self.vtable.deinitImGuiBackendFn();
    }

    pub fn newImGuiFrame(self: *RendererContext) void {
        self.vtable.newImGuiFrameFn();
    }

    pub fn renderImGui(self: *RendererContext, draw_data: *ig.c.ImDrawData) void {
        self.vtable.renderImGuiFn(self.context, draw_data);
    }

    pub fn resize(self: *RendererContext, width: i32, height: i32) Error!void {
        try self.vtable.resizeFn(self.context, width, height);
    }

    pub fn setVSync(self: *RendererContext, enabled: bool) Error!void { // Add this method
        try self.vtable.setVSyncFn(self.context, enabled);
    }

    pub fn drawTexture(
        self: *RendererContext,
        texture: *sdl.c.SDL_Texture,
        src: ?*const sdl.c.SDL_FRect,
        dst: *const sdl.c.SDL_FRect,
    ) Error!void {
        try self.vtable.drawTextureFn(self.context, texture, src, dst);
    }
};

// Forward declarations for renderer APIs
const sdl_renderer = @import("backend/sdl.zig");

pub fn createRenderer(
    backend_type: BackendType,
    window: *sdl.c.SDL_Window,
    allocator: std.mem.Allocator,
) Error!RendererContext {
    return switch (backend_type) {
        .SDL => {
            const ctx = try sdl_renderer.init(window, allocator);
            return RendererContext{
                .vtable = sdl_renderer.vtable,
                .context = ctx,
                .allocator = allocator,
            };
        },
        .OpenGL => {
            // TODO: Implement OpenGL backend initialization
            std.log.err("OpenGL backend not yet implemented", .{});
            return Error.UnsupportedBackend;
        },
    };
}
