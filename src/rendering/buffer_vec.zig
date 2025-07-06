const std = @import("std");

pub fn BufferVec(comptime T: type) type {
    return struct {
        const Self = @This();

        data: std.ArrayList(T),
        buffer: ?*anyopaque = null,
        label: ?[]const u8 = null,
        changed: bool = false,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .data = std.ArrayList(T).init(allocator),
            };
        }

        pub fn initCapacity(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            const data = try std.ArrayList(T).initCapacity(allocator, initial_capacity);
            return .{
                .data = data,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn reserve(self: *Self, new_capacity: usize) !void {
            if (new_capacity > self.data.capacity) {
                const target_capacity = @max(self.data.capacity * 2, new_capacity);
                try self.data.ensureTotalCapacity(target_capacity);
                self.changed = true;
            }
        }

        pub fn setLabel(self: *Self, label: []const u8) void {
            if (label != self.label) {
                self.changed = true;
            }
            self.label = label;
        }

        pub inline fn len(self: *Self) usize {
            return self.data.items.len;
        }

        pub inline fn capacity(self: *Self) usize {
            return self.data.capacity;
        }
    };
}

pub const Vec2BufferVec = BufferVec(@Vector(2, f32));
pub const Vec3BufferVec = BufferVec(@Vector(3, f32));
pub const Vec4BufferVec = BufferVec(@Vector(4, f32));
pub const Mat4BufferVec = BufferVec([16]f32);
pub const U32BufferVec = BufferVec(u32);
pub const F32BufferVec = BufferVec(f32);

test "BufferVec basic operations" {
    var buffer = BufferVec(f32).init(std.testing.allocator);
    defer buffer.deinit();

    // Test push
    _ = try buffer.push(1.0);
    _ = try buffer.push(2.0);

    try std.testing.expectEqual(@as(usize, 2), buffer.len());
    try std.testing.expectEqual(@as(f32, 1.0), buffer.get(0).?.*);
    try std.testing.expectEqual(@as(f32, 2.0), buffer.get(1).?.*);

    // Test clear retaining capacity
    const old_capacity = buffer.capacity();
    buffer.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), buffer.len());
    try std.testing.expectEqual(old_capacity, buffer.capacity());
}

test "BufferVec performance patterns" {
    var buffer = try BufferVec(u32).initCapacity(std.testing.allocator, 1000);
    defer buffer.deinit();

    // Simulate frame-like usage
    for (0..500) |i| {
        _ = try buffer.push(@intCast(i));
    }

    // Clear without deallocating - critical for performance
    buffer.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), buffer.len());
    try std.testing.expect(buffer.capacity() >= 1000);

    // Should not allocate on next frame
    for (0..500) |i| {
        _ = try buffer.push(@intCast(i + 1000));
    }
}
