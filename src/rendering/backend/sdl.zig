const std = @import("std");
const ig = @import("cimgui");
const sdl = @import("sdl");
const RendererInterface = @import("../renderer.zig");
const resource = @import("../../core/resource.zig");
const sprite = @import("../../sprite/sprite.zig");

const BackendTexture = resource.BackendTexture;
const SpriteInstance = sprite.SpriteInstance;
const CircleInstance = sprite.CircleInstance;
const LineInstance = sprite.LineInstance;
const RectInstance = sprite.RectInstance;

pub const Context = struct {
    renderer: ?*sdl.c.SDL_Renderer,
    window: *sdl.c.SDL_Window,
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) RendererInterface.Error!*Context {
    const sdl_renderer_handle = sdl.c.SDL_CreateRenderer(window, null);
    if (sdl_renderer_handle == null) {
        std.log.err("SDL_CreateRenderer failed: {s}", .{sdl.c.SDL_GetError()});
        return RendererInterface.Error.InitializationFailed;
    }

    const ctx = try allocator.create(Context);
    errdefer allocator.destroy(ctx);

    std.log.info("Renderer pointer from SDL_CreateRenderer: {?p}", .{sdl_renderer_handle});
    ctx.* = Context{
        .renderer = sdl_renderer_handle,
        .window = window,
    };
    std.log.info("Stored Context.renderer: {?p}", .{ctx.renderer.?});

    std.log.info("SDL Renderer Initialized successfully", .{});
    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, context: *Context) void {
    std.log.info("Deinitializing SDL Renderer...", .{});

    if (context.renderer) |r| {
        sdl.c.SDL_DestroyRenderer(r);
        std.log.debug("SDL_DestroyRenderer called", .{});
    }

    allocator.destroy(context);
    std.log.info("Deinitialized SDL Renderer.", .{});
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) RendererInterface.Error!void {
    const r = ctx.renderer orelse return;

    _ = sdl.c.SDL_SetRenderDrawColor(
        r,
        @intFromFloat(clear_color.x * 255.0),
        @intFromFloat(clear_color.y * 255.0),
        @intFromFloat(clear_color.z * 255.0),
        @intFromFloat(clear_color.w * 255.0),
    );
    _ = sdl.c.SDL_RenderClear(r);
}

pub fn endFrame(_: *Context) RendererInterface.Error!void {}

