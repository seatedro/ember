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

// Vertex structure for texture rendering
const TextureVertex = struct {
    position: [2]f32,
    texCoord: [2]f32,
};

// Uniforms structure for texture rendering
const TextureUniforms = struct {
    projectionMatrix: [16]f32,
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

    // Texture rendering support
    texture_library: ?objc.Object = null, // MTLLibrary for texture shaders
    texture_pipeline_state: ?objc.Object = null, // MTLRenderPipelineState for textures
    texture_vertex_buffer: ?objc.Object = null, // MTLBuffer for texture vertices
    texture_uniform_buffer: ?objc.Object = null, // MTLBuffer for uniforms
    texture_sampler: ?objc.Object = null, // MTLSamplerState

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

    // Initialize texture rendering components
    try initTextureRendering(ctx);

    return ctx;
}

fn initTextureRendering(ctx: *Context) !void {
    // Load the compiled texture shader library
    const texture_lib_data = @embedFile("metal/compiled/texture_shaders.metallib");
    const data = objc.Object.fromId(
        @as(*anyopaque, @ptrCast(objc.c.objc_msgSend(
            objc.getClass("NSData").?.value,
            objc.sel("dataWithBytes:length:"),
            texture_lib_data.ptr,
            texture_lib_data.len,
        ))),
    );

    var err: ?*anyopaque = null;
    const texture_library = ctx.device.msgSend(
        objc.Object,
        objc.sel("newLibraryWithData:error:"),
        .{ data.value, &err },
    );
    if (err != null) {
        log.err("Failed to create texture shader library", .{});
        return error.InitializationFailed;
    }
    ctx.texture_library = texture_library;

    // Create texture pipeline state
    try createTexturePipeline(ctx);

    // Create texture vertex buffer (for a quad)
    try createTextureVertexBuffer(ctx);

    // Create uniform buffer
    try createTextureUniformBuffer(ctx);

    // Create sampler state
    try createTextureSampler(ctx);
}

