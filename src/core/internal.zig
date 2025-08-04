const std = @import("std");
const b = @import("../build_config.zig");
const config = @import("config.zig");
const ember = @import("../ember.zig");
const Window = @import("window.zig");
const io = ember.io;
const sdl = ember.sdl;
const ig = ember.ig;
const BackendType = ember.BackendType;

const log = std.log.scoped(.context);

pub const Context = struct {
    const Self = @This();
    var debug_allocator = std.heap.DebugAllocator(.{}).init;

    allocator: std.mem.Allocator = undefined,
    cfg: config.Config = undefined,
    running: bool = true,
    renderer_ctx: ember.RendererCtx = undefined,
    backend: BackendType = b.renderer,
    window: Window = undefined,

    _imgui_io: *ig.ImGuiIO = undefined,

    _frame: u64 = 0,
    fps: f32 = 0,
    _tick_acc: u64 = 0,
    _tick_freq: u64 = 0,
    _tick_max: u64 = 0,
    _last_tick: u64 = 0,
    _last_stat_time: f32 = 0,
    _seconds: f32 = 0,
    dt: f32 = 0,

    pub fn init(cfg: config.Config) !*Self {
        const allocator = debug_allocator.allocator();
        var self = try allocator.create(Self);
        self.* = .{};
        self.allocator = allocator;
        self.cfg = cfg;

        try self.initWindow();
        try self.initImGui();
        try self.initRenderer();

        self._tick_freq = sdl.c.SDL_GetPerformanceFrequency();
        self._tick_max = self._tick_freq / 2;
        self._last_tick = sdl.c.SDL_GetPerformanceCounter();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.deinitRenderer();
        deinitImgui();
        self.deinitWindow();
        self.allocator.destroy(self);
        _ = debug_allocator.deinit();
    }

    pub fn initWindow(self: *Self) !void {
        const cfg = self.cfg;
        const rval = sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO);
        if (!rval) {
            log.err("SDL_Init failed: {s}", .{sdl.c.SDL_GetError()});
            return error.SdlError;
        }

        var flags: u32 = sdl.c.SDL_WINDOW_MOUSE_CAPTURE | sdl.c.SDL_WINDOW_MOUSE_FOCUS;
        if (cfg.window_borderless) {
            flags |= sdl.c.SDL_WINDOW_BORDERLESS;
        }
        if (cfg.window_highdpi) {
            flags |= sdl.c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
        }
        if (self.backend == .OpenGL) {
            flags |= sdl.c.SDL_WINDOW_OPENGL;
            try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DOUBLEBUFFER, 1));
            try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_DEPTH_SIZE, 24));
            try sdl.errify(sdl.c.SDL_GL_SetAttribute(sdl.c.SDL_GL_STENCIL_SIZE, 8));
        }

        var width: c_int = 1280;
        var height: c_int = 720;
        switch (cfg.window_size) {
            .fullscreen => {
                flags |= sdl.c.SDL_WINDOW_FULLSCREEN;
            },
            .maximized => {
                flags |= sdl.c.SDL_WINDOW_MAXIMIZED;
            },
            .windowed => |size| {
                width = @intCast(size.width);
                height = @intCast(size.height);
            },
        }
        const window = sdl.c.SDL_CreateWindow(
            cfg.title,
            width,
            height,
            flags,
        );
        if (window == null) {
            log.err("Unable to create ember window: {s}", .{sdl.c.SDL_GetError()});
            return error.SdlError;
        }
        self.window = Window{ .ptr = window.? };

        const video_driver_cstr = sdl.c.SDL_GetCurrentVideoDriver() orelse null;
        const skip_set_pos = if (video_driver_cstr) |cstr| blk: {
            const name = std.mem.span(cstr);
            break :blk std.mem.eql(u8, name, "wayland");
        } else false;

        if (!skip_set_pos) {
            sdl.errify(sdl.c.SDL_SetWindowPosition(
                self.window.ptr,
                sdl.c.SDL_WINDOWPOS_CENTERED,
                sdl.c.SDL_WINDOWPOS_CENTERED,
            )) catch {
                log.err("SDL_SetWindowPosition failed: {s}", .{sdl.c.SDL_GetError()});
            };
        } else {
            log.debug("Skipping SDL_SetWindowPosition – not supported by Wayland backend", .{});
        }
    }

    pub fn deinitWindow(self: *Self) void {
        sdl.c.SDL_DestroyWindow(self.window.ptr);
        sdl.c.SDL_Quit();
    }

    pub fn initImGui(self: *Self) !void {
        const ig_ctx = ig.c.igCreateContext(null);
        if (ig_ctx == null) {
            std.log.err("Failed to create ImGui context!", .{});
            return error.ImguiError;
        }

        self._imgui_io = ig.c.igGetIO();
        self._imgui_io.ConfigFlags |= ig.c.ImGuiConfigFlags_NavEnableKeyboard;
        self._imgui_io.ConfigFlags |= ig.c.ImGuiConfigFlags_NavEnableGamepad;
        self._imgui_io.ConfigFlags |= ig.c.ImGuiConfigFlags_DockingEnable;
        self._imgui_io.ConfigFlags |= ig.c.ImGuiConfigFlags_ViewportsEnable;

        ig.c.igStyleColorsDark(null);
    }

    pub fn deinitImgui() void {
        ig.ImGui_ImplSDL3_Shutdown();
        const ctx = ig.c.igGetCurrentContext();
        ig.c.igDestroyContext(ctx);
    }

    pub fn initRenderer(self: *Self) !void {
        self.renderer_ctx = try ember.Renderer.init(self.allocator, self.window.ptr);

        try sdl.errify(sdl.c.SDL_ShowWindow(self.window.ptr));
        // try ember.Renderer.setVSync(&renderer_ctx, true);

        try ember.Renderer.initImGuiBackend(&self.renderer_ctx);
    }

    pub fn deinitRenderer(self: *Self) void {
        ember.Renderer.deinitImGuiBackend();
        ember.Renderer.deinit(&self.renderer_ctx);
    }

    inline fn _update(
        self: *Self,
        comptime eventFn: *const fn (*Context, io.Event) anyerror!void,
        comptime updateFn: *const fn (*Context) anyerror!void,
    ) void {
        while (io.pollSdlEvent()) |event| {
            _ = ig.ImGui_ImplSDL3_ProcessEvent(&event);
            if (self._imgui_io.WantCaptureMouse) {
                continue;
            }

            const e = io.Event.from(event);
            if (e == .quit) {
                self.running = false;
            }
            if (e == .window) {
                switch (e.window.type) {
                    .resized => {
                        ember.Renderer.resize(
                            &self.renderer_ctx,
                            @intCast(e.window.type.resized.width),
                            @intCast(e.window.type.resized.height),
                        ) catch |err| {
                            log.err("Got error while resizing: {any}", .{err});
                            self.running = false;
                        };
                    },
                    .close => {
                        self.running = false;
                    },
                    else => {},
                }
            }

            eventFn(self, e) catch |err| {
                log.err("Got error while running `update`: {any}", .{err});
                self.running = false;
            };
        }
        updateFn(self) catch |err| {
            log.err("Got error while running `update`: {any}", .{err});
            self.running = false;
        };
    }

    pub fn tick(
        self: *Self,
        comptime eventFn: *const fn (*Context, io.Event) anyerror!void,
        comptime updateFn: *const fn (*Context) anyerror!void,
        comptime drawFn: *const fn (*Context) anyerror!void,
    ) void {
        const threshold: u64 = switch (self.cfg.fps_limit) {
            .unlimited => 0,
            .vsync => 0,
            .capped => |fps| self._tick_freq / @as(u64, fps),
        };

        if (threshold > 0) {
            while (true) {
                const _tick = sdl.c.SDL_GetPerformanceCounter();
                const elapsed_ticks = _tick - self._last_tick;
                self._last_tick = _tick;
                self._tick_acc += elapsed_ticks;
                if (self._tick_acc >= threshold) {
                    break;
                }
                if ((threshold - self._tick_acc) * 1000 > self._tick_freq) {
                    sdl.c.SDL_Delay(1); // Delay 1 frame
                }
            }

            // clamp accumulator
            self._tick_acc = std.math.clamp(self._tick_acc, 0, self._tick_max);

            var step: u32 = 0;
            const dt: f32 = @floatCast(
                @as(f64, @floatFromInt(threshold)) / @as(f64, @floatFromInt(self._tick_freq)),
            );

            while (self._tick_acc >= threshold) {
                step += 1;
                self._tick_acc -= threshold;
                // fixed time step
                self.dt = dt;
                self._seconds += self.dt;
                self._update(eventFn, updateFn);
            }

            self.dt = @as(f32, @floatFromInt(step)) * dt;
        } else {
            const _tick = sdl.c.SDL_GetPerformanceCounter();
            const elapsed_ticks = _tick - self._last_tick;
            self.dt = @floatCast(
                @as(f64, @floatFromInt(elapsed_ticks)) / @as(f64, @floatFromInt(self._tick_freq)),
            );
            self._last_tick = _tick;
            self._seconds += self.dt;
            self._update(eventFn, updateFn);
        }

        ig.ImGui_ImplSDL3_NewFrame();
        ember.Renderer.newImGuiFrame();
        ig.c.igNewFrame();

        ember.Renderer.beginFrame(&self.renderer_ctx, ember.CLEAR_COLOR) catch |err| {
            log.err("Got error while beginning frame: {any}", .{err});
            self.running = false;
        };
        drawFn(self) catch |err| {
            log.err("Got error while beginning frame: {any}", .{err});
            self.running = false;
        };
        ig.c.igRender();
        ember.Renderer.render(&self.renderer_ctx, ember.CLEAR_COLOR) catch |err| {
            log.err("Got error while presenting frame: {any}", .{err});
            self.running = false;
        };
        ember.Renderer.endFrame(&self.renderer_ctx) catch |err| {
            log.err("Got error while ending frame: {any}", .{err});
            self.running = false;
        };

        self._frame += 1;
        const duration = self._seconds - self._last_stat_time;
        if (duration >= 1) {
            self.fps = @as(
                f32,
                @floatCast(
                    @as(f64, @floatFromInt(self._frame)) / duration,
                ),
            );
            self._last_stat_time = self._seconds;
            self._frame = 0;
        }
    }
};
