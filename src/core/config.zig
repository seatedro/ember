const std = @import("std");

pub const Config = struct {
    log_level: std.log.Level = std.log.default_level,

    fps_limit: FpsLimit = .{ .capped = 60 },

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
    unlimited,
    vsync,
    capped: u32,

    pub inline fn str(self: @This()) []const u8 {
        return switch (self) {
            .unlimited => "unlimited",
            .vsync => "vsync",
            .capped => "capped",
        };
    }
};
