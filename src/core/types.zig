pub const Vec2 = @Vector(2, f32);

pub const Region = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const CanvasSize = struct {
    width: i32,
    height: i32,

    pub fn getWidthFloat(self: CanvasSize) f32 {
        return @floatFromInt(self.width);
    }

    pub fn getHeightFloat(self: CanvasSize) f32 {
        return @floatFromInt(self.height);
    }
};
