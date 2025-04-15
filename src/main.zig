const std = @import("std");

const cimgui = @import("cimgui");
const sdl = @import("sdl");

const WIN_WIDTH = 1280;
const WIN_HEIGHT = 720;

/// Converts the return value of an SDL function to an error union.
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

pub fn main() !void {
    // Initialize SDL
    try errify(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    defer sdl.c.SDL_Quit();

    // Create window
    const window_flags = sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_HIDDEN;
    const window = sdl.c.SDL_CreateWindow(
        "Dear ImGui SDL3+SDL_Renderer example",
        WIN_WIDTH,
        WIN_HEIGHT,
        window_flags,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow failed: {s}", .{sdl.c.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    }
    defer sdl.c.SDL_DestroyWindow(window);

    // Create renderer
    const renderer = sdl.c.SDL_CreateRenderer(window, null);
    if (renderer == null) {
        std.log.err("SDL_CreateRenderer failed: {s}", .{sdl.c.SDL_GetError()});
        return error.SDLRendererCreationFailed;
    }
    defer sdl.c.SDL_DestroyRenderer(renderer);

    try errify(sdl.c.SDL_SetRenderVSync(renderer, 1));
    try errify(sdl.c.SDL_SetWindowPosition(
        window,
        sdl.c.SDL_WINDOWPOS_CENTERED,
        sdl.c.SDL_WINDOWPOS_CENTERED,
    ));
    try errify(sdl.c.SDL_ShowWindow(window));

    // Setup Dear ImGui context
    _ = cimgui.c.igCreateContext(null);
    defer cimgui.c.igDestroyContext(null);

    const io = cimgui.c.igGetIO();
    // io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableKeyboard;
    // io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_NavEnableGamepad;
    // io.*.ConfigFlags |= cimgui.c.ImGuiConfigFlags_DockingEnable;

    cimgui.c.igStyleColorsDark(null);

    // Setup Platform/Renderer backends
    if (!cimgui.ImGui_ImplSDL3_InitForSDLRenderer(window, renderer)) {
        std.log.err("ImGui_ImplSDL3_InitForSDLRenderer failed", .{});
        return error.ImGuiBackendInitFailed;
    }
    defer cimgui.ImGui_ImplSDL3_Shutdown();

    if (!cimgui.ImGui_ImplSDLRenderer3_Init(renderer)) {
        std.log.err("ImGui_ImplSDLRenderer3_Init failed", .{});
        return error.ImGuiRendererInitFailed;
    }
    defer cimgui.ImGui_ImplSDLRenderer3_Shutdown();

    // State
    var show_demo_window: bool = true;
    var show_another_window: bool = false;
    var clear_color = cimgui.c.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    var done = false;
    var event: sdl.c.SDL_Event = undefined;

    while (!done) {
        // Poll and handle events
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

        // Start the Dear ImGui frame
        cimgui.ImGui_ImplSDL3_NewFrame();
        cimgui.ImGui_ImplSDLRenderer3_NewFrame();
        cimgui.c.igNewFrame();

        // 1. Show the big demo window
        if (show_demo_window) {
            cimgui.c.igShowDemoWindow(&show_demo_window);
        }

        // 2. Show a simple window we create ourselves
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

        // 3. Show another simple window
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
        // SDL_RenderSetScale(renderer, io.*.DisplayFramebufferScale.x, io.*.DisplayFramebufferScale.y);
        try errify(sdl.c.SDL_SetRenderDrawColor(
            renderer,
            @intFromFloat(clear_color.x * 255.0),
            @intFromFloat(clear_color.y * 255.0),
            @intFromFloat(clear_color.z * 255.0),
            @intFromFloat(clear_color.w * 255.0),
        ));
        try errify(sdl.c.SDL_RenderClear(renderer));
        cimgui.ImGui_ImplSDLRenderer3_RenderDrawData(cimgui.c.igGetDrawData());
        try errify(sdl.c.SDL_RenderPresent(renderer));
    }
}
