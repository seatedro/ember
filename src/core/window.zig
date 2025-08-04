const std = @import("std");
const ember = @import("../ember.zig");
const sdl = ember.sdl;
const types = ember.types;

const Self = @This();
ptr: *sdl.c.SDL_Window,

pub fn getWindowSize(self: Self) !types.Size {
    var w: c_int = 0;
    var h: c_int = 0;
    try sdl.errify(sdl.c.SDL_GetWindowSize(self.ptr, &w, &h));
    return .{
        .width = @intCast(w),
        .height = @intCast(h),
    };
}

pub fn isMinimized(self: Self) bool {
    return (sdl.c.SDL_GetWindowFlags(self.ptr) & sdl.c.SDL_WINDOW_MINIMIZED) != 0;
}
