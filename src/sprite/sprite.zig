const std = @import("std");
const TextureHandle = @import("../core/resource.zig").TextureHandle;

pub const SpriteInstance = struct {
    transform: [16]f32 align(16),
    uv_offset_scale: @Vector(4, f32) align(16),
    color: @Vector(4, f32) align(16),
    texture_handle: TextureHandle align(16),
};

pub const CircleInstance = struct {
    center: @Vector(2, f32) align(8),
    radius: f32,
    color: @Vector(4, f32) align(16),

    comptime {
        std.debug.assert(@alignOf(CircleInstance) == 16);
    }
};

pub const LineInstance = struct {
    start: @Vector(2, f32) align(8),
    end: @Vector(2, f32) align(8),
    thickness: f32,
    color: @Vector(4, f32) align(16),
    _padding: [12]u8 = std.mem.zeroes([12]u8),

    comptime {
        std.debug.assert(@alignOf(LineInstance) == 16);
    }
};

pub const RectInstance = struct {
    position: @Vector(2, f32) align(8),
    size: @Vector(2, f32) align(8),
    color: @Vector(4, f32) align(16),

    comptime {
        std.debug.assert(@alignOf(RectInstance) == 16);
    }
};
