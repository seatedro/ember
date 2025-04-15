const std = @import("std");

pub const c = @cImport({
    // This prevents SDL from trying to define its own main.
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL.h");
    // @cInclude("SDL3/SDL_video.h"),
    // @cInclude("SDL3/SDL_render.h"),
    // @cInclude("SDL3/SDL_events.h"),
    // @cInclude("SDL3/SDL_main.h"),
});

// Optional: Add Zig helper functions for SDL if desired, e.g., errify
const SdlError = error{
    SdlError, // Generic SDL error
};

/// Converts the return value of an SDL function to an error union.
/// Handles common SDL return patterns (int < 0, null pointers, bool false).
pub inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
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

fn logSdlError() void {
    const err_msg = c.SDL_GetError();
    if (std.mem.len(err_msg) > 0) {
        std.log.err("SDL Error: {s}", .{err_msg});
    } else {
        std.log.err("SDL Error: (No specific message)", .{});
    }
}
