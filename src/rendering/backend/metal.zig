const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const ig = @import("cimgui");
const objc = @import("objc");

const mtl = @import("metal/api.zig");

const log = std.log.scoped(.metal);

pub const Texture = struct {
    texture: objc.Object, // MTLTexture
    width: u32,
    height: u32,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    device: objc.Object, // MTLDevice
    command_queue: objc.Object, // MTLCommandQueue
    layer: objc.Object, // CAMetalLayer
    window: *sdl.c.SDL_Window,
    renderer: *sdl.c.SDL_Renderer,

    // Current frame state
    current_drawable: ?objc.Object = null,
    current_command_buffer: ?objc.Object = null,
    render_pass_descriptor: objc.Object,
    current_encoder: ?objc.Object = null,

    pipeline_state: ?objc.Object = null, // MTLRenderPipelineState
    vertex_buffer: ?objc.Object = null, // MTLBuffer

    // ImGui state
    imgui_initialized: bool = false,
};

fn chooseDevice() error{NoMetalDevice}!objc.Object {
    var chosen_device: ?objc.Object = null;

    switch (comptime builtin.os.tag) {
        .macos => {
            const devices = objc.Object.fromId(mtl.MTLCopyAllDevices());
            defer devices.release();

            var iter = devices.iterate();
            while (iter.next()) |device| {
                if (device.getProperty(bool, "isHeadless")) continue;
                chosen_device = device;
                if (device.getProperty(bool, "isRemovable") or
                    device.getProperty(bool, "isLowPower")) break;
            }
        },
        else => @compileError("unsupported target for Metal"),
    }

    const device = chosen_device orelse return error.NoMetalDevice;
    return device.retain();
}

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !*Context {
    // Without this SDL might bork
    _ = sdl.c.SDL_SetHint("SDL_RENDER_DRIVER", "metal");

    const renderer = sdl.c.SDL_CreateRenderer(window, null);
    if (renderer == null) {
        log.err("Failed to create SDL renderer: {s}", .{sdl.c.SDL_GetError()});
        return error.InitializationFailed;
    }

    const metal_layer_ptr = sdl.c.SDL_GetRenderMetalLayer(renderer);
    if (metal_layer_ptr == null) {
        log.err("Failed to get Metal layer from SDL renderer", .{});
        sdl.c.SDL_DestroyRenderer(renderer);
        return error.InitializationFailed;
    }

    const layer = objc.Object.fromId(@as(?*anyopaque, @ptrCast(metal_layer_ptr)));
    layer.setProperty("pixelFormat", @intFromEnum(mtl.MTLPixelFormat.bgra8unorm));

    // TODO: check if we reuse the device or choose our own
    const device = layer.msgSend(objc.Object, objc.sel("device"), .{});
    if (device.value == null) {
        log.err("Failed to get device from Metal layer", .{});
        sdl.c.SDL_DestroyRenderer(renderer);
        return error.InitializationFailed;
    }
    _ = device.retain(); // Retain since we're storing it

    const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    errdefer queue.release();

    const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor").?;
    const pass_descriptor = MTLRenderPassDescriptor.msgSend(objc.Object, objc.sel("new"), .{});
    _ = pass_descriptor.retain();
    errdefer pass_descriptor.release();

    var width: c_int = 0;
    var height: c_int = 0;
    _ = sdl.c.SDL_GetWindowSize(window, &width, &height);

    const size = .{
        .width = @as(f64, @floatFromInt(width)),
        .height = @as(f64, @floatFromInt(height)),
    };
    layer.setProperty("drawableSize", size);

    const ctx = try allocator.create(Context);
    ctx.* = .{
        .allocator = allocator,
        .device = device,
        .command_queue = queue,
        .layer = layer,
        .window = window,
        .renderer = renderer.?,
        .render_pass_descriptor = pass_descriptor,
    };

    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    if (ctx.imgui_initialized) {
        deinitImGuiBackend();
    }

    if (ctx.current_encoder) |encoder| encoder.release();
    if (ctx.current_command_buffer) |cb| cb.release();
    if (ctx.current_drawable) |drawable| drawable.release();
    ctx.render_pass_descriptor.release();

    if (ctx.pipeline_state) |ps| ps.release();
    if (ctx.vertex_buffer) |vb| vb.release();

    ctx.command_queue.release();
    ctx.device.release();

    sdl.c.SDL_DestroyRenderer(ctx.renderer);
    allocator.destroy(ctx);
}

