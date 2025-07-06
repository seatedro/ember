const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const wgpu = @import("wgpu");
const RendererInterface = @import("../renderer.zig");
const resource = @import("../../core/resource.zig");
const sprite = @import("../../sprite/sprite.zig");

const BackendTexture = resource.BackendTexture;
const SpriteInstance = sprite.SpriteInstance;
const CircleInstance = sprite.CircleInstance;
const LineInstance = sprite.LineInstance;
const RectInstance = sprite.RectInstance;

pub const Context = struct {
    allocator: std.mem.Allocator,
    window: *sdl.c.SDL_Window,
    instance: *wgpu.Instance,
    adapter: ?*wgpu.Adapter,
    device: ?*wgpu.Device,
    queue: ?*wgpu.Queue,
    surface: ?*wgpu.Surface,
    surface_config: wgpu.SurfaceConfiguration,
    render_pipeline: ?*wgpu.RenderPipeline,
    bind_group_layout: ?*wgpu.BindGroupLayout,
    sampler: ?*wgpu.Sampler,
    vertex_buffer: ?*wgpu.Buffer,
    vertices: std.ArrayList(Vertex),
    width: u32,
    height: u32,
    draw_calls: std.ArrayList(DrawCall),
    vertex_data: std.ArrayList(Vertex),
};

pub const Texture = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
    bind_group: *wgpu.BindGroup,
    width: u32,
    height: u32,
};

const Vertex = struct {
    position: [2]f32,
    tex_coords: [2]f32,
};

const DrawCall = struct {
    texture_view: *wgpu.TextureView,
    bind_group: *wgpu.BindGroup,
    vertex_offset: u32,
    vertex_count: u32,
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) RendererInterface.Error!*Context {
    const ctx = try allocator.create(Context);
    errdefer allocator.destroy(ctx);

    ctx.allocator = allocator;
    ctx.window = window;
    ctx.vertices = std.ArrayList(Vertex).init(allocator);
    ctx.draw_calls = std.ArrayList(DrawCall).init(allocator);
    ctx.vertex_data = std.ArrayList(Vertex).init(allocator);

    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSizeInPixels(window, &w, &h);
    ctx.width = @intCast(w);
    ctx.height = @intCast(h);

    var logical_w: c_int = 0;
    var logical_h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSize(window, &logical_w, &logical_h);

    std.log.info("WGPU window size - logical: {}x{}, physical: {}x{}", .{ logical_w, logical_h, w, h });

    const instance_desc = wgpu.InstanceDescriptor{
        .features = wgpu.InstanceCapabilities{
            .timed_wait_any_enable = 0,
            .timed_wait_any_max_count = 0,
        },
    };
    ctx.instance = wgpu.Instance.create(&instance_desc) orelse {
        std.log.err("Failed to create WGPU instance", .{});
        return RendererInterface.Error.InitializationFailed;
    };
    errdefer ctx.instance.release();

    ctx.surface = try createSurfaceFromSDLWindow(ctx.instance, window);
    errdefer if (ctx.surface) |s| s.release();

    const adapter_opts = wgpu.RequestAdapterOptions{
        .compatible_surface = ctx.surface,
        .power_preference = .undefined,
        .force_fallback_adapter = 0,
    };

    const adapter_response = ctx.instance.requestAdapterSync(&adapter_opts, 200_000_000);
    ctx.adapter = switch (adapter_response.status) {
        .success => adapter_response.adapter,
        else => {
            std.log.err("Failed to request adapter: {s}", .{adapter_response.message orelse "Unknown error"});
            return RendererInterface.Error.InitializationFailed;
        },
    };
    errdefer if (ctx.adapter) |a| a.release();

    const device_desc = wgpu.DeviceDescriptor{
        .label = wgpu.StringView.fromSlice("Device"),
        .required_feature_count = 0,
        .required_features = &[_]wgpu.FeatureName{},
        .required_limits = null,
        .default_queue = wgpu.QueueDescriptor{
            .label = wgpu.StringView.fromSlice("Default Queue"),
        },
    };

    const device_response = ctx.adapter.?.requestDeviceSync(ctx.instance, &device_desc, 200_000_000);
    ctx.device = switch (device_response.status) {
        .success => device_response.device,
        else => {
            std.log.err("Failed to request device: {s}", .{device_response.message orelse "Unknown error"});
            return RendererInterface.Error.InitializationFailed;
        },
    };
    errdefer if (ctx.device) |d| d.release();

    ctx.queue = ctx.device.?.getQueue();

    var surface_caps: wgpu.SurfaceCapabilities = undefined;
    _ = ctx.surface.?.getCapabilities(ctx.adapter.?, &surface_caps);
    defer surface_caps.freeMembers();

    const surface_format = if (surface_caps.format_count > 0)
        surface_caps.formats[0]
    else
        .bgra8_unorm;

    ctx.surface_config = wgpu.SurfaceConfiguration{
        .device = ctx.device.?,
        .format = surface_format,
        .usage = wgpu.TextureUsages.render_attachment,
        .width = ctx.width,
        .height = ctx.height,
        .present_mode = .fifo,
        .alpha_mode = .auto,
        .view_formats = &[_]wgpu.TextureFormat{},
        .view_format_count = 0,
    };

    ctx.surface.?.configure(&ctx.surface_config);

    try createTextureResources(ctx);

    try createRenderPipeline(ctx);

    const vertex_buffer_desc = wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Vertex Buffer"),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .size = @sizeOf(Vertex) * 6 * 65536,
        .mapped_at_creation = 0,
    };
    ctx.vertex_buffer = ctx.device.?.createBuffer(&vertex_buffer_desc);

    std.log.info("WGPU Renderer initialized successfully", .{});
    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    std.log.info("Deinitializing WGPU Renderer...", .{});

    if (ctx.vertex_buffer) |vb| vb.release();
    if (ctx.sampler) |s| s.release();
    if (ctx.bind_group_layout) |bgl| bgl.release();
    if (ctx.render_pipeline) |rp| rp.release();
    if (ctx.surface) |s| s.release();
    if (ctx.device) |d| d.release();
    if (ctx.adapter) |a| a.release();
    ctx.instance.release();
    ctx.vertices.deinit();
    ctx.draw_calls.deinit();
    ctx.vertex_data.deinit();

    allocator.destroy(ctx);
    std.log.info("Deinitialized WGPU Renderer.", .{});
}

