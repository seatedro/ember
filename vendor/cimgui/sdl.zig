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
