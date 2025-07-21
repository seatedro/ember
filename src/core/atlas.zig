const std = @import("std");
const core = @import("./types.zig");

pub const TextureAtlas = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pixels: []u8,
    width: u32,
    height: u32,
    white_uv: core.Vec2,
    dirty: bool = true,

    next_x: u32,
    next_y: u32,
    row_h: u32,

    pub fn init(allocator: std.mem.Allocator, initial_size: u32) !Self {
        var atlas = Self{
            .allocator = allocator,
            .width = initial_size,
            .height = initial_size,
            .pixels = try allocator.alloc(u8, initial_size * initial_size * 4),
            .next_x = 1, // 0,0 - white pixel
            .next_y = 0,
            .row_h = 1,
            .white_uv = undefined,
            .dirty = true,
        };

        @memset(atlas.pixels, 0);

        const idx = 0;
        atlas.pixels[idx + 0] = 255; // R
        atlas.pixels[idx + 1] = 255; // G
        atlas.pixels[idx + 2] = 255; // B
        atlas.pixels[idx + 3] = 255; // A

        atlas.white_uv = core.Vec2{
            0.5 / @as(f32, @floatFromInt(initial_size)),
            0.5 / @as(f32, @floatFromInt(initial_size)),
        };

        return atlas;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.pixels);
    }

    pub fn getSize(self: *const Self) core.Vec2 {
        return core.Vec2{
            @as(f32, @floatFromInt(self.width)),
            @as(f32, @floatFromInt(self.height)),
        };
    }
};