pub fn beginFrame(ctx: *Context, clear_color: ig.c.ImVec4) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    _ = sdl.c.SDL_GetRenderOutputSize(ctx.renderer, &width, &height);

    const size = .{
        .width = @as(f64, @floatFromInt(width)),
        .height = @as(f64, @floatFromInt(height)),
    };
    ctx.layer.setProperty("drawableSize", size);

    const drawable = ctx.layer.msgSend(objc.Object, objc.sel("nextDrawable"), .{});
    if (drawable.value == null) {
        log.err("Failed to get drawable from Metal layer", .{});
        return;
    }
    ctx.current_drawable = drawable;

    const command_buffer = ctx.command_queue.msgSend(objc.Object, objc.sel("commandBuffer"), .{});
    if (command_buffer.value == null) {
        log.err("Failed to create Metal command buffer", .{});
        return;
    }
    ctx.current_command_buffer = command_buffer;

    const color_attachments = objc.Object.fromId(ctx.render_pass_descriptor.getProperty(?*anyopaque, "colorAttachments"));
    const color_attachment = color_attachments.msgSend(objc.Object, objc.sel("objectAtIndexedSubscript:"), .{@as(c_ulong, 0)});

    const texture = drawable.msgSend(objc.c.id, objc.sel("texture"), .{});
    color_attachment.setProperty("texture", texture);
    color_attachment.setProperty("loadAction", @intFromEnum(mtl.MTLLoadAction.clear));
    color_attachment.setProperty("storeAction", @intFromEnum(mtl.MTLStoreAction.store));

    const metal_clear_color = mtl.MTLClearColor{ .red = @as(f64, clear_color.x * clear_color.w), .green = @as(f64, clear_color.y * clear_color.w), .blue = @as(f64, clear_color.z * clear_color.w), .alpha = @as(f64, clear_color.w) };
    color_attachment.setProperty("clearColor", metal_clear_color);

    const encoder = command_buffer.msgSend(objc.Object, objc.sel("renderCommandEncoderWithDescriptor:"), .{ctx.render_pass_descriptor.value});
    if (encoder.value == null) {
        log.err("Failed to create Metal render command encoder", .{});
        return;
    }
    ctx.current_encoder = encoder;
}

pub fn endFrame(ctx: *Context) !void {
    const io = ig.c.igGetIO().?;
    if ((io.*.ConfigFlags & ig.c.ImGuiConfigFlags_ViewportsEnable) != 0) {
        ig.c.igUpdatePlatformWindows();
        ig.c.igRenderPlatformWindowsDefault();
    }

    if (ctx.current_encoder) |encoder| {
        encoder.msgSend(void, objc.sel("endEncoding"), .{});
        encoder.release();
        ctx.current_encoder = null;
    }

    if (ctx.current_command_buffer) |command_buffer| {
        if (ctx.current_drawable) |drawable| {
            command_buffer.msgSend(void, objc.sel("presentDrawable:"), .{drawable.value});
        }
        command_buffer.msgSend(void, objc.sel("commit"), .{});
        command_buffer.release();
        ctx.current_command_buffer = null;
    }

    if (ctx.current_drawable) |drawable| {
        drawable.release();
        ctx.current_drawable = null;
    }
}

pub fn initImGuiBackend(ctx: *Context) !void {
    if (!ig.ImGui_ImplMetal_Init(ctx.device.value)) {
        log.err("Failed to initialize ImGui Metal backend", .{});
        ig.ImGui_ImplSDL3_Shutdown();
        return error.InitializationFailed;
    }

    if (!ig.ImGui_ImplSDL3_InitForMetal(ctx.window)) {
        log.err("Failed to initialize ImGui SDL3 backend for Metal", .{});
        return error.InitializationFailed;
    }

    ctx.imgui_initialized = true;
    log.info("ImGui Metal backend initialized successfully with multi-viewport support", .{});
}