pub fn beginFrame(ctx: *Context, _: ig.c.ImVec4) RendererInterface.Error!void {
    _ = ctx;
}

pub fn endFrame(ctx: *Context) RendererInterface.Error!void {
    _ = ctx;
}

pub fn initImGuiBackend(ctx: *Context) RendererInterface.Error!void {
    if (!ig.ImGui_ImplSDL3_InitForOther(ctx.window)) {
        std.log.err("ImGui_ImplSDL3_InitForOther failed", .{});
        return RendererInterface.Error.InitializationFailed;
    }

    var init_info = ig.ImGui_ImplWGPU_InitInfo{
        .Device = ctx.device,
        .NumFramesInFlight = 2,
        .RenderTargetFormat = @as(c_int, @intCast(@intFromEnum(ctx.surface_config.format))),
        .DepthStencilFormat = @as(c_int, @intCast(@intFromEnum(wgpu.TextureFormat.undefined))),
        .PipelineMultisampleState = ig.WGPUMultisampleState{
            .next_in_chain = null,
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alpha_to_coverage_enabled = false,
        },
    };

    if (!ig.ImGui_ImplWGPU_Init(&init_info)) {
        std.log.err("ImGui_ImplWGPU_Init failed", .{});
        return RendererInterface.Error.InitializationFailed;
    }

    std.log.info("ImGui WGPU Backend Initialized.", .{});
}

pub fn deinitImGuiBackend() void {
    ig.ImGui_ImplWGPU_Shutdown();
}

