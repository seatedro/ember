const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const Renderer = @import("../renderer.zig");
const resource = @import("../../core/resource.zig");
const gl = @import("opengl");
const sprite = @import("../../sprite/sprite.zig");
const errors = @import("../errors.zig");

const glad = gl.glad;
const Buffer = gl.Buffer;
const Shader = gl.Shader;
const Program = gl.Program;
const VertexArray = gl.VertexArray;
pub const Texture = gl.Texture;

const BackendTexture = resource.BackendTexture;
const SpriteInstance = sprite.SpriteInstance;
const CircleInstance = sprite.CircleInstance;
const LineInstance = sprite.LineInstance;
const RectInstance = sprite.RectInstance;

pub const BatchedVertex = [4]f32; // Vertex data layout: [x, y, u, v]
pub const Context = struct {
    renderer: sdl.c.SDL_GLContext,
    window: *sdl.c.SDL_Window,
    shader_program: Program,
    quad_vao: VertexArray,
    quad_vbo: Buffer,
    vertices: std.ArrayList(BatchedVertex),
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !*Context {
    _ = sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_PROFILE_MASK, sdl.c.SDL_GL_CONTEXT_PROFILE_CORE);

    const gl_ctx = sdl.c.SDL_GL_CreateContext(window);
    errdefer {
        _ = sdl.c.SDL_GL_DestroyContext(gl_ctx);
    }

    const version = try glad.load(&sdl.c.SDL_GL_GetProcAddress);
    errdefer glad.unload();
    std.log.info("loaded OpenGL {}.{}", .{
        gl.glad.versionMajor(@intCast(version)),
        gl.glad.versionMinor(@intCast(version)),
    });

    try sdl.errify(sdl.c.SDL_GL_MakeCurrent(window, gl_ctx));

    const vert_src =
        \\#version 330 core
        \\layout(location = 0) in vec2 inPos;
        \\layout(location = 1) in vec2 inUV;
        \\out vec2 uv;
        \\void main() {
        \\    uv = inUV;
        \\    gl_Position = vec4(inPos, 0.0, 1.0);
        \\}
    ;
    const frag_src =
        \\#version 330 core
        \\in vec2 uv;
        \\out vec4 fragColor;
        \\uniform sampler2D tex;
        \\void main() {
        \\    fragColor = texture(tex, uv);
        \\}
    ;

    const program = try Program.createVF(vert_src, frag_src);
    errdefer program.destroy();

    const vao = try VertexArray.create();
    errdefer vao.destroy();

    const vertices = std.ArrayList(BatchedVertex).init(allocator);
    errdefer vertices.deinit();

    const vbo = try Buffer.create();
    errdefer vbo.destroy();

    {
        const vao_binding = try vao.bind();
        defer vao_binding.unbind();

        const vbo_binding = try vbo.bind(.array);
        defer vbo_binding.unbind();

        try vbo_binding.setDataNullManual(@sizeOf([6][4]f32), .dynamic_draw);

        try vbo_binding.attributeAdvanced(0, 2, gl.c.GL_FLOAT, false, 4 * @sizeOf(f32), 0);
        try vbo_binding.enableAttribArray(0);

        try vbo_binding.attributeAdvanced(1, 2, gl.c.GL_FLOAT, false, 4 * @sizeOf(f32), 2 * @sizeOf(f32));
        try vbo_binding.enableAttribArray(1);
    }

    const ctx = try allocator.create(Context);
    ctx.* = Context{
        .window = window,
        .renderer = gl_ctx,
        .shader_program = program,
        .quad_vao = vao,
        .quad_vbo = vbo,
        .vertices = vertices,
    };

    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    std.log.info("Deinitializing GL Renderer...", .{});
    if (ctx.renderer) |r| {
        _ = sdl.c.SDL_GL_DestroyContext(r);
    }
    ctx.vertices.deinit();
    allocator.destroy(ctx);
    std.log.info("Deinitialized GL Renderer.", .{});
}

pub fn beginFrame(_: *Context, clear_color: ig.c.ImVec4) !void {
    gl.clearColor(clear_color.x, clear_color.y, clear_color.z, clear_color.w);
    gl.clear(gl.c.GL_COLOR_BUFFER_BIT);

    gl.enable(gl.c.GL_BLEND) catch {};
    gl.blendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA) catch {};
}

