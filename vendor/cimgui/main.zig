const std = @import("std");
const sdl = @import("sdl").c;

// Import the core cimgui types and functions (ig*) from cimgui.h
pub const c = @cImport({
    @cInclude("cimgui.h");
});

// --- Extern Function Declarations for Backends ---
// These tell Zig the *signature* of the C++ functions compiled into
// the static library by vendor/cimgui/build.zig.
// The actual implementation will be linked later.

// SDL3 Platform Backend Functions
pub extern fn ImGui_ImplSDL3_InitForSDLRenderer(
    window: ?*sdl.SDL_Window,
    renderer: ?*sdl.SDL_Renderer,
) callconv(.C) bool;
pub extern fn ImGui_ImplSDL3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDL3_ProcessEvent(event: *const sdl.SDL_Event) callconv(.C) bool;
pub extern fn ImGui_ImplSDL3_NewFrame() callconv(.C) void;

// SDL_Renderer Backend Functions
pub extern fn ImGui_ImplSDLRenderer3_Init(renderer: ?*sdl.SDL_Renderer) callconv(.C) bool;
pub extern fn ImGui_ImplSDLRenderer3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_NewFrame() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_RenderDrawData(
    draw_data: ?*c.ImDrawData,
) callconv(.C) void;

// Add extern declarations for other backend functions if you use them

test "basic extern declarations" {
    // This test just ensures the declarations compile, not that they link.
    _ = ImGui_ImplSDL3_InitForSDLRenderer;
    _ = ImGui_ImplSDL3_Shutdown;
    _ = ImGui_ImplSDL3_ProcessEvent;
    _ = ImGui_ImplSDL3_NewFrame;
    _ = ImGui_ImplSDLRenderer3_Init;
    _ = ImGui_ImplSDLRenderer3_Shutdown;
    _ = ImGui_ImplSDLRenderer3_NewFrame;
    _ = ImGui_ImplSDLRenderer3_RenderDrawData;
    try std.testing.expect(true); // Placeholder assertion
}
