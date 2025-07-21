const std = @import("std");
const TextureHandle = @import("../core/resource.zig").TextureHandle;

const Point = @Vector(2, f32);

pub const SpriteCommand = struct {
    transform: [16]f32,
    uv_offset_scale: @Vector(4, f32),
    color: @Vector(4, f32),
    texture_handle: TextureHandle,
};

pub const CircleCommand = struct {
    center: Point,
    radius: f32,
    color: u32,
    num_segments: u32,
};

pub const LineCommand = struct {
    start: Point,
    end: Point,
    thickness: f32,
    color: u32,
};

pub const QuadCommand = struct {
    position: Point,
    size: Point,
    color: u32,
};