pub fn newImGuiFrame() void {
    ig.ImGui_ImplWGPU_NewFrame();
}

pub fn renderImGui(
    draw_data: *ig.c.ImDrawData,
    clear_color: ig.c.ImVec4,
    view: *wgpu.TextureView,
    encoder: *wgpu.CommandEncoder,
) void {
    const render_pass_desc = wgpu.RenderPassDescriptor{
        .label = wgpu.StringView.fromSlice("Render Pass"),
        .color_attachment_count = 1,
        .color_attachments = &[_]wgpu.ColorAttachment{
            .{
                .view = view,
                .resolve_target = null,
                .load_op = .load,
                .store_op = .store,
                .clear_value = wgpu.Color{
                    .r = clear_color.x * clear_color.w,
                    .g = clear_color.y * clear_color.w,
                    .b = clear_color.z * clear_color.w,
                    .a = clear_color.w,
                },
            },
        },
        .depth_stencil_attachment = null,
        .occlusion_query_set = null,
        .timestamp_writes = null,
    };

    const imgui_render_pass = encoder.beginRenderPass(&render_pass_desc) orelse {
        std.log.err("Failed to begin ImGui render pass", .{});
        return;
    };
    defer imgui_render_pass.release();

    ig.ImGui_ImplWGPU_RenderDrawData(draw_data, imgui_render_pass);

    imgui_render_pass.end();
}

pub fn render(ctx: *Context, clear_color: ig.c.ImVec4) void {
    var surface_texture: wgpu.SurfaceTexture = undefined;
    ctx.surface.?.getCurrentTexture(&surface_texture);
    defer if (surface_texture.texture) |texture| texture.release();

    if (surface_texture.status != .success_optimal) {
        std.log.err("Failed to get current surface texture: status = {}", .{surface_texture.status});
        return;
    }

    const view = surface_texture.texture.?.createView(null) orelse {
        std.log.err("Failed to create texture view", .{});
        return;
    };
    defer view.release();

    const encoder_desc = wgpu.CommandEncoderDescriptor{
        .label = wgpu.StringView.fromSlice("Command Encoder"),
    };
    const encoder = ctx.device.?.createCommandEncoder(&encoder_desc) orelse {
        std.log.err("Failed to create command encoder", .{});
        return;
    };
    defer encoder.release();

    if (ctx.draw_calls.items.len > 0 and ctx.vertex_data.items.len > 0) {
        std.log.debug("drawing game content: {}", .{ctx.vertex_data.items.len});
        const game_render_pass_desc = wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Game Content Render Pass"),
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.ColorAttachment{
                .{
                    .view = view,
                    .resolve_target = null,
                    .load_op = .clear, // Clear first
                    .store_op = .store,
                    .clear_value = wgpu.Color{
                        .r = clear_color.x * clear_color.w,
                        .g = clear_color.y * clear_color.w,
                        .b = clear_color.z * clear_color.w,
                        .a = clear_color.w,
                    },
                },
            },
            .depth_stencil_attachment = null,
            .occlusion_query_set = null,
            .timestamp_writes = null,
        };

        const game_render_pass = encoder.beginRenderPass(&game_render_pass_desc) orelse {
            std.log.err("Failed to begin game render pass", .{});
            return;
        };
        defer game_render_pass.release();

        const vertex_data_size = ctx.vertex_data.items.len * @sizeOf(Vertex);
        ctx.queue.?.writeBuffer(
            ctx.vertex_buffer.?,
            0,
            ctx.vertex_data.items.ptr,
            vertex_data_size,
        );

        if (ctx.render_pipeline) |pipeline| {
            game_render_pass.setPipeline(pipeline);

            for (ctx.draw_calls.items) |draw_call| {
                game_render_pass.setBindGroup(0, draw_call.bind_group, 0, null);
                game_render_pass.setVertexBuffer(0, ctx.vertex_buffer.?, draw_call.vertex_offset * @sizeOf(Vertex), draw_call.vertex_count * @sizeOf(Vertex));
                game_render_pass.draw(draw_call.vertex_count, 1, 0, 0);
            }
        }

        game_render_pass.end();
    }

    const draw_data = ig.igGetDrawData();
    if (draw_data) |data| {
        if (data.Valid and data.CmdListsCount > 0) {
            renderImGui(data, clear_color, view, encoder);
        }
    } else {
        std.log.warn("ImGui draw data was null!", .{});
    }

    const command_buffer_desc = wgpu.CommandBufferDescriptor{
        .label = wgpu.StringView.fromSlice("Command Buffer"),
    };
    const command_buffer = encoder.finish(&command_buffer_desc) orelse {
        std.log.err("Failed to finish command buffer", .{});
        return;
    };
    defer command_buffer.release();
    ctx.queue.?.submit(&[_]*wgpu.CommandBuffer{command_buffer});
    _ = ctx.surface.?.present();
    ctx.draw_calls.clearRetainingCapacity();
    ctx.vertex_data.clearRetainingCapacity();
}

