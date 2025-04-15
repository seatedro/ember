// File: vendor/cimgui/main.zig
const std = @import("std");
// Import the sibling sdl module
const sdl = @import("sdl");

// Define specific errors for ImGui operations
pub const Error = error{
    ContextCreationFailed,
    BackendInitFailed,
    RendererInitFailed,
};

// Import C definitions for ImGui core
pub const c = @cImport({
    @cInclude("cimgui.h");
    // We don't need SDL headers here if sdl.zig provides them via its 'c' export
});

// Typedefs for convenience (matching C types)
pub const ImVec4 = c.ImVec4;
pub const ImGuiIO = c.ImGuiIO;
pub const WindowFlags = c.ImGuiWindowFlags;

// --- Extern "C" Declarations ---
// These declare the signatures of the C/C++ functions we link against.

pub extern fn igCreateContext(shared_font_atlas: ?*c.ImFontAtlas) ?*c.ImGuiContext;
pub extern fn igDestroyContext(ctx: ?*c.ImGuiContext) void;
pub extern fn igGetIO() ?*c.ImGuiIO;
pub extern fn igStyleColorsDark(dst: ?*c.ImGuiStyle) void;
pub extern fn igNewFrame() void;
pub extern fn igRender() void;
pub extern fn igGetDrawData() ?*c.ImDrawData;
pub extern fn igShowDemoWindow(p_open: ?*bool) void;
pub extern fn igBegin(name: [*c]const u8, p_open: ?*bool, flags: c.ImGuiWindowFlags) bool;
pub extern fn igEnd() void;
pub extern fn igText(fmt: [*c]const u8, ...) void;
pub extern fn igCheckbox(label: [*c]const u8, v: *bool) bool;
pub extern fn igSliderFloat(label: [*c]const u8, v: *f32, v_min: f32, v_max: f32) bool;
pub extern fn igColorEdit3(label: [*c]const u8, col: *f32, flags: c.ImGuiColorEditFlags) bool;
pub extern fn igButton(label: [*c]const u8) bool;
pub extern fn igSameLine() void;

// SDL3 Platform Backend Functions (using types from the imported sdl module)
pub extern fn ImGui_ImplSDL3_InitForSDLRenderer(
    window: ?*sdl.c.SDL_Window,
    renderer: ?*sdl.c.SDL_Renderer,
) callconv(.C) bool;
pub extern fn ImGui_ImplSDL3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDL3_ProcessEvent(event: *const sdl.c.SDL_Event) callconv(.C) bool;
pub extern fn ImGui_ImplSDL3_NewFrame() callconv(.C) void;

// SDL_Renderer Backend Functions (using types from the imported sdl module)
pub extern fn ImGui_ImplSDLRenderer3_Init(renderer: ?*sdl.c.SDL_Renderer) callconv(.C) bool;
pub extern fn ImGui_ImplSDLRenderer3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_NewFrame() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_RenderDrawData(
    draw_data: ?*c.ImDrawData,
) callconv(.C) void;
