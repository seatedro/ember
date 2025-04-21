const std = @import("std");
const sdl = @import("sdl");
const ig = @import("cimgui");
const Renderer = @import("../renderer.zig");
const gl = @import("opengl");
const glad = gl.glad;
const Buffer = gl.Buffer;
const Shader = gl.Shader;
const Program = gl.Program;
const VertexArray = gl.VertexArray;
pub const Texture = gl.Texture;

pub const Context = struct {
    renderer: sdl.c.SDL_GLContext,
    window: *sdl.c.SDL_Window,
    shader_program: Program,
    quad_vao: VertexArray,
    quad_vbo: Buffer,
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

    // Enable VSYNC by default (overwrite via setVSync later)
    _ = sdl.c.SDL_GL_SetSwapInterval(1);

    // Compile and link shader program for textured quad
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

    // Create shader program using our abstractions
    const program = try Program.createVF(vert_src, frag_src);
    errdefer program.destroy();

    // Create and setup VAO
    const vao = try VertexArray.create();
    errdefer vao.destroy();

    // Create and setup VBO
    const vbo = try Buffer.create();
    errdefer vbo.destroy();

    // Setup buffers and attributes
    {
        const vao_binding = try vao.bind();
        defer vao_binding.unbind();

        const vbo_binding = try vbo.bind(.array);
        defer vbo_binding.unbind();

        // Allocate buffer for 6 vertices of vec4 (pos.xy, uv.xy)
        try vbo_binding.setDataNullManual(@sizeOf([6][4]f32), .dynamic_draw);

        // position attribute
        try vbo_binding.attributeAdvanced(0, 2, gl.c.GL_FLOAT, false, 4 * @sizeOf(f32), 0);
        try vbo_binding.enableAttribArray(0);

        // uv attribute
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
    };

    return ctx;
}

pub fn deinit(allocator: std.mem.Allocator, ctx: *Context) void {
    std.log.info("Deinitializing GL Renderer...", .{});
    if (ctx.renderer) |r| {
        _ = sdl.c.SDL_GL_DestroyContext(r);
    }
    ig.ImGui_ImplOpenGL3_Shutdown();
    allocator.destroy(ctx);
    std.log.info("Deinitialized GL Renderer.", .{});
}

pub fn beginFrame(_: *Context, clr: ig.c.ImVec4) Renderer.Error!void {
    gl.clearColor(clr.x, clr.y, clr.z, clr.w);
    gl.clear(gl.c.GL_COLOR_BUFFER_BIT);
}

pub fn endFrame(ctx: *Context) Renderer.Error!void {
    _ = sdl.c.SDL_GL_SwapWindow(ctx.window);
}

pub fn initImGuiBackend(ctx: *Context) Renderer.Error!void {
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

pub fn renderImGui(_: *Context, draw: *ig.c.ImDrawData) void {
    ig.ImGui_ImplOpenGL3_RenderDrawData(draw);
}

pub fn resize(_: *anyopaque, w: i32, h: i32) Renderer.Error!void {
    gl.viewport(0, 0, w, h);
}

pub fn setVSync(_: *anyopaque, on: bool) Renderer.Error!void {
    _ = sdl.c.SDL_GL_SetSwapInterval(if (on) 1 else 0);
}

pub fn loadTexture(_: *Context, path: []const u8) !Texture {
    const surface = sdl.c.IMG_Load(path.ptr);
    if (surface == null) return Renderer.Error.InitializationFailed;

    // Create a new OpenGL texture
    const texture = try gl.Texture.create();

    // Bind the texture for setup
    const binding = try texture.bind(.@"2D");
    defer binding.unbind();

    // Set texture parameters
    try binding.parameter(.MinFilter, gl.c.GL_LINEAR_MIPMAP_LINEAR);
    try binding.parameter(.MagFilter, gl.c.GL_LINEAR);
    try binding.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
    try binding.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);

    // Define the format based on SDL surface format
    const format = switch (surface.*.format) {
        sdl.c.SDL_PIXELFORMAT_RGB24 => gl.Texture.Format.rgb,
        sdl.c.SDL_PIXELFORMAT_RGBA32 => gl.Texture.Format.rgba,
        else => gl.Texture.Format.rgba, // Default
    };

    // Upload pixels to the texture
    try binding.image2D(
        0, // level (0 = base)
        .rgba, // internal format
        surface.*.w, // width
        surface.*.h, // height
        0, // border (must be 0)
        format, // format
        .UnsignedByte, // data type
        surface.*.pixels, // pixel data
    );

    // Generate mipmaps
    binding.generateMipmap();

    // Return the texture ID
    return texture;
}

pub fn destroyTexture(tex: Texture) void {
    tex.destroy();
}

pub fn drawTexture(
    ctx: *Context,
    tex: Texture,
    srcRect: ?Renderer.Rect,
    dstRect: Renderer.Rect,
) !void {
    // Use program binding
    const program_binding = try ctx.shader_program.use();
    defer program_binding.unbind();

    // Bind VAO
    const vao_binding = try ctx.quad_vao.bind();
    defer vao_binding.unbind();

    // Bind texture to unit 0
    try Texture.active(gl.c.GL_TEXTURE0);
    const tex_binding = try tex.bind(.@"2D");
    defer tex_binding.unbind();

    // Set sampler uniform
    try ctx.shader_program.setUniform("tex", 0);

    // Compute normalized window coords
    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.c.SDL_GetWindowSizeInPixels(ctx.window, &w, &h);
    const fw = @as(f32, @floatFromInt(w));
    const fh = @as(f32, @floatFromInt(h));

    const x0 = dstRect.x / fw * 2.0 - 1.0;
    const y0 = 1.0 - dstRect.y / fh * 2.0;
    const x1 = (dstRect.x + dstRect.w) / fw * 2.0 - 1.0;
    const y1 = 1.0 - (dstRect.y + dstRect.h) / fh * 2.0;

    // Calculate texture coordinates based on source rectangle
    const u_0: f32 = 0.0;
    const v_0: f32 = 0.0;
    const u_1: f32 = 1.0;
    const v_1: f32 = 1.0;

    // If srcRect is provided, calculate normalized texture coordinates
    // This would require knowing texture dimensions to implement correctly
    if (srcRect) |src| {
        // TODO: For proper implementation, we need the texture dimensions
        // For now, we'll just use full texture coordinates
        _ = src;
    }

    const verts = [6][4]f32{
        .{ x0, y0, u_0, v_0 },
        .{ x1, y0, u_1, v_0 },
        .{ x1, y1, u_1, v_1 },
        .{ x0, y0, u_0, v_0 },
        .{ x1, y1, u_1, v_1 },
        .{ x0, y1, u_0, v_1 },
    };

    // Update quad vertex buffer
    const vbo_binding = try ctx.quad_vbo.bind(.array);
    defer vbo_binding.unbind();
    try vbo_binding.setSubData(0, &verts);

    // Draw the quad
    try gl.drawArrays(gl.c.GL_TRIANGLES, 0, 6);

    return;
}