pub fn resize(ctx: *Context, width: i32, height: i32) RendererInterface.Error!void {
    ctx.width = @intCast(width);
    ctx.height = @intCast(height);

    ig.ImGui_ImplWGPU_InvalidateDeviceObjects();

    ctx.surface_config.width = ctx.width;
    ctx.surface_config.height = ctx.height;
    ctx.surface.?.configure(&ctx.surface_config);

    if (!ig.ImGui_ImplWGPU_CreateDeviceObjects()) {
        std.log.err("Failed to recreate ImGui device objects after resize", .{});
        return RendererInterface.Error.InitializationFailed;
    }

    std.log.info("WGPU Renderer resized to {}x{}", .{ width, height });
}

pub fn setVSync(ctx: *Context, enabled: bool) RendererInterface.Error!void {
    ctx.surface_config.present_mode = if (enabled) .fifo else .immediate;
    ctx.surface.?.configure(&ctx.surface_config);
    std.log.info("WGPU Renderer VSync set to: {}", .{enabled});
}

pub fn loadTexture(ctx: *Context, path: []const u8) RendererInterface.Error!BackendTexture {
    const surface = sdl.c.IMG_Load(path.ptr);
    if (surface == null) {
        std.log.err("Failed to load image: {s}", .{path});
        return RendererInterface.Error.InitializationFailed;
    }
    defer sdl.c.SDL_DestroySurface(surface);

    const width: u32 = @intCast(surface.*.w);
    const height: u32 = @intCast(surface.*.h);
    const size = width * height * 4; // RGBA

    const rgba_surface = sdl.c.SDL_ConvertSurface(surface, sdl.c.SDL_PIXELFORMAT_RGBA32);
    if (rgba_surface == null) {
        std.log.err("Failed to convert surface to RGBA", .{});
        return RendererInterface.Error.InitializationFailed;
    }
    defer sdl.c.SDL_DestroySurface(rgba_surface);

    const texture_desc = wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Loaded Texture"),
        .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
        .dimension = .@"2d",
        .size = wgpu.Extent3D{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
        .sample_count = 1,
        .view_format_count = 0,
        .view_formats = &[_]wgpu.TextureFormat{},
    };

    const texture = ctx.device.?.createTexture(&texture_desc) orelse {
        std.log.err("Failed to create texture", .{});
        return RendererInterface.Error.InitializationFailed;
    };

    const texel_copy_texture = wgpu.TexelCopyTextureInfo{
        .texture = texture,
        .mip_level = 0,
        .origin = wgpu.Origin3D{ .x = 0, .y = 0, .z = 0 },
        .aspect = .all,
    };

    const texel_copy_layout = wgpu.TexelCopyBufferLayout{
        .offset = 0,
        .bytes_per_row = width * 4,
        .rows_per_image = height,
    };

    ctx.queue.?.writeTexture(
        &texel_copy_texture,
        @ptrCast(rgba_surface.*.pixels.?),
        size,
        &texel_copy_layout,
        &wgpu.Extent3D{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
    );

    const view = texture.createView(null);

    const bind_group = ctx.device.?.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Texture Bind Group"),
        .layout = ctx.bind_group_layout.?,
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .texture_view = view,
            },
            .{
                .binding = 1,
                .sampler = ctx.sampler.?,
            },
        },
    });

    if (bind_group == null) {
        std.log.err("Failed to create bind group for texture", .{});
        return RendererInterface.Error.InitializationFailed;
    }

    std.log.info("Texture loaded successfully: {}x{}", .{ width, height });

    const tex = Texture{
        .texture = texture,
        .view = view.?,
        .bind_group = bind_group.?,
        .width = width,
        .height = height,
    };

    return BackendTexture{ .texture = tex, .width = width, .height = height };
}

