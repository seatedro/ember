const std = @import("std");

pub const Config = struct {
    /// Logging level
    log_level: std.log.Level = std.log.default_level,

    /// FPS limiting
    fps_limit: FpsLimit = .{ .capped = 60 },

    /// Window Size
    window_size: WindowSize = .fullscreen,

    /// App name
    title: [:0]const u8,

    /// Flags
    window_borderless: bool = false,
    window_highdpi: bool = false,
};

pub const WindowSize = union(enum) {
    fullscreen,
    maximized,
    windowed: struct { width: u32, height: u32 },
};

pub const FpsLimit = union(enum) {
    unlimited, // No limit, draw as fast as we can
    vsync, // Enable vsync when hardware acceleration is available, default to 30 fps otherwise
    capped: u32, // Capped to given fps, fixed time step

    pub inline fn str(self: @This()) []const u8 {
        return switch (self) {
            .unlimited => "unlimited",
            .vsync => "vsync",
            .capped => "capped",
        };
    }
};