pub fn endFrame(_: *Context) !void {}

pub fn initImGuiBackend(ctx: *Context) !void {
    if (!ig.ImGui_ImplSDL3_InitForOpenGL(ctx.window, ctx.renderer)) {
        std.log.err("ImGui_ImplOpenGL3_Init failed", .{});
        return Renderer.Error.InitializationFailed;
    }

    if (!ig.ImGui_ImplOpenGL3_Init("#version 330")) {
        std.log.err("ImGui_ImplOpenGL3_Init failed", .{});
        return Renderer.Error.InitializationFailed;
    }

    std.log.info("ImGui GL Renderer Backend Initialized.", .{});
}

pub fn deinitImGuiBackend() void {
    ig.ImGui_ImplOpenGL3_Shutdown();
}

pub fn newImGuiFrame() void {
    ig.ImGui_ImplOpenGL3_NewFrame();
    ig.ImGui_ImplSDL3_NewFrame();
}

pub fn renderImGui(draw_data: *ig.c.ImDrawData) void {
    ig.ImGui_ImplOpenGL3_RenderDrawData(draw_data);
}

pub fn render(ctx: *Context, _: ig.c.ImVec4) void {
    const draw_data = ig.igGetDrawData();
    if (draw_data) |data| {
        if (data.Valid and data.CmdListsCount > 0) {
            renderImGui(data);
        }
    }

    _ = sdl.c.SDL_GL_SwapWindow(ctx.window);

    const io = ig.c.igGetIO().?;
    if ((io.*.ConfigFlags & ig.c.ImGuiConfigFlags_ViewportsEnable) != 0) {
        const backup_win = sdl.c.SDL_GL_GetCurrentWindow();
        const backup_ctx = sdl.c.SDL_GL_GetCurrentContext();
        ig.c.igUpdatePlatformWindows();
        ig.c.igRenderPlatformWindowsDefault();
        _ = sdl.c.SDL_GL_MakeCurrent(backup_win, backup_ctx);
    }
}

pub fn resize(_: *anyopaque, w: i32, h: i32) !void {
    gl.viewport(0, 0, w, h);
}

pub fn setVSync(_: *Context, on: bool) !void {
    try sdl.errify(sdl.c.SDL_GL_SetSwapInterval(if (on) 1 else 0));
}

pub fn loadTexture(_: *Context, path: []const u8) !BackendTexture {
    const surface = sdl.c.IMG_Load(path.ptr);
    if (surface == null) return Renderer.Error.InitializationFailed;

    const texture = try gl.Texture.create();

    const binding = try texture.bind(.@"2D");
    defer binding.unbind();

    try binding.parameter(.MinFilter, gl.c.GL_LINEAR_MIPMAP_LINEAR);
    try binding.parameter(.MagFilter, gl.c.GL_LINEAR);
    try binding.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
    try binding.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);

    const format = switch (surface.*.format) {
        sdl.c.SDL_PIXELFORMAT_RGB24 => blk: {
            std.log.debug("RGB24", .{});
            break :blk gl.Texture.Format.rgb;
        },
        sdl.c.SDL_PIXELFORMAT_RGBA32 => blk: {
            std.log.debug("RGBA32", .{});
            break :blk gl.Texture.Format.rgba;
        },
        else => blk: {
            std.log.debug("default", .{});
            break :blk gl.Texture.Format.bgra;
        }, // Default
    };

    std.log.debug("Format: {d}", .{format});

    try errors.errifyGL(binding.image2D(
        0, // level (0 = base)
        .rgba, // internal format
        surface.*.w, // width
        surface.*.h, // height
        0, // border (must be 0)
        format, // format
        .UnsignedByte, // data type
        surface.*.pixels, // pixel data
    ));

    binding.generateMipmap();

    return BackendTexture{
        .texture = texture,
        .width = @intCast(surface.*.w),
        .height = @intCast(surface.*.h),
    };
}

pub fn destroyTexture(tex: Texture) void {
    tex.destroy();
}