pub fn destroyTexture(tex: Texture) void {
    tex.bind_group.release();
    tex.view.release();
    tex.texture.release();
}

pub fn renderSpriteInstances(
    ctx: *Context,
    backend_tex: BackendTexture,
    instances: []const SpriteInstance,
) RendererInterface.Error!void {
    if (instances.len == 0) return;
    if (ctx.render_pipeline == null) {
        std.log.err("Render pipeline not initialized", .{});
        return;
    }

    const texture = backend_tex.texture;

    const vertex_offset = @as(u32, @intCast(ctx.vertex_data.items.len));

    try ctx.vertex_data.ensureUnusedCapacity(instances.len * 6);

    for (instances) |instance| {
        const pos_x = instance.transform[3]; // 4th column, 1st row (m03)
        const pos_y = instance.transform[7]; // 4th column, 2nd row (m13)

        const scale_x = @sqrt(instance.transform[0] * instance.transform[0] + instance.transform[4] * instance.transform[4]);
        const scale_y = @sqrt(instance.transform[1] * instance.transform[1] + instance.transform[5] * instance.transform[5]);

        const base_size = 32.0;
        const width = base_size * scale_x;
        const height = base_size * scale_y;

        const x0 = pos_x / @as(f32, @floatFromInt(ctx.width)) * 2.0 - 1.0;
        const y0 = 1.0 - pos_y / @as(f32, @floatFromInt(ctx.height)) * 2.0;
        const x1 = (pos_x + width) / @as(f32, @floatFromInt(ctx.width)) * 2.0 - 1.0;
        const y1 = 1.0 - (pos_y + height) / @as(f32, @floatFromInt(ctx.height)) * 2.0;

        const uv_offset_scale = instance.uv_offset_scale;
        const tex_u0 = uv_offset_scale[0];
        const tex_v0 = uv_offset_scale[1];
        const tex_u1 = uv_offset_scale[0] + uv_offset_scale[2];
        const tex_v1 = uv_offset_scale[1] + uv_offset_scale[3];

        try ctx.vertex_data.append(.{ .position = .{ x0, y0 }, .tex_coords = .{ tex_u0, tex_v0 } });
        try ctx.vertex_data.append(.{ .position = .{ x1, y0 }, .tex_coords = .{ tex_u1, tex_v0 } });
        try ctx.vertex_data.append(.{ .position = .{ x1, y1 }, .tex_coords = .{ tex_u1, tex_v1 } });
        try ctx.vertex_data.append(.{ .position = .{ x0, y0 }, .tex_coords = .{ tex_u0, tex_v0 } });
        try ctx.vertex_data.append(.{ .position = .{ x1, y1 }, .tex_coords = .{ tex_u1, tex_v1 } });
        try ctx.vertex_data.append(.{ .position = .{ x0, y1 }, .tex_coords = .{ tex_u0, tex_v1 } });
    }

    const vertex_count = @as(u32, @intCast(ctx.vertex_data.items.len - vertex_offset));

    try ctx.draw_calls.append(.{
        .texture_view = texture.view,
        .bind_group = texture.bind_group,
        .vertex_offset = vertex_offset,
        .vertex_count = vertex_count,
    });
}

