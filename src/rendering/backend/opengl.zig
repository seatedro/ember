const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const Renderer = @import("../renderer.zig");
const resource = @import("../../core/resource.zig");
const TextureAtlas = @import("../../core/atlas.zig").TextureAtlas;
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

// Updated vertex format that includes color
pub const BatchedVertex = struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
pub const Context = struct {
    renderer: sdl.c.SDL_GLContext,
    window: *sdl.c.SDL_Window,
    shader_program: Program,
    quad_vao: VertexArray,
    quad_vbo: Buffer,
    quad_ebo: Buffer,
    vertices: std.ArrayList(BatchedVertex),

    atlas_tex: ?Texture = null,
};

pub fn init(allocator: std.mem.Allocator, window: *sdl.c.SDL_Window) !Context {
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
        \\layout(location = 2) in vec4 inColor;
        \\out vec2 uv;
        \\out vec4 color;
        \\void main() {
        \\    uv = inUV;
        \\    color = inColor;
        \\    gl_Position = vec4(inPos, 0.0, 1.0);
        \\}
    ;
    const frag_src =
        \\#version 330 core
        \\in vec2 uv;
        \\in vec4 color;
        \\out vec4 fragColor;
        \\uniform sampler2D tex;
        \\void main() {
        \\    fragColor = color * texture(tex, uv);
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

    const ebo = try Buffer.create();
    errdefer ebo.destroy();

    {
        const vao_binding = try vao.bind();
        defer vao_binding.unbind();

        const vbo_binding = try vbo.bind(.array);
        defer vbo_binding.unbind();

        try vbo_binding.setDataNullManual(@sizeOf([6]BatchedVertex), .dynamic_draw);

        // Position attribute (location 0)
        try vbo_binding.attributeAdvanced(0, 2, gl.c.GL_FLOAT, false, @sizeOf(BatchedVertex), @offsetOf(BatchedVertex, "position"));
        try vbo_binding.enableAttribArray(0);

        // UV attribute (location 1)
        try vbo_binding.attributeAdvanced(1, 2, gl.c.GL_FLOAT, false, @sizeOf(BatchedVertex), @offsetOf(BatchedVertex, "uv"));
        try vbo_binding.enableAttribArray(1);

        // Color attribute (location 2)
        try vbo_binding.attributeAdvanced(2, 4, gl.c.GL_FLOAT, false, @sizeOf(BatchedVertex), @offsetOf(BatchedVertex, "color"));
        try vbo_binding.enableAttribArray(2);
    }

    return Context{
        .window = window,
        .renderer = gl_ctx,
        .shader_program = program,
        .quad_vao = vao,
        .quad_vbo = vbo,
        .quad_ebo = ebo,
        .vertices = vertices,
    };
}

pub fn deinit(ctx: *Context) void {
    std.log.info("Deinitializing GL Renderer...", .{});
    if (ctx.renderer) |r| {
        _ = sdl.c.SDL_GL_DestroyContext(r);
    }
    ctx.vertices.deinit();
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

pub fn render(ctx: *Context, _: ig.c.ImVec4, dl: *Renderer.DrawList) !void {
    const draw_data = ig.igGetDrawData();
    if (draw_data) |data| {
        if (data.Valid and data.CmdListsCount > 0) {
            renderImGui(data);
        }
    }

    try renderDrawList(ctx, dl);

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
    try errors.errifyGL(gl.viewport(0, 0, w, h));
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

pub fn syncAtlas(ctx: *Context, atlas: *TextureAtlas) !void {
    if (!atlas.dirty) return;

    if (ctx.atlas_tex == null) {
        const texture = try gl.Texture.create();

        const binding = try texture.bind(.@"2D");
        defer binding.unbind();

        try binding.parameter(.MinFilter, gl.c.GL_LINEAR);
        try binding.parameter(.MagFilter, gl.c.GL_LINEAR);
        try binding.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
        try binding.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);

        try errors.errifyGL(binding.image2D(
            0, // level (0 = base)
            .rgba, // internal format
            @intCast(atlas.width), // width
            @intCast(atlas.height), // height
            0, // border (must be 0)
            .rgba, // format
            .UnsignedByte,
            atlas.pixels.ptr, // pixel data
        ));

        binding.generateMipmap();
        ctx.atlas_tex = texture;
    }

    atlas.dirty = false;
}

pub fn renderDrawList(ctx: *Context, dl: *Renderer.DrawList) !void {
    if (dl.cmd_buffer.items.len == 0) return;

    var window_w: c_int = 0;
    var window_h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSize(ctx.window, &window_w, &window_h);

    const width = @as(f32, @floatFromInt(window_w));
    const height = @as(f32, @floatFromInt(window_h));

    if (width == 0.0 or height == 0.0) return; // Avoid division by zero

    const commands = dl.cmd_buffer.items;
    const vs_ptr = dl.vtx_buffer.items;
    const is_ptr = dl.idx_buffer.items;

    if (vs_ptr.len == 0 or is_ptr.len == 0) return;

    var gl_vertices = std.ArrayList(BatchedVertex).init(ctx.vertices.allocator);
    defer gl_vertices.deinit();

    try gl_vertices.ensureTotalCapacity(vs_ptr.len);
    for (vs_ptr) |drawvert| {
        const color_u32 = drawvert.color;
        const color_f32 = [4]f32{
            @as(f32, @floatFromInt(color_u32 & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 8) & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 16) & 0xFF)) / 255.0,
            @as(f32, @floatFromInt((color_u32 >> 24) & 0xFF)) / 255.0,
        };

        const ndc_x = (drawvert.pos[0] / width) * 2.0 - 1.0;
        const ndc_y = 1.0 - (drawvert.pos[1] / height) * 2.0; // Flip Y coordinate

        gl_vertices.appendAssumeCapacity(BatchedVertex{
            .position = [2]f32{ ndc_x, ndc_y },
            .uv = [2]f32{ drawvert.uv[0], drawvert.uv[1] },
            .color = color_f32,
        });
    }

    const vao_binding = try ctx.quad_vao.bind();
    defer vao_binding.unbind();

    // Upload vertex data
    const b = try ctx.quad_vbo.bind(.array);
    defer b.unbind();

    const required_size = @sizeOf(BatchedVertex) * gl_vertices.items.len;
    try b.setDataNullManual(required_size, .dynamic_draw);
    try b.setSubData(0, gl_vertices.items);

    // Upload index data
    const ebo_binding = try ctx.quad_ebo.bind(.element_array);
    defer ebo_binding.unbind();

    try ebo_binding.setDataNullManual(4 * is_ptr.len, .dynamic_draw);
    try ebo_binding.setSubData(0, is_ptr);

    const program_binding = try ctx.shader_program.use();
    defer program_binding.unbind();

    for (commands) |cmd| {
        if (cmd.user_callback != null or cmd.elem_count == 0) continue;

        try Texture.active(gl.c.GL_TEXTURE0);
        var binding: ?gl.Texture.Binding = null;
        if (cmd.texture_id) |texture_id| {
            const backend_tex: *const BackendTexture = @ptrCast(@alignCast(texture_id));
            binding = try backend_tex.texture.bind(.@"2D");
        } else if (ctx.atlas_tex) |atlas_tex| {
            binding = try atlas_tex.bind(.@"2D");
        } else {
            continue;
        }
        defer if (binding != null) binding.?.unbind();

        try ctx.shader_program.setUniform("tex", 0);

        const offset_bytes = cmd.idx_offset * @sizeOf(u32);
        try gl.drawElements(
            gl.c.GL_TRIANGLES,
            @intCast(cmd.elem_count),
            gl.c.GL_UNSIGNED_INT,
            offset_bytes,
        );
    }
}
