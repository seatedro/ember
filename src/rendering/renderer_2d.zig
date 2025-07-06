const std = @import("std");
const buffer_vec = @import("buffer_vec.zig");
const sprite = @import("../sprite/sprite.zig");
const resource_handles = @import("../core/resource.zig");

const TextureHandle = resource_handles.TextureHandle;
const BufferVec = buffer_vec.BufferVec;
const SpriteInstance = sprite.SpriteInstance;
const CircleInstance = sprite.CircleInstance;
const LineInstance = sprite.LineInstance;
const RectInstance = sprite.RectInstance;

pub const Renderer2D = struct {
    allocator: std.mem.Allocator,

    sprite_instances: BufferVec(SpriteInstance),
    circle_instances: BufferVec(CircleInstance),
    line_instances: BufferVec(LineInstance),
    rect_instances: BufferVec(RectInstance),

    draw_batches: std.ArrayList(DrawBatch),
    config: Renderer2DConfig,

    pub fn init(allocator: std.mem.Allocator, config: Renderer2DConfig) !Renderer2D {
        return Renderer2D{
            .sprite_instances = try BufferVec(SpriteInstance).initCapacity(allocator, config.initial_sprite_capacity),
            .circle_instances = try BufferVec(CircleInstance).initCapacity(allocator, config.initial_shape_capacity),
            .line_instances = try BufferVec(LineInstance).initCapacity(allocator, config.initial_shape_capacity),
            .rect_instances = try BufferVec(RectInstance).initCapacity(allocator, config.initial_shape_capacity),
            .draw_batches = try std.ArrayList(DrawBatch).initCapacity(allocator, config.initial_batch_capacity),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        self.sprite_instances.deinit();
        self.circle_instances.deinit();
        self.line_instances.deinit();
        self.rect_instances.deinit();
        self.draw_batches.deinit();
    }

    pub fn clearFrame(self: *Renderer2D) void {
        self.sprite_instances.data.clearRetainingCapacity();
        self.circle_instances.data.clearRetainingCapacity();
        self.line_instances.data.clearRetainingCapacity();
        self.rect_instances.data.clearRetainingCapacity();
        self.draw_batches.clearRetainingCapacity();
    }

    pub fn drawSprite(self: *Renderer2D, sprite_data: SpriteDrawData) !void {
        const transform_matrix = sprite_data.transform.toMatrix();

        const instance = SpriteInstance{
            .transform = transform_matrix,
            .uv_offset_scale = sprite_data.uv_offset_scale,
            .color = sprite_data.color,
            .texture_handle = sprite_data.texture_handle,
        };

        try self.sprite_instances.data.append(instance);
    }

    pub fn drawCircle(self: *Renderer2D, center: @Vector(2, f32), radius: f32, color: @Vector(4, f32)) !void {
        const instance = CircleInstance{
            .center = center,
            .radius = radius,
            .color = color,
        };

        try self.circle_instances.data.append(instance);
    }

    pub fn drawLine(self: *Renderer2D, start: @Vector(2, f32), end: @Vector(2, f32), thickness: f32, color: @Vector(4, f32)) !void {
        const instance = LineInstance{
            .start = start,
            .end = end,
            .thickness = thickness,
            .color = color,
        };

        try self.line_instances.data.append(instance);
    }

    pub fn drawRect(self: *Renderer2D, position: @Vector(2, f32), size: @Vector(2, f32), color: @Vector(4, f32)) !void {
        const instance = RectInstance{
            .position = position,
            .size = size,
            .color = color,
        };

        try self.rect_instances.data.append(instance);
    }

    pub fn generateBatches(self: *Renderer2D) !void {
        self.draw_batches.clearRetainingCapacity();

        if (self.sprite_instances.len() > 0) {
            try self.generateSpriteBatches();
        }

        if (self.circle_instances.len() > 0) {
            try self.draw_batches.append(DrawBatch{
                .batch_type = .Circles,
                .start_index = 0,
                .count = @intCast(self.circle_instances.len()),
                .texture_handle = TextureHandle.INVALID,
            });
        }

        if (self.line_instances.len() > 0) {
            try self.draw_batches.append(DrawBatch{
                .batch_type = .Lines,
                .start_index = 0,
                .count = @intCast(self.line_instances.len()),
                .texture_handle = TextureHandle.INVALID,
            });
        }

        if (self.rect_instances.len() > 0) {
            try self.draw_batches.append(DrawBatch{
                .batch_type = .Rectangles,
                .start_index = 0,
                .count = @intCast(self.rect_instances.len()),
                .texture_handle = TextureHandle.INVALID,
            });
        }
    }

    fn generateSpriteBatches(self: *Renderer2D) !void {
        if (self.sprite_instances.len() == 0) return;

        var current_texture_handle = TextureHandle.INVALID;
        var batch_start: u32 = 0;
        var batch_count: u32 = 0;

        for (self.sprite_instances.data.items, 0..) |instance, i| {
            if (!instance.texture_handle.eql(current_texture_handle)) {
                if (batch_count > 0) {
                    try self.draw_batches.append(DrawBatch{
                        .batch_type = .Sprites,
                        .start_index = batch_start,
                        .count = batch_count,
                        .texture_handle = current_texture_handle,
                    });
                }

                current_texture_handle = instance.texture_handle;
                batch_start = @intCast(i);
                batch_count = 1;
            } else {
                batch_count += 1;
            }
        }

        if (batch_count > 0) {
            try self.draw_batches.append(DrawBatch{
                .batch_type = .Sprites,
                .start_index = batch_start,
                .count = batch_count,
                .texture_handle = current_texture_handle,
            });
        }
    }

    pub fn getBatches(self: *const Renderer2D) []const DrawBatch {
        return self.draw_batches.items;
    }

    pub fn getSpriteInstances(self: *const Renderer2D) []const SpriteInstance {
        return self.sprite_instances.data.items;
    }

    pub fn getCircleInstances(self: *const Renderer2D) []const CircleInstance {
        return self.circle_instances.data.items;
    }

    pub fn getLineInstances(self: *const Renderer2D) []const LineInstance {
        return self.line_instances.data.items;
    }

    pub fn getRectInstances(self: *const Renderer2D) []const RectInstance {
        return self.rect_instances.data.items;
    }
};

pub const Renderer2DConfig = struct {
    initial_sprite_capacity: usize = 10000,
    initial_shape_capacity: usize = 1000,
    initial_batch_capacity: usize = 64,
};

pub const DrawBatch = struct {
    batch_type: BatchType,
    start_index: u32,
    count: u32,
    texture_handle: TextureHandle,
};

pub const BatchType = enum {
    Sprites,
    Circles,
    Lines,
    Rectangles,
};

pub const Transform2D = struct {
    position: @Vector(2, f32) = @Vector(2, f32){ 0.0, 0.0 },
    rotation: f32 = 0.0,
    scale: @Vector(2, f32) = @Vector(2, f32){ 1.0, 1.0 },

    pub fn toMatrix(self: Transform2D) [16]f32 {
        const cos_r = @cos(self.rotation);
        const sin_r = @sin(self.rotation);

        return [16]f32{
            cos_r * self.scale[0], -sin_r * self.scale[1], 0.0, self.position[0],
            sin_r * self.scale[0], cos_r * self.scale[1],  0.0, self.position[1],
            0.0,                   0.0,                    1.0, 0.0,
            0.0,                   0.0,                    0.0, 1.0,
        };
    }

    pub fn transformPoint(self: Transform2D, point: @Vector(2, f32)) @Vector(2, f32) {
        const cos_r = @cos(self.rotation);
        const sin_r = @sin(self.rotation);

        const scaled = point * self.scale;
        const rotated = @Vector(2, f32){
            scaled[0] * cos_r - scaled[1] * sin_r,
            scaled[0] * sin_r + scaled[1] * cos_r,
        };

        return rotated + self.position;
    }
};

pub const SpriteDrawData = struct {
    transform: Transform2D,
    texture_handle: TextureHandle,
    uv_offset_scale: @Vector(4, f32) = @Vector(4, f32){ 0.0, 0.0, 1.0, 1.0 },
    color: @Vector(4, f32) = @Vector(4, f32){ 1.0, 1.0, 1.0, 1.0 },
};

pub const Color = struct {
    pub const WHITE = @Vector(4, f32){ 1.0, 1.0, 1.0, 1.0 };
    pub const BLACK = @Vector(4, f32){ 0.0, 0.0, 0.0, 1.0 };
    pub const RED = @Vector(4, f32){ 1.0, 0.0, 0.0, 1.0 };
    pub const GREEN = @Vector(4, f32){ 0.0, 1.0, 0.0, 1.0 };
    pub const BLUE = @Vector(4, f32){ 0.0, 0.0, 1.0, 1.0 };
    pub const YELLOW = @Vector(4, f32){ 1.0, 1.0, 0.0, 1.0 };
    pub const MAGENTA = @Vector(4, f32){ 1.0, 0.0, 1.0, 1.0 };
    pub const CYAN = @Vector(4, f32){ 0.0, 1.0, 1.0, 1.0 };

    pub fn rgb(r: f32, g: f32, b: f32) @Vector(4, f32) {
        return @Vector(4, f32){ r, g, b, 1.0 };
    }

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) @Vector(4, f32) {
        return @Vector(4, f32){ r, g, b, a };
    }
};