/// TODO: Implement SDF-based circle rendering
pub fn renderCircleInstances(
    ctx: *Context,
    instances: []const CircleInstance,
) RendererInterface.Error!void {
    _ = ctx;
    _ = instances;
}

/// TODO: Implement instanced line rendering with geometry shaders or compute
pub fn renderLineInstances(
    ctx: *Context,
    instances: []const LineInstance,
) RendererInterface.Error!void {
    _ = ctx;
    _ = instances;
}

/// TODO: Implement SDF-based rectangle rendering
pub fn renderRectInstances(
    ctx: *Context,
    instances: []const RectInstance,
) RendererInterface.Error!void {
    _ = ctx;
    _ = instances;
}

fn createSurfaceFromSDLWindow(instance: *wgpu.Instance, window: *sdl.c.SDL_Window) !*wgpu.Surface {
    const props = sdl.c.SDL_GetWindowProperties(window);
    if (props == 0) {
        std.log.err("Failed to get window properties", .{});
        return RendererInterface.Error.UnsupportedBackend;
    }

    // macOS/Cocoa
    if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.cocoa.window", null)) |cocoa_window| {
        const metal_view = sdl.c.SDL_Metal_CreateView(window);
        if (metal_view) |view| {
            const layer = sdl.c.SDL_Metal_GetLayer(view);
            if (layer) |metal_layer| {
                const desc = wgpu.surfaceDescriptorFromMetalLayer(.{
                    .layer = metal_layer,
                });
                return instance.createSurface(&desc) orelse {
                    std.log.err("Failed to create WGPU surface from Metal layer", .{});
                    return RendererInterface.Error.InitializationFailed;
                };
            }
        }
        _ = cocoa_window; // suppress unused warning
    }

    // Windows
    if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.win32.hwnd", null)) |hwnd| {
        if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.win32.hinstance", null)) |hinstance| {
            const desc = wgpu.surfaceDescriptorFromWindowsHWND(.{
                .hinstance = hinstance,
                .hwnd = hwnd,
            });
            return instance.createSurface(&desc) orelse {
                std.log.err("Failed to create WGPU surface from HWND", .{});
                return RendererInterface.Error.InitializationFailed;
            };
        }
    }

    // Check for X11
    const x11_window = sdl.c.SDL_GetNumberProperty(props, "SDL.window.x11.window", 0);
    if (x11_window != 0) {
        if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.x11.display", null)) |x11_display| {
            const desc = wgpu.surfaceDescriptorFromXlibWindow(.{
                .display = x11_display,
                .window = @intCast(x11_window),
            });
            return instance.createSurface(&desc) orelse {
                std.log.err("Failed to create WGPU surface from X11 window", .{});
                return RendererInterface.Error.InitializationFailed;
            };
        }
    }

    // Wayland
    if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.wayland.surface", null)) |wl_surface| {
        if (sdl.c.SDL_GetPointerProperty(props, "SDL.window.wayland.display", null)) |wl_display| {
            const desc = wgpu.surfaceDescriptorFromWaylandSurface(.{
                .display = wl_display,
                .surface = wl_surface,
            });
            return instance.createSurface(&desc) orelse {
                std.log.err("Failed to create WGPU surface from Wayland surface", .{});
                return RendererInterface.Error.InitializationFailed;
            };
        }
    }

    std.log.err("Unsupported platform for WGPU surface creation", .{});
    return RendererInterface.Error.UnsupportedBackend;
}

