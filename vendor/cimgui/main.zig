const std = @import("std");
const sdl = @import("sdl");

pub const Error = error{
    ContextCreationFailed,
    BackendInitFailed,
    RendererInitFailed,
};

pub const c = @cImport({
    @cInclude("cimgui.h");
});

pub const ImVec4 = c.ImVec4;
pub const ImGuiIO = c.ImGuiIO;
pub const WindowFlags = c.ImGuiWindowFlags;

// cimgui
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

// SDL3 Platform
pub extern fn ImGui_ImplSDL3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDL3_ProcessEvent(event: *const sdl.c.SDL_Event) callconv(.C) bool;
pub extern fn ImGui_ImplSDL3_NewFrame() callconv(.C) void;

// SDL_Renderer3
pub extern fn ImGui_ImplSDL3_InitForSDLRenderer(
    window: ?*sdl.c.SDL_Window,
    renderer: ?*sdl.c.SDL_Renderer,
) callconv(.C) bool;
pub extern fn ImGui_ImplSDLRenderer3_Init(renderer: ?*sdl.c.SDL_Renderer) callconv(.C) bool;
pub extern fn ImGui_ImplSDLRenderer3_Shutdown() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_NewFrame() callconv(.C) void;
pub extern fn ImGui_ImplSDLRenderer3_RenderDrawData(
    draw_data: ?*c.ImDrawData,
    renderer: ?*sdl.c.SDL_Renderer,
) callconv(.C) void;

// OpenGL
pub extern fn ImGui_ImplSDL3_InitForOpenGL(window: ?*sdl.c.SDL_Window, sdl_gl_context: sdl.c.SDL_GLContext) callconv(.C) bool;
pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: [*:0]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: ?*c.ImDrawData) void;