test "Renderer2D basic operations" {
    const config = Renderer2DConfig{
        .initial_sprite_capacity = 100,
        .initial_shape_capacity = 50,
        .initial_batch_capacity = 10,
    };

    var renderer = try Renderer2D.init(std.testing.allocator, config);
    defer renderer.deinit();

    const sprite_data = SpriteDrawData{
        .transform = Transform2D{
            .position = @Vector(2, f32){ 100.0, 50.0 },
            .scale = @Vector(2, f32){ 2.0, 2.0 },
        },
        .texture_handle = TextureHandle{ .index = 0, .generation = 0 },
        .color = Color.RED,
    };

    try renderer.drawSprite(sprite_data);
    try std.testing.expectEqual(@as(usize, 1), renderer.sprite_instances.len());

    try renderer.drawCircle(@Vector(2, f32){ 50.0, 50.0 }, 25.0, Color.BLUE);
    try std.testing.expectEqual(@as(usize, 1), renderer.circle_instances.len());

    try renderer.generateBatches();
    const batches = renderer.getBatches();
    try std.testing.expect(batches.len >= 2); // At least sprite and circle batches

    renderer.clearFrame();
    try std.testing.expectEqual(@as(usize, 0), renderer.sprite_instances.len());
    try std.testing.expectEqual(@as(usize, 0), renderer.circle_instances.len());
}

test "Transform2D matrix generation" {
    const transform = Transform2D{
        .position = @Vector(2, f32){ 10.0, 20.0 },
        .rotation = std.math.pi / 4.0, // 45 degrees
        .scale = @Vector(2, f32){ 2.0, 3.0 },
    };

    const matrix = transform.toMatrix();

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), matrix[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), matrix[7], 0.001);

    const point = @Vector(2, f32){ 1.0, 0.0 };
    const transformed = transform.transformPoint(point);

    try std.testing.expect(transformed[0] > 9.0 and transformed[0] < 12.0); // Approximately √2 + 10
    try std.testing.expect(transformed[1] > 20.0 and transformed[1] < 23.0); // Approximately √2 + 20
}