fn createTexturePipeline(ctx: *Context) !void {
    const texture_library = ctx.texture_library.?;

    // Get vertex and fragment functions
    const vertex_func_name = objc.Object.fromId(
        @as(*anyopaque, @ptrCast(objc.c.objc_msgSend(
            objc.getClass("NSString").?.value,
            objc.sel("stringWithUTF8String:"),
            "texture_vertex",
        ))),
    );
    defer vertex_func_name.release();

    const fragment_func_name = objc.Object.fromId(
        @as(*anyopaque, @ptrCast(objc.c.objc_msgSend(
            objc.getClass("NSString").?.value,
            objc.sel("stringWithUTF8String:"),
            "texture_fragment",
        ))),
    );
    defer fragment_func_name.release();

    const vertex_func = texture_library.msgSend(objc.Object, objc.sel("newFunctionWithName:"), .{vertex_func_name.value});
    const fragment_func = texture_library.msgSend(objc.Object, objc.sel("newFunctionWithName:"), .{fragment_func_name.value});

    if (vertex_func.value == null or fragment_func.value == null) {
        log.err("Failed to load texture shader functions", .{});
        return error.InitializationFailed;
    }
    defer vertex_func.release();
    defer fragment_func.release();

    // Create vertex descriptor
    const vertex_desc = objc.Object.fromId(
        objc.c.objc_msgSend(objc.getClass("MTLVertexDescriptor").?.value, objc.sel("vertexDescriptor"), .{}),
    );
    defer vertex_desc.release();

    const attributes = objc.Object.fromId(vertex_desc.getProperty(?*anyopaque, "attributes"));
    const layouts = objc.Object.fromId(vertex_desc.getProperty(?*anyopaque, "layouts"));

    // Position attribute (0)
    const pos_attr = attributes.msgSend(objc.Object, objc.sel("objectAtIndexedSubscript:"), .{@as(c_ulong, 0)});
    pos_attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
    pos_attr.setProperty("offset", @as(c_ulong, 0));
    pos_attr.setProperty("bufferIndex", @as(c_ulong, 0));

    // Texture coordinate attribute (1)
    const tex_attr = attributes.msgSend(objc.Object, objc.sel("objectAtIndexedSubscript:"), .{@as(c_ulong, 1)});
    tex_attr.setProperty("format", @intFromEnum(mtl.MTLVertexFormat.float2));
    tex_attr.setProperty("offset", @as(c_ulong, @offsetOf(TextureVertex, "texCoord")));
    tex_attr.setProperty("bufferIndex", @as(c_ulong, 0));

    // Layout
    const layout = layouts.msgSend(objc.Object, objc.sel("objectAtIndexedSubscript:"), .{@as(c_ulong, 0)});
    layout.setProperty("stride", @as(c_ulong, @sizeOf(TextureVertex)));
    layout.setProperty("stepFunction", @intFromEnum(mtl.MTLVertexStepFunction.per_vertex));

    // Create pipeline descriptor
    const pipeline_desc = objc.Object.fromId(
        objc.c.objc_msgSend(objc.getClass("MTLRenderPipelineDescriptor").?.value, objc.sel("new"), .{}),
    );
    defer pipeline_desc.release();

    pipeline_desc.setProperty("vertexFunction", vertex_func.value);
    pipeline_desc.setProperty("fragmentFunction", fragment_func.value);
    pipeline_desc.setProperty("vertexDescriptor", vertex_desc.value);

    // Color attachment
    const color_attachments = objc.Object.fromId(pipeline_desc.getProperty(?*anyopaque, "colorAttachments"));
    const color_attachment = color_attachments.msgSend(objc.Object, objc.sel("objectAtIndexedSubscript:"), .{@as(c_ulong, 0)});
    color_attachment.setProperty("pixelFormat", @intFromEnum(mtl.MTLPixelFormat.bgra8unorm));

    // Enable blending
    color_attachment.setProperty("blendingEnabled", true);
    color_attachment.setProperty("rgbBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
    color_attachment.setProperty("alphaBlendOperation", @intFromEnum(mtl.MTLBlendOperation.add));
    color_attachment.setProperty("sourceRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.source_alpha));
    color_attachment.setProperty("sourceAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.source_alpha));
    color_attachment.setProperty("destinationRGBBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));
    color_attachment.setProperty("destinationAlphaBlendFactor", @intFromEnum(mtl.MTLBlendFactor.one_minus_source_alpha));

    // Create pipeline state
    var pipeline_err: ?*anyopaque = null;
    const pipeline_state = ctx.device.msgSend(
        objc.Object,
        objc.sel("newRenderPipelineStateWithDescriptor:error:"),
        .{ pipeline_desc.value, &pipeline_err },
    );
    if (pipeline_err != null) {
        log.err("Failed to create texture pipeline state", .{});
        return error.InitializationFailed;
    }

    ctx.texture_pipeline_state = pipeline_state;
}

fn createTextureVertexBuffer(ctx: *Context) !void {
    const buffer_size = @sizeOf(TextureVertex) * 6; // 6 vertices for 2 triangles (quad)

    const vertex_buffer = ctx.device.msgSend(
        objc.Object,
        objc.sel("newBufferWithLength:options:"),
        .{ @as(c_ulong, buffer_size), @intFromEnum(mtl.MTLResourceOptions.storage_mode_shared) },
    );

    if (vertex_buffer.value == null) {
        log.err("Failed to create texture vertex buffer", .{});
        return error.InitializationFailed;
    }

    ctx.texture_vertex_buffer = vertex_buffer;
}

fn createTextureUniformBuffer(ctx: *Context) !void {
    const uniform_buffer = ctx.device.msgSend(
        objc.Object,
        objc.sel("newBufferWithLength:options:"),
        .{ @as(c_ulong, @sizeOf(TextureUniforms)), @intFromEnum(mtl.MTLResourceOptions.storage_mode_shared) },
    );

    if (uniform_buffer.value == null) {
        log.err("Failed to create texture uniform buffer", .{});
        return error.InitializationFailed;
    }

    ctx.texture_uniform_buffer = uniform_buffer;
}

fn createTextureSampler(ctx: *Context) !void {
    const sampler_desc = objc.Object.fromId(
        objc.c.objc_msgSend(objc.getClass("MTLSamplerDescriptor").?.value, objc.sel("new"), .{}),
    );
    defer sampler_desc.release();

    sampler_desc.setProperty("minFilter", @intFromEnum(mtl.MTLSamplerMinMagFilter.linear));
    sampler_desc.setProperty("magFilter", @intFromEnum(mtl.MTLSamplerMinMagFilter.linear));
    sampler_desc.setProperty("sAddressMode", @intFromEnum(mtl.MTLSamplerAddressMode.clamp_to_edge));
    sampler_desc.setProperty("tAddressMode", @intFromEnum(mtl.MTLSamplerAddressMode.clamp_to_edge));

    const sampler = ctx.device.msgSend(objc.Object, objc.sel("newSamplerStateWithDescriptor:"), .{sampler_desc.value});
    if (sampler.value == null) {
        log.err("Failed to create texture sampler", .{});
        return error.InitializationFailed;
    }

    ctx.texture_sampler = sampler;
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

    // Clean up texture rendering resources
    if (ctx.texture_library) |lib| lib.release();
    if (ctx.texture_pipeline_state) |ps| ps.release();
    if (ctx.texture_vertex_buffer) |vb| vb.release();
    if (ctx.texture_uniform_buffer) |ub| ub.release();
    if (ctx.texture_sampler) |sampler| sampler.release();

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
    const encoder = ctx.current_encoder orelse {
        log.err("No current render encoder for texture drawing", .{});
        return error.InitializationFailed;
    };

    // Get window dimensions for projection matrix
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = sdl.c.SDL_GetWindowSize(ctx.window, &window_width, &window_height);

    const w = @as(f32, @floatFromInt(window_width));
    const h = @as(f32, @floatFromInt(window_height));

    // Create orthographic projection matrix
    const projection_matrix = [16]f32{
        2.0 / w, 0.0,      0.0, 0.0,
        0.0,     -2.0 / h, 0.0, 0.0,
        0.0,     0.0,      1.0, 0.0,
        -1.0,    1.0,      0.0, 1.0,
    };

    // Update uniform buffer
    const uniform_buffer = ctx.texture_uniform_buffer.?;
    const uniform_contents = uniform_buffer.msgSend(?*anyopaque, objc.sel("contents"), .{}).?;
    const uniforms = @as(*TextureUniforms, @ptrCast(@alignCast(uniform_contents)));
    uniforms.projectionMatrix = projection_matrix;

    // Calculate vertex positions and texture coordinates
    const x1 = dst.x;
    const y1 = dst.y;
    const x2 = dst.x + dst.w;
    const y2 = dst.y + dst.h;

    var tex_u1: f32 = 0.0;
    var tex_v1: f32 = 0.0;
    var tex_u2: f32 = 1.0;
    var tex_v2: f32 = 1.0;

    if (src) |src_rect| {
        tex_u1 = src_rect.x / @as(f32, @floatFromInt(texture.width));
        tex_v1 = src_rect.y / @as(f32, @floatFromInt(texture.height));
        tex_u2 = (src_rect.x + src_rect.w) / @as(f32, @floatFromInt(texture.width));
        tex_v2 = (src_rect.y + src_rect.h) / @as(f32, @floatFromInt(texture.height));
    }

    // Create quad vertices (2 triangles)
    const vertices = [6]TextureVertex{
        .{ .position = .{ x1, y1 }, .texCoord = .{ tex_u1, tex_v1 } },
        .{ .position = .{ x2, y1 }, .texCoord = .{ tex_u2, tex_v1 } },
        .{ .position = .{ x1, y2 }, .texCoord = .{ tex_u1, tex_v2 } },
        .{ .position = .{ x1, y2 }, .texCoord = .{ tex_u1, tex_v2 } },
        .{ .position = .{ x2, y1 }, .texCoord = .{ tex_u2, tex_v1 } },
        .{ .position = .{ x2, y2 }, .texCoord = .{ tex_u2, tex_v2 } },
    };

    // Update vertex buffer
    const vertex_buffer = ctx.texture_vertex_buffer.?;
    const vertex_contents = vertex_buffer.msgSend(?*anyopaque, objc.sel("contents"), .{}).?;
    @memcpy(@as([*]u8, @ptrCast(vertex_contents))[0..@sizeOf(@TypeOf(vertices))], std.mem.asBytes(&vertices));

    // Set pipeline state
    encoder.msgSend(void, objc.sel("setRenderPipelineState:"), .{ctx.texture_pipeline_state.?.value});

    // Set vertex buffer
    encoder.msgSend(void, objc.sel("setVertexBuffer:offset:atIndex:"), .{ vertex_buffer.value, @as(c_ulong, 0), @as(c_ulong, 0) });

    // Set uniform buffer
    encoder.msgSend(void, objc.sel("setVertexBuffer:offset:atIndex:"), .{ uniform_buffer.value, @as(c_ulong, 0), @as(c_ulong, 1) });

    // Set texture and sampler
    encoder.msgSend(void, objc.sel("setFragmentTexture:atIndex:"), .{ texture.texture.value, @as(c_ulong, 0) });
    encoder.msgSend(void, objc.sel("setFragmentSamplerState:atIndex:"), .{ ctx.texture_sampler.?.value, @as(c_ulong, 0) });

    // Draw
    encoder.msgSend(void, objc.sel("drawPrimitives:vertexStart:vertexCount:"), .{ @intFromEnum(mtl.MTLPrimitiveType.triangle), @as(c_ulong, 0), @as(c_ulong, 6) });
}

pub fn drawTextureBatch(
    ctx: *Context,
    texture: Texture,
    src: ?@import("../renderer.zig").Rect,
    dst: []@import("../renderer.zig").Rect,
) !void {
    // For now, just draw each texture individually
    // TODO: Optimize this with instanced rendering or batching
    for (dst) |rect| {
        try drawTexture(ctx, texture, src, rect);
    }
}
