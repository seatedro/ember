const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const wgpu = @import("wgpu");
const Renderer = @import("../renderer.zig");
const TextureAtlas = @import("../../core/atlas.zig").TextureAtlas;
const core = @import("../../core/types.zig");
const resource = @import("../../core/resource.zig");
const sprite = @import("../../sprite/sprite.zig");
const math = std.math;

const BackendTexture = resource.BackendTexture;
const SpriteInstance = sprite.SpriteInstance;
const CircleInstance = sprite.CircleInstance;
const LineInstance = sprite.LineInstance;
const RectInstance = sprite.RectInstance;

const Region = core.Region;
const CanvasSize = core.CanvasSize;

pub const Context = struct {
    allocator: std.mem.Allocator,
    window: *sdl.c.SDL_Window,
    instance: *wgpu.Instance,
    adapter: ?*wgpu.Adapter,
    device: ?*wgpu.Device,
    queue: ?*wgpu.Queue,
    surface: ?*wgpu.Surface,
    surface_config: wgpu.SurfaceConfiguration,
    width: u32,
    height: u32,

    pipeline: ?*wgpu.RenderPipeline = null,
    bind_group_layout: ?*wgpu.BindGroupLayout = null,
    sampler: ?*wgpu.Sampler = null,
    vertex_buffer: ?*wgpu.Buffer = null,
    index_buffer: ?*wgpu.Buffer = null,

    atlas_tex: ?*wgpu.Texture = null,
    atlas_view: ?*wgpu.TextureView = null,
    atlas_bind_group: ?*wgpu.BindGroup = null,
};

pub const Texture = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
    bind_group: *wgpu.BindGroup,
    width: u32,
    height: u32,
};

const DrawListVertex = struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};

pub fn init(
    allocator: std.mem.Allocator,
    window: *sdl.c.SDL_Window,
) Renderer.Error!Context {
    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSizeInPixels(window, &w, &h);

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
    const instance = wgpu.Instance.create(&instance_desc) orelse {
        std.log.err("Failed to create WGPU instance", .{});
        return Renderer.Error.InitializationFailed;
    };
    errdefer instance.release();

    const surface = try createSurfaceFromSDLWindow(instance, window);
    errdefer surface.release();

    const adapter_opts = wgpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = .undefined,
        .force_fallback_adapter = 0,
    };

    const adapter_response = instance.requestAdapterSync(&adapter_opts, 200_000_000);
    const adapter = switch (adapter_response.status) {
        .success => adapter_response.adapter,
        else => {
            std.log.err("Failed to request adapter: {s}", .{adapter_response.message orelse "Unknown error"});
            return Renderer.Error.InitializationFailed;
        },
    };
    errdefer if (adapter) |a| a.release();

    const device_desc = wgpu.DeviceDescriptor{
        .label = wgpu.StringView.fromSlice("Device"),
        .required_feature_count = 0,
        .required_features = &[_]wgpu.FeatureName{},
        .required_limits = null,
        .default_queue = wgpu.QueueDescriptor{
            .label = wgpu.StringView.fromSlice("Default Queue"),
        },
    };

    const device_response = adapter.?.requestDeviceSync(instance, &device_desc, 200_000_000);
    const device = switch (device_response.status) {
        .success => device_response.device,
        else => {
            std.log.err("Failed to request device: {s}", .{device_response.message orelse "Unknown error"});
            return Renderer.Error.InitializationFailed;
        },
    };
    errdefer if (device) |d| d.release();

    const queue = device.?.getQueue();

    var surface_caps: wgpu.SurfaceCapabilities = undefined;
    _ = surface.getCapabilities(adapter.?, &surface_caps);
    defer surface_caps.freeMembers();

    const surface_format = if (surface_caps.format_count > 0)
        surface_caps.formats[0]
    else
        .bgra8_unorm;

    const surface_config = wgpu.SurfaceConfiguration{
        .device = device.?,
        .format = surface_format,
        .usage = wgpu.TextureUsages.render_attachment,
        .width = @intCast(w),
        .height = @intCast(h),
        .present_mode = .fifo,
        .alpha_mode = .auto,
        .view_formats = &[_]wgpu.TextureFormat{},
        .view_format_count = 0,
    };

    surface.configure(&surface_config);

    var ctx = Context{
        .allocator = allocator,
        .window = window,
        .instance = instance,
        .adapter = adapter,
        .device = device,
        .queue = queue,
        .surface = surface,
        .surface_config = surface_config,
        .width = @intCast(w),
        .height = @intCast(h),
    };

    try createTextureResources(&ctx);
    try createDrawListPipeline(&ctx);

    std.log.info("WGPU Renderer initialized successfully", .{});

    return ctx;
}

