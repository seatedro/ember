const std = @import("std");

const cimgui = @import("cimgui");
const sdl = @import("sdl");
const cimgui_sdl3 = @import("cimgui_sdl3");
const cimgui_sdlrenderer3 = @import("cimgui_sdlrenderer3");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;

pub fn main() !void {
    if (sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO) != 0) {
        std.log.err("SDL_Init Error: {s}\n", .{sdl.c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer sdl.c.SDL_Quit();

    const window_flags = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_ALLOW_HIGHDPI;
    const window = sdl.c.SDL_CreateWindow(
        "Ember - ImGui SDL3 Demo",
        WIN_WIDTH,
        WIN_HEIGHT,
        window_flags,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow Error: {s}\n", .{sdl.c.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    }
    defer sdl.c.SDL_DestroyWindow(window);

    const renderer_flags = sdl.c.SDL_RENDERER_PRESENTVSYNC | sdl.c.SDL_RENDERER_ACCELERATED;
    var renderer = sdl.c.SDL_CreateRenderer(window, null, renderer_flags);
    if (renderer == null) {
        std.log.err("SDL_CreateRenderer Error: {s}\n", .{sdl.c.SDL_GetError()});
        return error.SDLRendererCreationFailed;
    }
    defer sdl.c.SDL_DestroyRenderer(renderer);

    _ = cimgui.igCreateContext(null);
    defer cimgui.igDestroyContext(null);

    cimgui.igStyleColorsDark(null);

    const io = cimgui.igGetIO();
    io.*.ConfigFlags |= cimgui.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigFlags |= cimgui.ImGuiConfigFlags_ViewportsEnable; // If using multi-viewports

    if (!cimgui_sdl3.ImGui_ImplSDL3_InitForSDLRenderer(window, renderer)) {
        std.log.err("ImGui_ImplSDL3_InitForSDLRenderer failed\n", .{});
        return error.ImGuiBackendInitFailed;
    }
    defer cimgui_sdl3.ImGui_ImplSDL3_Shutdown();

    if (!cimgui_sdlrenderer3.ImGui_ImplSDLRenderer3_Init(renderer)) {
        std.log.err("ImGui_ImplSDLRenderer3_Init failed\n", .{});
    }
    defer cimgui_sdlrenderer3.ImGui_ImplSDLRenderer3_Shutdown();

    // --- Main Loop ---
    var running = true;
    var event: sdl.c.SDL_Event = undefined;
    const clear_color = cimgui.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };
    var show_demo_window: bool = true;

    while (running) {
        while (sdl.c.SDL_PollEvent(&event) != 0) {
            _ = cimgui_sdl3.ImGui_ImplSDL3_ProcessEvent(&event);

            switch (event.type) {
                sdl.c.SDL_EVENT_QUIT => {
                    running = false;
                },
                sdl.c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (event.window.windowID == sdl.c.SDL_GetWindowID(window)) {
                        running = false;
                    }
                },
                else => {},
            }
        } // End event loop

        cimgui_sdlrenderer3.ImGui_ImplSDLRenderer3_NewFrame();
        cimgui_sdl3.ImGui_ImplSDL3_NewFrame();
        cimgui.igNewFrame();

        // --- ImGui Content ---
        if (show_demo_window) {
            cimgui.igShowDemoWindow(&show_demo_window);
        }

        cimgui.igRender();

        _ = sdl.c.SDL_SetRenderDrawColor(
            renderer,
            @intFromFloat(clear_color.x * 255.0),
            @intFromFloat(clear_color.y * 255.0),
            @intFromFloat(clear_color.z * 255.0),
            @intFromFloat(clear_color.w * 255.0),
        );
        _ = sdl.c.SDL_RenderClear(renderer);

        cimgui_sdlrenderer3.ImGui_ImplSDLRenderer3_RenderDrawData(cimgui.igGetDrawData());

        sdl.c.SDL_RenderPresent(renderer);
    } // End main loop
}