pub fn deinitImGuiBackend() void {
    ig.ImGui_ImplMetal_Shutdown();
    ig.ImGui_ImplSDL3_Shutdown();
}

pub fn newImGuiFrame(ctx: *Context) void {
    ig.ImGui_ImplMetal_NewFrame(ctx.render_pass_descriptor.value);
}

pub fn renderImGui(ctx: *Context, draw_data: *ig.c.ImDrawData) void {
    if (ctx.current_command_buffer) |command_buffer| {
        if (ctx.current_encoder) |encoder| {
            ig.ImGui_ImplMetal_RenderDrawData(draw_data, command_buffer.value, encoder.value);
        }
    }
}

pub fn resize(ctx: *Context, width: i32, height: i32) !void {
    const size = .{
        .width = @as(f64, @floatFromInt(width)),
        .height = @as(f64, @floatFromInt(height)),
    };
    ctx.layer.setProperty("drawableSize", size);
}

pub fn setVSync(ctx: *Context, enabled: bool) !void {
    ctx.layer.setProperty("displaySyncEnabled", enabled);
}

pub fn loadTexture(ctx: *Context, path: []const u8) !Texture {
    const surface = sdl.c.IMG_Load(path.ptr);
    if (surface == null) {
        log.err("Failed to load image: {s}", .{path});
        return error.InitializationFailed;
    }
    defer sdl.c.SDL_DestroySurface(surface);

    const MTLTextureDescriptor = objc.getClass("MTLTextureDescriptor").?;
    const desc = MTLTextureDescriptor.msgSend(objc.Object, objc.sel("new"), .{});
    defer desc.release();

    desc.setProperty("textureType", @as(c_ulong, 2)); // MTLTextureType2D
    desc.setProperty("pixelFormat", @intFromEnum(mtl.MTLPixelFormat.rgba8unorm));
    desc.setProperty("width", @as(c_ulong, @intCast(surface.*.w)));
    desc.setProperty("height", @as(c_ulong, @intCast(surface.*.h)));
    desc.setProperty("usage", @intFromEnum(mtl.MTLTextureUsage.shader_read));

    const texture = ctx.device.msgSend(objc.Object, objc.sel("newTextureWithDescriptor:"), .{desc.value});
    if (texture.value == null) {
        log.err("Failed to create Metal texture", .{});
        return error.InitializationFailed;
    }

    const bytes_per_row = @as(c_ulong, @intCast(surface.*.w * 4)); // Assuming RGBA
    const region = mtl.MTLRegion{
        .origin = mtl.MTLOrigin{ .x = 0, .y = 0, .z = 0 },
        .size = mtl.MTLSize{ .width = @as(c_ulong, @intCast(surface.*.w)), .height = @as(c_ulong, @intCast(surface.*.h)), .depth = 1 },
    };

    texture.msgSend(void, objc.sel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"), .{ region, @as(c_ulong, 0), surface.*.pixels, bytes_per_row });

    return Texture{
        .texture = texture,
        .width = @intCast(surface.*.w),
        .height = @intCast(surface.*.h),
    };
}

pub fn destroyTexture(tex: Texture) void {
    tex.texture.release();
}

pub fn drawTexture(
    ctx: *Context,
    texture: Texture,
    src: ?@import("../renderer.zig").Rect,
    dst: @import("../renderer.zig").Rect,
) !void {
    // TODO: Implement basic texture drawing using Metal render pipeline
    // This would require setting up a basic vertex/fragment shader pipeline
    // For now, this is a placeholder
    _ = ctx;
    _ = texture;
    _ = src;
    _ = dst;
}

pub fn drawTextureBatch(
    ctx: *Context,
    texture: Texture,
    src: ?@import("../renderer.zig").Rect,
    dst: []@import("../renderer.zig").Rect,
) !void {
    // For now, just draw each texture individually
    for (dst) |rect| {
        try drawTexture(ctx, texture, src, rect);
    }
}