pub fn deinit(ctx: *Context) void {
    std.log.info("Deinitializing WGPU Renderer...", .{});

    if (ctx.atlas_bind_group) |bg| bg.release();
    if (ctx.atlas_view) |v| v.release();
    if (ctx.atlas_tex) |t| t.release();

    if (ctx.vertex_buffer) |vb| vb.release();
    if (ctx.index_buffer) |ib| ib.release();
    if (ctx.sampler) |s| s.release();
    if (ctx.bind_group_layout) |bgl| bgl.release();
    if (ctx.pipeline) |p| p.release();
    if (ctx.surface) |s| s.release();
    if (ctx.device) |d| d.release();
    if (ctx.adapter) |a| a.release();
    ctx.instance.release();

    std.log.info("Deinitialized WGPU Renderer.", .{});
}

pub fn beginFrame(ctx: *Context, _: ig.c.ImVec4) Renderer.Error!void {
    _ = ctx;
}

pub fn endFrame(ctx: *Context) Renderer.Error!void {
    _ = ctx;
}

pub fn initImGuiBackend(ctx: *Context) Renderer.Error!void {
    if (!ig.ImGui_ImplSDL3_InitForOther(ctx.window)) {
        std.log.err("ImGui_ImplSDL3_InitForOther failed", .{});
        return Renderer.Error.InitializationFailed;
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
        return Renderer.Error.InitializationFailed;
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

pub fn render(ctx: *Context, clear_color: ig.c.ImVec4, dl: *Renderer.DrawList) !void {
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

    try renderDrawList(ctx, view, encoder, clear_color, dl);

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
}

pub fn resize(ctx: *Context, width: i32, height: i32) Renderer.Error!void {
    if (width == 0 or height == 0) return; // can report zero while minimized

    ctx.width = @intCast(width);
    ctx.height = @intCast(height);

    ig.ImGui_ImplWGPU_InvalidateDeviceObjects();

    ctx.surface_config.width = ctx.width;
    ctx.surface_config.height = ctx.height;
    ctx.surface.?.configure(&ctx.surface_config);

    if (!ig.ImGui_ImplWGPU_CreateDeviceObjects()) {
        std.log.err("Failed to recreate ImGui device objects after resize", .{});
        return Renderer.Error.InitializationFailed;
    }

    std.log.info("WGPU Renderer resized to {}x{}", .{ width, height });
}

pub fn setVSync(ctx: *Context, enabled: bool) Renderer.Error!void {
    ctx.surface_config.present_mode = if (enabled) .fifo else .immediate;
    ctx.surface.?.configure(&ctx.surface_config);
    std.log.info("WGPU Renderer VSync set to: {}", .{enabled});
}

pub fn loadTexture(ctx: *Context, path: []const u8) Renderer.Error!BackendTexture {
    const surface = sdl.c.IMG_Load(path.ptr);
    if (surface == null) {
        std.log.err("Failed to load image: {s}", .{path});
        return Renderer.Error.InitializationFailed;
    }
    defer sdl.c.SDL_DestroySurface(surface);

    const width: u32 = @intCast(surface.*.w);
    const height: u32 = @intCast(surface.*.h);
    const size = width * height * 4; // RGBA

    const rgba_surface = sdl.c.SDL_ConvertSurface(surface, sdl.c.SDL_PIXELFORMAT_RGBA32);
    if (rgba_surface == null) {
        std.log.err("Failed to convert surface to RGBA", .{});
        return Renderer.Error.InitializationFailed;
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
        return Renderer.Error.InitializationFailed;
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
        return Renderer.Error.InitializationFailed;
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

fn createSurfaceFromSDLWindow(instance: *wgpu.Instance, window: *sdl.c.SDL_Window) !*wgpu.Surface {
    const props = sdl.c.SDL_GetWindowProperties(window);
    if (props == 0) {
        std.log.err("Failed to get window properties", .{});
        return Renderer.Error.UnsupportedBackend;
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
                    return Renderer.Error.InitializationFailed;
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
                return Renderer.Error.InitializationFailed;
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
                return Renderer.Error.InitializationFailed;
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
                return Renderer.Error.InitializationFailed;
            };
        }
    }

    std.log.err("Unsupported platform for WGPU surface creation", .{});
    return Renderer.Error.UnsupportedBackend;
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

fn getCanvasSize(ctx: *Context) CanvasSize {
    return CanvasSize{ .width = @intCast(ctx.width), .height = @intCast(ctx.height) };
}

pub fn renderDrawList(
    ctx: *Context,
    view: *wgpu.TextureView,
    encoder: *wgpu.CommandEncoder,
    clear_color: ig.c.ImVec4,
    dl: *Renderer.DrawList,
) Renderer.Error!void {
    if (dl.cmd_buffer.items.len <= 0) return;

    // Initialize pipeline if not already done
    if (ctx.pipeline == null) {
        try createDrawListPipeline(ctx);
    }

    const commands = dl.cmd_buffer.items;
    const vs_ptr = dl.vtx_buffer.items;
    const vs_count = dl.vtx_buffer.items.len;
    const is_ptr = dl.idx_buffer.items;

    const csz = getCanvasSize(ctx);

    var wgpu_vertices = std.ArrayList(DrawListVertex).init(ctx.allocator);
    defer wgpu_vertices.deinit();

    try wgpu_vertices.ensureTotalCapacity(vs_count);
    for (vs_ptr) |drawvert| {
        const color_u32 = drawvert.color;
        const color_f32 = [4]f32{
            @as(f32, @floatFromInt(color_u32 & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 8) & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 16) & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 24) & 0xFF)) / 255.0,
        };

        const ndc_x = (drawvert.pos[0] / csz.getWidthFloat()) * 2.0 - 1.0;
        const ndc_y = 1.0 - (drawvert.pos[1] / csz.getHeightFloat()) * 2.0; // Flip Y

        wgpu_vertices.appendAssumeCapacity(DrawListVertex{
            .position = [2]f32{ ndc_x, ndc_y },
            .uv = [2]f32{ drawvert.uv[0], drawvert.uv[1] },
            .color = color_f32,
        });
    }

    // Upload vertex data
    const vertex_data_size = wgpu_vertices.items.len * @sizeOf(DrawListVertex);
    if (vertex_data_size > 0) {
        const required_vertex_size = @max(vertex_data_size * 2, 65536);

        if (ctx.vertex_buffer == null) {
            const vertex_buffer_desc = wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("DrawList Vertex Buffer"),
                .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                .size = required_vertex_size,
                .mapped_at_creation = 0,
            };
            ctx.vertex_buffer = ctx.device.?.createBuffer(&vertex_buffer_desc);
        } else {
            const current_size = ctx.vertex_buffer.?.getSize();
            if (vertex_data_size > current_size) {
                ctx.vertex_buffer.?.release();
                const vertex_buffer_desc = wgpu.BufferDescriptor{
                    .label = wgpu.StringView.fromSlice("DrawList Vertex Buffer"),
                    .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                    .size = required_vertex_size,
                    .mapped_at_creation = 0,
                };
                ctx.vertex_buffer = ctx.device.?.createBuffer(&vertex_buffer_desc);
            }
        }

        ctx.queue.?.writeBuffer(
            ctx.vertex_buffer.?,
            0,
            wgpu_vertices.items.ptr,
            vertex_data_size,
        );
    }

    // Upload index data
    const index_data_size = is_ptr.len * @sizeOf(u32);
    if (index_data_size > 0) {
        const required_index_size = @max(index_data_size * 2, 65536);

        if (ctx.index_buffer == null) {
            const index_buffer_desc = wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("DrawList Index Buffer"),
                .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                .size = required_index_size,
                .mapped_at_creation = 0,
            };
            ctx.index_buffer = ctx.device.?.createBuffer(&index_buffer_desc);
        } else {
            const current_size = ctx.index_buffer.?.getSize();
            if (index_data_size > current_size) {
                ctx.index_buffer.?.release();
                const index_buffer_desc = wgpu.BufferDescriptor{
                    .label = wgpu.StringView.fromSlice("DrawList Index Buffer"),
                    .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                    .size = required_index_size,
                    .mapped_at_creation = 0,
                };
                ctx.index_buffer = ctx.device.?.createBuffer(&index_buffer_desc);
            }
        }

        ctx.queue.?.writeBuffer(
            ctx.index_buffer.?,
            0,
            is_ptr.ptr,
            index_data_size,
        );
    }

    const render_pass_desc = wgpu.RenderPassDescriptor{
        .label = wgpu.StringView.fromSlice("DrawList Render Pass"),
        .color_attachment_count = 1,
        .color_attachments = &[_]wgpu.ColorAttachment{
            .{
                .view = view,
                .resolve_target = null,
                .load_op = .clear,
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

    const render_pass = encoder.beginRenderPass(&render_pass_desc) orelse {
        std.log.err("Failed to begin DrawList render pass", .{});
        return Renderer.Error.InitializationFailed;
    };
    defer render_pass.release();

    render_pass.setPipeline(ctx.pipeline.?);
    if (ctx.vertex_buffer) |vb| {
        render_pass.setVertexBuffer(0, vb, 0, vertex_data_size);
    }
    if (ctx.index_buffer) |ib| {
        render_pass.setIndexBuffer(ib, .uint32, 0, index_data_size);
    }

    for (commands) |cmd| {
        if (cmd.user_callback != null or cmd.elem_count == 0) continue;

        const bind_group = if (cmd.texture_id == null) blk: {
            if (ctx.atlas_bind_group == null) {
                std.log.err("Atlas not initialized but draw command needs it.", .{});
                continue;
            }
            break :blk ctx.atlas_bind_group.?;
        } else blk: {
            const backend_tex: *const BackendTexture = @ptrCast(@alignCast(cmd.texture_id));
            break :blk backend_tex.texture.bind_group;
        };

        render_pass.setBindGroup(0, bind_group, 0, null);
        render_pass.drawIndexed(cmd.elem_count, 1, cmd.idx_offset, @intCast(cmd.vtx_offset), 0);
    }

    render_pass.end();
}

fn createDrawListPipeline(ctx: *Context) Renderer.Error!void {
    const shader_source =
        \\struct VertexInput {
        \\    @location(0) position: vec2<f32>,
        \\    @location(1) uv: vec2<f32>,
        \\    @location(2) color: vec4<f32>,
        \\}
        \\
        \\struct VertexOutput {
        \\    @builtin(position) clip_position: vec4<f32>,
        \\    @location(0) uv: vec2<f32>,
        \\    @location(1) color: vec4<f32>,
        \\}
        \\
        \\@vertex
        \\fn vs_main(input: VertexInput) -> VertexOutput {
        \\    var output: VertexOutput;
        \\    output.clip_position = vec4<f32>(input.position, 0.0, 1.0);
        \\    output.uv = input.uv;
        \\    output.color = input.color;
        \\    return output;
        \\}
        \\
        \\@group(0) @binding(0) var texture_view: texture_2d<f32>;
        \\@group(0) @binding(1) var texture_sampler: sampler;
        \\
        \\@fragment
        \\fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
        \\    let tex_color = textureSample(texture_view, texture_sampler, input.uv);
        \\    return input.color * tex_color;
        \\}
    ;

    const shader_desc = wgpu.shaderModuleWGSLDescriptor(.{
        .label = "DrawList Shader",
        .code = shader_source,
    });
    const shader_module = ctx.device.?.createShaderModule(&shader_desc) orelse {
        return Renderer.Error.InitializationFailed;
    };
    defer shader_module.release();

    const pipeline_layout = ctx.device.?.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("DrawList Pipeline Layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{ctx.bind_group_layout.?},
    }) orelse return Renderer.Error.InitializationFailed;
    defer pipeline_layout.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{ .offset = 0, .shader_location = 0, .format = .float32x2 }, // position
        .{ .offset = 8, .shader_location = 1, .format = .float32x2 }, // uv
        .{ .offset = 16, .shader_location = 2, .format = .float32x4 }, // color
    };

    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(DrawListVertex),
        .step_mode = .vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };

    const render_pipeline_desc = wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("DrawList Pipeline"),
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

    ctx.pipeline = ctx.device.?.createRenderPipeline(&render_pipeline_desc);
    if (ctx.pipeline == null) {
        return Renderer.Error.InitializationFailed;
    }
}

