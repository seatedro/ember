const std = @import("std");
const ig = @import("cimgui");
const sdl = @import("sdl");
const RendererInterface = @import("../renderer.zig");

const SdlContext = struct {
    renderer: ?*sdl.c.SDL_Renderer,
    window: *sdl.c.SDL_Window,
};

fn sdlInit(window: *sdl.c.SDL_Window, allocator: std.mem.Allocator) RendererInterface.Error!*anyopaque {
    const sdl_renderer_handle = sdl.c.SDL_CreateRenderer(window, null);
    if (sdl_renderer_handle == null) {
        std.log.err("SDL_CreateRenderer failed: {s}", .{sdl.c.SDL_GetError()});
        return RendererInterface.Error.InitializationFailed;
    }

    const ctx = try allocator.create(SdlContext);
    errdefer allocator.destroy(ctx);

    std.log.info("Renderer pointer from SDL_CreateRenderer: {?p}", .{sdl_renderer_handle});
    ctx.* = SdlContext{
        .renderer = sdl_renderer_handle,
        .window = window,
    };
    std.log.info("Stored SdlContext.renderer: {?p}", .{ctx.renderer.?});

    std.log.info("SDL Renderer Initialized successfully", .{});
    return @ptrCast(ctx);
}

fn sdlDeinit(context_opaque: *anyopaque, allocator: std.mem.Allocator) void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));
    std.log.info("Deinitializing SDL Renderer...", .{});

    if (context.renderer) |r| {
        sdl.c.SDL_DestroyRenderer(r);
        std.log.debug("SDL_DestroyRenderer called", .{});
    }

    allocator.destroy(context);
    std.log.info("SDL Renderer Deinitialized.", .{});
}

fn sdlBeginFrame(context_opaque: *anyopaque, clear_color: ig.c.ImVec4) RendererInterface.Error!void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));
    const r = context.renderer;

    try sdl.errify(sdl.c.SDL_SetRenderDrawColor(
        r,
        @intFromFloat(clear_color.x * 255.0),
        @intFromFloat(clear_color.y * 255.0),
        @intFromFloat(clear_color.z * 255.0),
        @intFromFloat(clear_color.w * 255.0),
    ));

    try sdl.errify(sdl.c.SDL_RenderClear(r));
}

fn sdlEndFrame(context_opaque: *anyopaque) RendererInterface.Error!void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));

    // Note: SDL_RenderPresent is implicitly called by ImGui's platform window handling
    // when viewports are enabled. However, for the main window or when viewports are off,
    // we might need it here. ImGui's SDL backend handles this. Let's keep it simple for now.
    // If issues arise with the main window not updating, uncommenting SDL_RenderPresent might be needed,
    // but usually ImGui handles the present for its windows.
    // For now, ImGui_ImplSDLRenderer3_RenderDrawData handles drawing, and the platform backend handles present.
    // try sdl.errify(sdl.c.SDL_RenderPresent(context.renderer));
    const result = sdl.c.SDL_RenderPresent(context.renderer);
    if (!result) {
        std.log.err("SDL_RenderPresent failed: {s}", .{sdl.c.SDL_GetError()});
        return RendererInterface.Error.EndFrameFailed; // Or a more specific error
    }
}

fn sdlInitImGuiBackend(context_opaque: *anyopaque) RendererInterface.Error!void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));
    const r = context.renderer;

    if (!ig.ImGui_ImplSDL3_InitForSDLRenderer(context.window, r)) {
        std.log.err("ImGui_ImplSDL3_InitForSDLRenderer failed", .{});
        return RendererInterface.Error.InitializationFailed;
    }

    // Initialize ImGui SDL Renderer Backend
    // Note: This binds ImGui's rendering calls specifically to SDL_Renderer
    if (!ig.ImGui_ImplSDLRenderer3_Init(r)) {
        std.log.err("ImGui_ImplSDLRenderer3_Init failed", .{});
        // Cleanup already created SDL renderer
        sdl.c.SDL_DestroyRenderer(r);
        return RendererInterface.Error.InitializationFailed;
    }

    std.log.info("ImGui SDL Renderer Backend Initialized.", .{});
}

fn sdlDeinitImGuiBackend() void {
    ig.ImGui_ImplSDLRenderer3_Shutdown();
}

fn sdlNewImGuiFrame() void {
    ig.ImGui_ImplSDLRenderer3_NewFrame();
}

fn sdlRenderImGui(
    context_opaque: *anyopaque,
    draw_data: *ig.c.ImDrawData,
) void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));

    ig.ImGui_ImplSDLRenderer3_RenderDrawData(draw_data, context.renderer);

    // **** Check for SDL errors IMMEDIATELY after the call ****
    const sdl_error = sdl.c.SDL_GetError();
    if (sdl_error.* != 0) { // Check if the error string pointer is not null/empty
        std.log.err("SDL Error *after* ImGui_ImplSDLRenderer3_RenderDrawData: {s}", .{sdl_error});
        // You might want to return an error here, e.g.:
        // return RendererInterface.Error.RenderImGuiFailed;
    } else {
        std.log.debug("No SDL error reported after ImGui_ImplSDLRenderer3_RenderDrawData.", .{});
    }
}

fn sdlResize(context_opaque: *anyopaque, width: i32, height: i32) RendererInterface.Error!void {
    // SDL_Renderer usually handles resizing automatically with the window.
    // We might need viewport adjustments if not using ImGui viewports,
    // but for now, this can often be a no-op for basic SDL_Renderer.
    _ = context_opaque;
    std.log.info("SDL Renderer Resize event (width: {}, height: {}) - usually no-op", .{ width, height });
    return;
}

fn sdlSetVSync(context_opaque: *anyopaque, enabled: bool) RendererInterface.Error!void {
    const context: *SdlContext = @ptrCast(@alignCast(context_opaque));
    const r = context.renderer orelse {
        std.log.err("SDL_Renderer handle is null when attempting to set VSync.", .{});
        return RendererInterface.Error.InitializationFailed; // Or VSyncFailed
    };

    const vsync_value: c_int = if (enabled) 1 else 0;
    try sdl.errify(sdl.c.SDL_SetRenderVSync(r, vsync_value));
    std.log.info("SDL Renderer VSync set to: {}", .{enabled});
}

// --- VTable Definition ---
pub const vtable = RendererInterface.Renderer{
    .initFn = sdlInit,
    .deinitFn = sdlDeinit,
    .beginFrameFn = sdlBeginFrame,
    .endFrameFn = sdlEndFrame,
    .initImGuiBackendFn = sdlInitImGuiBackend,
    .deinitImGuiBackendFn = sdlDeinitImGuiBackend,
    .newImGuiFrameFn = sdlNewImGuiFrame,
    .renderImGuiFn = sdlRenderImGui,
    .resizeFn = sdlResize,
    .setVSyncFn = sdlSetVSync,
};

pub const init = sdlInit;
