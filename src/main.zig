const std = @import("std");
const cimgui = @import("cimgui");
const sdl = @import("sdl");

const rendering = @import("rendering/renderer.zig");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try sdl.errify(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    defer sdl.c.SDL_Quit();

    const backend = rendering.BackendType.SDL;

    var window_flags = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_HIDDEN;
    if (backend == .OpenGL) {
        // Example: Add OpenGL flag if needed by that backend's init
        window_flags |= sdl.c.SDL_WINDOW_OPENGL;
        // --- TODO: Set SDL_GL_SetAttribute BEFORE CreateWindow for OpenGL ---
        // Example:
        // try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_MAJOR_VERSION, 3));
        // try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_MINOR_VERSION, 3));
        // try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_CONTEXT_PROFILE_MASK, sdl.c.SDL_GL_CONTEXT_PROFILE_CORE));
        std.log.warn("OpenGL backend selected - Ensure necessary SDL_GL attributes are set BEFORE window creation if required.", .{});
    }

    const window = sdl.c.SDL_CreateWindow(
        "Ember Engine",
        WIN_WIDTH,
        WIN_HEIGHT,
        window_flags,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow failed: {s}", .{sdl.c.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    }
    defer sdl.c.SDL_DestroyWindow(window);

    try sdl.errify(sdl.c.SDL_SetWindowPosition(
        window,
        sdl.c.SDL_WINDOWPOS_CENTERED,
        sdl.c.SDL_WINDOWPOS_CENTERED,
    ));
    try sdl.errify(sdl.c.SDL_ShowWindow(window));

    // Setup Dear ImGui context
    const ig_context = cimgui.c.igCreateContext(null); // Store the returned context pointer
    if (ig_context == null) {
        // Check if context creation failed
        std.log.err("Failed to create ImGui context!", .{});
        sdl.c.SDL_DestroyWindow(window);
        sdl.c.SDL_Quit();
        return error.ImGuiContextCreationFailed;
    }
    defer cimgui.c.igDestroyContext(ig_context);

    const io = cimgui.c.igGetIO();
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableGamepad;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_ViewportsEnable;

    cimgui.c.igStyleColorsDark(null);

    defer cimgui.ImGui_ImplSDL3_Shutdown();
    // Create renderer
    var renderer_ctx = rendering.createRenderer(backend, window.?, allocator) catch {
        cimgui.c.igDestroyContext(ig_context);
        sdl.c.SDL_DestroyWindow(window);
        sdl.c.SDL_Quit();
        return error.InitializationFailed;
    };

    defer renderer_ctx.deinit();

    try renderer_ctx.initImGuiBackend();
    defer renderer_ctx.deinitImGuiBackend();

    try renderer_ctx.setVSync(true);

    // State
    var show_demo_window: bool = true;
    var show_another_window: bool = false;
    var clear_color = cimgui.c.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    var done = false;
    var event: sdl.c.SDL_Event = undefined;

    while (!done) {
        while (sdl.c.SDL_PollEvent(&event)) {
            _ = cimgui.ImGui_ImplSDL3_ProcessEvent(&event);
            switch (event.type) {
                sdl.c.SDL_EVENT_QUIT => done = true,
                sdl.c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (event.window.windowID == sdl.c.SDL_GetWindowID(window)) {
                        done = true;
                    }
                },
                else => {},
            }
        }

        // Minimized? Sleep and skip frame
        if ((sdl.c.SDL_GetWindowFlags(window) & sdl.c.SDL_WINDOW_MINIMIZED) != 0) {
            sdl.c.SDL_Delay(10);
            continue;
        }

        cimgui.ImGui_ImplSDL3_NewFrame();
        renderer_ctx.newImGuiFrame();
        cimgui.c.igNewFrame();

        if (show_demo_window) {
            cimgui.igShowDemoWindow(&show_demo_window);
        }

        {
            var f: f32 = 0.0;
            var counter: i32 = 0;

            if (cimgui.c.igBegin("Hello, world!", null, 0)) {
                cimgui.c.igText("This is some useful text.");
                _ = cimgui.c.igCheckbox("Demo Window", &show_demo_window);
                _ = cimgui.c.igCheckbox("Another Window", &show_another_window);
                _ = cimgui.c.igSliderFloat("float", &f, 0.0, 1.0);
                _ = cimgui.c.igColorEdit3("clear color", &clear_color.x, 0);

                if (cimgui.c.igButton("Button")) {
                    counter += 1;
                }
                cimgui.c.igSameLine();
                cimgui.c.igText("counter = %d", counter);

                cimgui.c.igText(
                    "Application average %.3f ms/frame (%.1f FPS)",
                    1000.0 / io.*.Framerate,
                    io.*.Framerate,
                );
            }
            cimgui.c.igEnd();
        }

        if (show_another_window) {
            if (cimgui.c.igBegin("Another Window", &show_another_window, 0)) {
                cimgui.c.igText("Hello from another window!");
                if (cimgui.c.igButton("Close Me")) {
                    show_another_window = false;
                }
            }
            cimgui.c.igEnd();
        }

        // Rendering
        cimgui.c.igRender();
        const draw_data = cimgui.igGetDrawData();
        // SDL_RenderSetScale(renderer, io.*.DisplayFramebufferScale.x, io.*.DisplayFramebufferScale.y);
        try renderer_ctx.beginFrame(clear_color);

        if (draw_data) |data| { // Check draw_data is not null
            if (data.Valid and data.CmdListsCount > 0) {
                renderer_ctx.renderImGui(data);
            }
        } else {
            std.log.warn("ImGui draw data was null!", .{});
        }

        // This does nothing if the backend doesn't support it.
        // So far sdlrenderer3 does not support multi-viewports.
        if ((io.*.ConfigFlags & cimgui.c.ImGuiConfigFlags_ViewportsEnable) != 0) {
            cimgui.c.igUpdatePlatformWindows();
            cimgui.c.igRenderPlatformWindowsDefault();
        }

        try renderer_ctx.endFrame();
    }
}