pub fn syncAtlas(ctx: *Context, atlas: *TextureAtlas) !void {
    if (!atlas.dirty) return;

    const w = atlas.width;
    const h = atlas.height;

    if (ctx.atlas_tex == null) {
        std.log.info("Creating atlas texture", .{});
        const texture_desc = wgpu.TextureDescriptor{
            .label = wgpu.StringView.fromSlice("Atlas Texture"),
            .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
            .dimension = .@"2d",
            .size = wgpu.Extent3D{
                .width = w,
                .height = h,
                .depth_or_array_layers = 1,
            },
            .format = .rgba8_unorm,
            .mip_level_count = 1,
            .sample_count = 1,
            .view_format_count = 0,
            .view_formats = &[_]wgpu.TextureFormat{},
        };

        ctx.atlas_tex = ctx.device.?.createTexture(&texture_desc) orelse {
            return Renderer.Error.InitializationFailed;
        };

        ctx.atlas_view = ctx.atlas_tex.?.createView(null);

        ctx.atlas_bind_group = ctx.device.?.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("Atlas Bind Group"),
            .layout = ctx.bind_group_layout.?,
            .entry_count = 2,
            .entries = &[_]wgpu.BindGroupEntry{
                .{
                    .binding = 0,
                    .texture_view = ctx.atlas_view.?,
                },
                .{
                    .binding = 1,
                    .sampler = ctx.sampler.?,
                },
            },
        });
    }

    const texel_copy_tex = wgpu.TexelCopyTextureInfo{
        .texture = ctx.atlas_tex.?,
        .mip_level = 0,
        .origin = wgpu.Origin3D{ .x = 0, .y = 0, .z = 0 },
        .aspect = .all,
    };

    const texel_copy_layout = wgpu.TexelCopyBufferLayout{
        .offset = 0,
        .bytes_per_row = w * 4,
        .rows_per_image = h,
    };

    ctx.queue.?.writeTexture(&texel_copy_tex, atlas.pixels.ptr, atlas.pixels.len, &texel_copy_layout, &wgpu.Extent3D{
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
    });

    atlas.dirty = false;
}

test "optional" {
    const renderer_2d = @import("../renderer_2d.zig");
    var draw_data = renderer_2d.DrawData.init(std.testing.allocator) catch unreachable;
    var draw_list = Renderer.DrawList.init(std.testing.allocator, &draw_data);

    const ctx: Context = .{
        .allocator = std.testing.allocator,
        .dl = &draw_list,
        .window = undefined, // Would need real SDL window in actual usage
        .instance = undefined, // Would need real WGPU instance in actual usage
        .adapter = null,
        .device = null,
        .queue = null,
        .surface = null,
        .surface_config = std.mem.zeroes(wgpu.SurfaceConfiguration),
        .width = 0,
        .height = 0,
    };

    try std.testing.expect(ctx.pipeline == null);
    try std.testing.expect(ctx.bind_group_layout == null);
    try std.testing.expect(ctx.sampler == null);
    try std.testing.expect(ctx.atlas_tex == null);
    try std.testing.expect(ctx.atlas_view == null);
    try std.testing.expect(ctx.atlas_bind_group == null);

    std.debug.print("Test passed", .{});
}