pub fn initImGuiBackend(context: *Context) RendererInterface.Error!void {
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

pub fn deinitImGuiBackend() void {
    ig.ImGui_ImplSDLRenderer3_Shutdown();
}

pub fn newImGuiFrame() void {
    ig.ImGui_ImplSDLRenderer3_NewFrame();
}

pub fn renderImGui(
    draw_data: *ig.c.ImDrawData,
    renderer: *sdl.c.SDL_Renderer,
) void {
    ig.ImGui_ImplSDLRenderer3_RenderDrawData(draw_data, renderer);

    const sdl_error = sdl.c.SDL_GetError();
    if (sdl_error.* != 0) {
        std.log.err("SDL Error after ImGui_ImplSDLRenderer3_RenderDrawData: {s}", .{sdl_error});
    }
}

pub fn render(ctx: *Context, _: ig.c.ImVec4) void {
    const r = ctx.renderer orelse return;
    const draw_data = ig.igGetDrawData();
    if (draw_data) |data| {
        if (data.Valid and data.CmdListsCount > 0) {
            renderImGui(data, r);
        }
    }

    const result = sdl.c.SDL_RenderPresent(r);
    if (!result) {
        std.log.err("SDL_RenderPresent failed: {s}", .{sdl.c.SDL_GetError()});
    }
}

pub fn resize(_: *Context, width: i32, height: i32) RendererInterface.Error!void {
    std.log.info("SDL Renderer Resize event (width: {}, height: {}) - usually no-op", .{ width, height });
    return;
}

pub fn setVSync(context: *Context, enabled: bool) RendererInterface.Error!void {
    const r = context.renderer orelse {
        std.log.err("SDL_Renderer handle is null when attempting to set VSync.", .{});
        return RendererInterface.Error.InitializationFailed;
    };

    const vsync_value: c_int = if (enabled) 1 else 0;
    try sdl.errify(sdl.c.SDL_SetRenderVSync(r, vsync_value));
    std.log.info("SDL Renderer VSync set to: {}", .{enabled});
}

pub const Texture = *sdl.c.SDL_Texture;

pub fn loadTexture(ctx: *Context, path: []const u8) RendererInterface.Error!BackendTexture {
    const tex: Texture = try sdl.errify(sdl.c.IMG_LoadTexture(ctx.renderer.?, path.ptr));
    return BackendTexture{
        .texture = tex,
        .width = @intCast(tex.w),
        .height = @intCast(tex.h),
    };
}

pub fn destroyTexture(tex: Texture) void {
    sdl.c.SDL_DestroyTexture(tex);
}

pub fn renderSpriteInstances(
    ctx: *Context,
    backend_tex: BackendTexture,
    instances: []const SpriteInstance,
) RendererInterface.Error!void {
    if (instances.len == 0) return;

    const r = ctx.renderer orelse return RendererInterface.Error.InitializationFailed;

    const texture = backend_tex.texture;

    for (instances) |instance| {
        const pos_x = instance.transform[3]; // 4th column, 1st row (m03)
        const pos_y = instance.transform[7]; // 4th column, 2nd row (m13)

        const scale_x = @sqrt(instance.transform[0] * instance.transform[0] + instance.transform[4] * instance.transform[4]);
        const scale_y = @sqrt(instance.transform[1] * instance.transform[1] + instance.transform[5] * instance.transform[5]);

        const base_size = 32.0;
        const sdl_dst = sdl.c.SDL_FRect{
            .x = pos_x,
            .y = pos_y,
            .w = base_size * scale_x,
            .h = base_size * scale_y,
        };

        try sdl.errify(sdl.c.SDL_RenderTexture(r, texture, null, &sdl_dst));
    }
}

pub fn renderCircleInstances(
    ctx: *Context,
    instances: []const CircleInstance,
) RendererInterface.Error!void {
    _ = ctx;
    _ = instances;
    // TODO: Implement basic circle rendering with SDL_RenderFillCircle when available
    // For now, skip rendering circles as placeholder
}

pub fn renderLineInstances(
    ctx: *Context,
    instances: []const LineInstance,
) RendererInterface.Error!void {
    if (instances.len == 0) return;

    const r = ctx.renderer orelse return RendererInterface.Error.InitializationFailed;

    for (instances) |instance| {
        try sdl.errify(sdl.c.SDL_SetRenderDrawColor(
            r,
            @intFromFloat(instance.color[0] * 255.0),
            @intFromFloat(instance.color[1] * 255.0),
            @intFromFloat(instance.color[2] * 255.0),
            @intFromFloat(instance.color[3] * 255.0),
        ));

        try sdl.errify(sdl.c.SDL_RenderLine(
            r,
            instance.start[0],
            instance.start[1],
            instance.end[0],
            instance.end[1],
        ));
    }
}

pub fn renderRectInstances(
    ctx: *Context,
    instances: []const RectInstance,
) RendererInterface.Error!void {
    if (instances.len == 0) return;

    const r = ctx.renderer orelse return RendererInterface.Error.InitializationFailed;

    for (instances) |instance| {
        try sdl.errify(sdl.c.SDL_SetRenderDrawColor(
            r,
            @intFromFloat(instance.color[0] * 255.0),
            @intFromFloat(instance.color[1] * 255.0),
            @intFromFloat(instance.color[2] * 255.0),
            @intFromFloat(instance.color[3] * 255.0),
        ));

        const sdl_rect = sdl.c.SDL_FRect{
            .x = instance.position[0],
            .y = instance.position[1],
            .w = instance.size[0],
            .h = instance.size[1],
        };

        try sdl.errify(sdl.c.SDL_RenderFillRect(r, &sdl_rect));
    }
}