pub fn renderSpriteInstances(
    ctx: *Context,
    backend_tex: BackendTexture,
    instances: []const SpriteInstance,
) !void {
    if (instances.len == 0) return;

    const texture = backend_tex.texture;

    const pbind = try ctx.shader_program.use();
    defer pbind.unbind();

    const vbind = try ctx.quad_vao.bind();
    defer vbind.unbind();

    try Texture.active(gl.c.GL_TEXTURE0);
    const tbind = try texture.bind(.@"2D");
    defer tbind.unbind();

    try ctx.shader_program.setUniform("tex", 0);

    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSizeInPixels(ctx.window, &w, &h);
    const fw = @as(f32, @floatFromInt(w));
    const fh = @as(f32, @floatFromInt(h));

    const n = instances.len;
    try ctx.vertices.ensureTotalCapacity(n * 6);
    ctx.vertices.clearRetainingCapacity();

    for (instances) |instance| {
        const pos_x = instance.transform[3]; // 4th column, 1st row (m03)
        const pos_y = instance.transform[7]; // 4th column, 2nd row (m13)

        const scale_x = @sqrt(instance.transform[0] * instance.transform[0] + instance.transform[4] * instance.transform[4]);
        const scale_y = @sqrt(instance.transform[1] * instance.transform[1] + instance.transform[5] * instance.transform[5]);

        const base_size = 32.0;
        const rect_x = pos_x;
        const rect_y = pos_y;
        const rect_w = base_size * scale_x;
        const rect_h = base_size * scale_y;

        const x0 = rect_x / fw * 2.0 - 1.0;
        const y0 = 1.0 - rect_y / fh * 2.0;
        const x1 = (rect_x + rect_w) / fw * 2.0 - 1.0;
        const y1 = 1.0 - (rect_y + rect_h) / fh * 2.0;

        const u_0 = 0.0;
        const v_0 = 0.0;
        const u_1 = 1.0;
        const v_1 = 1.0;

        try ctx.vertices.append(.{ x0, y0, u_0, v_0 });
        try ctx.vertices.append(.{ x1, y0, u_1, v_0 });
        try ctx.vertices.append(.{ x1, y1, u_1, v_1 });
        try ctx.vertices.append(.{ x0, y0, u_0, v_0 });
        try ctx.vertices.append(.{ x1, y1, u_1, v_1 });
        try ctx.vertices.append(.{ x0, y1, u_0, v_1 });
    }

    const b = try ctx.quad_vbo.bind(.array);
    defer b.unbind();

    const required_size = @sizeOf(BatchedVertex) * ctx.vertices.items.len;
    try b.setDataNullManual(required_size, .dynamic_draw);
    try b.setSubData(0, ctx.vertices.items);
    try gl.drawArrays(gl.c.GL_TRIANGLES, 0, @intCast(ctx.vertices.items.len));
}

/// TODO: Implement SDF-based circle rendering shaders
pub fn renderCircleInstances(
    ctx: *Context,
    instances: []const CircleInstance,
) !void {
    _ = ctx;
    _ = instances;
}

/// TODO: Implement instanced line rendering with geometry shaders
pub fn renderLineInstances(
    ctx: *Context,
    instances: []const LineInstance,
) !void {
    if (instances.len == 0) return;
    _ = ctx;

    try gl.enable(gl.c.GL_BLEND);
    try gl.blendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);
}

/// TODO: Implement SDF-based rectangle rendering shaders
pub fn renderRectInstances(
    ctx: *Context,
    instances: []const RectInstance,
) !void {
    if (instances.len == 0) return;

    try gl.enable(gl.c.GL_BLEND);
    try gl.blendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    for (instances) |instance| {
        const x0 = instance.position[0];
        const y0 = instance.position[1];
        const x1 = instance.position[0] + instance.size[0];
        const y1 = instance.position[1] + instance.size[1];

        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.c.SDL_GetWindowSizeInPixels(ctx.window, &w, &h);
        const fw = @as(f32, @floatFromInt(w));
        const fh = @as(f32, @floatFromInt(h));

        const nx0 = x0 / fw * 2.0 - 1.0;
        const ny0 = 1.0 - y0 / fh * 2.0;
        const nx1 = x1 / fw * 2.0 - 1.0;
        const ny1 = 1.0 - y1 / fh * 2.0;

        _ = nx0;
        _ = ny0;
        _ = nx1;
        _ = ny1;
    }
}