fn createTextureResources(ctx: *Context) !void {
    const sampler_desc = wgpu.SamplerDescriptor{
        .label = wgpu.StringView.fromSlice("Texture Sampler"),
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
        .lod_min_clamp = 0.0,
        .lod_max_clamp = 32.0,
        .compare = .undefined,
        .max_anisotropy = 1,
    };
    ctx.sampler = ctx.device.?.createSampler(&sampler_desc);

    const bind_group_layout_desc = wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Texture Bind Group Layout"),
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = wgpu.TextureBindingLayout{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                    .multisampled = 0,
                },
                .sampler = wgpu.SamplerBindingLayout{
                    .type = .binding_not_used,
                },
                .buffer = wgpu.BufferBindingLayout{
                    .type = .binding_not_used,
                },
                .storage_texture = wgpu.StorageTextureBindingLayout{
                    .access = .binding_not_used,
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = wgpu.SamplerBindingLayout{
                    .type = .filtering,
                },
                .texture = wgpu.TextureBindingLayout{
                    .sample_type = .binding_not_used,
                },
                .buffer = wgpu.BufferBindingLayout{
                    .type = .binding_not_used,
                },
                .storage_texture = wgpu.StorageTextureBindingLayout{
                    .access = .binding_not_used,
                },
            },
        },
    };
    ctx.bind_group_layout = ctx.device.?.createBindGroupLayout(&bind_group_layout_desc);
}

fn createRenderPipeline(ctx: *Context) !void {
    const shader_source =
        \\struct VertexOutput {
        \\    @builtin(position) clip_position: vec4f,
        \\    @location(0) tex_coords: vec2f,
        \\}
        \\
        \\@vertex
        \\fn vs_main(@location(0) position: vec2f, @location(1) tex_coords: vec2f) -> VertexOutput {
        \\    var out: VertexOutput;
        \\    out.clip_position = vec4f(position, 0.0, 1.0);
        \\    out.tex_coords = tex_coords;
        \\    return out;
        \\}
        \\
        \\@group(0) @binding(0) var texture_view: texture_2d<f32>;
        \\@group(0) @binding(1) var texture_sampler: sampler;
        \\
        \\@fragment
        \\fn fs_main(in: VertexOutput) -> @location(0) vec4f {
        \\    return textureSample(texture_view, texture_sampler, in.tex_coords);
        \\}
    ;

    const shader_desc = wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Texture Shader",
        .code = shader_source,
    });
    const shader_module = ctx.device.?.createShaderModule(&shader_desc) orelse {
        std.log.err("Failed to create shader module", .{});
        return RendererInterface.Error.InitializationFailed;
    };
    defer shader_module.release();

    const pipeline_layout_desc = wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Render Pipeline Layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{ctx.bind_group_layout.?},
    };
    const pipeline_layout = ctx.device.?.createPipelineLayout(&pipeline_layout_desc) orelse {
        std.log.err("Failed to create pipeline layout", .{});
        return RendererInterface.Error.InitializationFailed;
    };
    defer pipeline_layout.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .offset = 0,
            .shader_location = 0,
            .format = .float32x2,
        },
        .{
            .offset = @offsetOf(Vertex, "tex_coords"),
            .shader_location = 1,
            .format = .float32x2,
        },
    };

    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };

    const render_pipeline_desc = wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Render Pipeline"),
        .layout = pipeline_layout,
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .primitive = wgpu.PrimitiveState{
            .topology = .triangle_list,
            .strip_index_format = .undefined,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .depth_stencil = null,
        .multisample = wgpu.MultisampleState{
            .count = 1,
            .mask = ~@as(u32, 0),
            .alpha_to_coverage_enabled = 0,
        },
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{
                .{
                    .format = ctx.surface_config.format,
                    .blend = &wgpu.BlendState{
                        .color = wgpu.BlendComponent{
                            .src_factor = .src_alpha,
                            .dst_factor = .one_minus_src_alpha,
                            .operation = .add,
                        },
                        .alpha = wgpu.BlendComponent{
                            .src_factor = .one,
                            .dst_factor = .zero,
                            .operation = .add,
                        },
                    },
                    .write_mask = wgpu.ColorWriteMasks.all,
                },
            },
        },
    };

    ctx.render_pipeline = ctx.device.?.createRenderPipeline(&render_pipeline_desc);
    if (ctx.render_pipeline == null) {
        std.log.err("Failed to create render pipeline!", .{});
        return RendererInterface.Error.InitializationFailed;
    }
    std.log.info("Render pipeline created successfully", .{});
}
