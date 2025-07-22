const std = @import("std");
const buffer_vec = @import("buffer_vec.zig");
const sprite = @import("../sprite/sprite.zig");
const resource_handles = @import("../core/resource.zig");
const core = @import("../core/types.zig");

const TextureHandle = resource_handles.TextureHandle;
const SpriteCommand = sprite.SpriteCommand;
const CircleCommand = sprite.CircleCommand;
const LineCommand = sprite.LineCommand;
const QuadCommand = sprite.QuadCommand;
const Vec2 = core.Vec2;

const DRAWLIST_ARCFAST_SAMPLE_MAX = 48;
const CIRCLE_SEGMENTATION_MAX_ERROR: f32 = 0.3;
const DRAWLIST_ARCFAST_RADIUS_CUTOFF = calcCircleAutoSegmentCount(DRAWLIST_ARCFAST_SAMPLE_MAX);
const CIRCLE_AUTO_SEGMENT_MIN = 12;
const CIRCLE_AUTO_SEGMENT_MAX = 512;
const DRAWLIST_ARCFAST_TABLE_SIZE = DRAWLIST_ARCFAST_SAMPLE_MAX;
const DRAWLIST_CIRCLE_AUTO_SEGMENT_MAX = 512;
const IM_DRAWLIST_TEX_LINES_WIDTH_MAX = 63;

pub const DrawFlags = struct {
    closed: bool = false,
    anti_aliased: bool = true,
};

const COL32_A_MASK: u32 = 0xFF000000;

pub const DrawVert = struct {
    pos: Vec2,
    uv: Vec2,
    color: u32,
};

pub const DrawCmd = struct {
    clip_rect: @Vector(4, f32), // x1, y1, x2, y2
    texture_id: ?*anyopaque,
    vtx_offset: u32,
    idx_offset: u32,
    elem_count: u32,
    user_callback: ?*const fn () void = null,
};

pub const DrawData = struct {
    allocator: std.mem.Allocator,
    arc_fast_vtx: [DRAWLIST_ARCFAST_SAMPLE_MAX]Vec2,
    tex_uv_white_pixel: Vec2,
    fringe_scale: f32 = 1.0,
    temp_buffer: std.ArrayList(Vec2),

    pub fn init(allocator: std.mem.Allocator) !DrawData {
        var data = DrawData{
            .allocator = allocator,
            .tex_uv_white_pixel = .{ 0.0, 0.0 },
            .arc_fast_vtx = undefined,
            .temp_buffer = std.ArrayList(Vec2).init(allocator),
        };

        for (0..DRAWLIST_ARCFAST_SAMPLE_MAX) |i| {
            const a = (@as(f32, @floatFromInt(i)) * 2.0 * std.math.pi) / @as(f32, @floatFromInt(DRAWLIST_ARCFAST_SAMPLE_MAX));
            data.arc_fast_vtx[i] = Vec2{ @cos(a), @sin(a) };
        }

        return data;
    }

    pub fn deinit(self: *DrawData) void {
        self.temp_buffer.deinit();
    }
};

inline fn roundUpToEven(value: anytype) @TypeOf(value) {
    return @divFloor((value + 1), 2) * 2;
}

inline fn calcCircleAutoSegmentCount(radius: f32) i32 {
    std.debug.assert(radius != 0);

    return std.math.clamp(
        roundUpToEven(
            @as(i32, @intFromFloat(
                std.math.ceil(
                    std.math.pi /
                        std.math.acos(
                            1 - @min(
                                CIRCLE_SEGMENTATION_MAX_ERROR,
                                radius,
                            ) /
                                radius,
                        ),
                ),
            )),
        ),
        CIRCLE_AUTO_SEGMENT_MIN,
        CIRCLE_AUTO_SEGMENT_MAX,
    );
}

pub const DrawList = struct {
    allocator: std.mem.Allocator,
    data: DrawData,

    cmd_buffer: std.ArrayList(DrawCmd),

    vtx_buffer: std.ArrayList(DrawVert),
    idx_buffer: std.ArrayList(u32),

    path: std.ArrayList(Vec2),

    // Current state
    vtx_current_idx: u32 = 0,
    flags: DrawFlags = .{},

    pub fn init(allocator: std.mem.Allocator) !DrawList {
        return DrawList{
            .allocator = allocator,
            .data = try DrawData.init(allocator),
            .cmd_buffer = std.ArrayList(DrawCmd).init(allocator),
            .vtx_buffer = std.ArrayList(DrawVert).init(allocator),
            .idx_buffer = std.ArrayList(u32).init(allocator),
            .path = std.ArrayList(Vec2).init(allocator),
        };
    }

    pub fn deinit(self: *DrawList) void {
        self.cmd_buffer.deinit();
        self.vtx_buffer.deinit();
        self.idx_buffer.deinit();
        self.path.deinit();
        self.data.deinit();
    }

    pub fn clearFrame(self: *DrawList) void {
        self.cmd_buffer.clearRetainingCapacity();
        self.vtx_buffer.clearRetainingCapacity();
        self.idx_buffer.clearRetainingCapacity();
        self.path.clearRetainingCapacity();
        self.vtx_current_idx = 0;
    }

    fn primReserve(self: *DrawList, idx_count: u32, vtx_count: u32) !void {
        if (self.cmd_buffer.items.len == 0) {
            try self.cmd_buffer.append(DrawCmd{
                .clip_rect = @Vector(4, f32){ -8192.0, -8192.0, 8192.0, 8192.0 },
                .texture_id = null,
                .vtx_offset = 0,
                .idx_offset = 0,
                .elem_count = 0,
            });
        }

        const cmd = &self.cmd_buffer.items[self.cmd_buffer.items.len - 1];
        cmd.elem_count += idx_count;

        try self.vtx_buffer.ensureUnusedCapacity(vtx_count);
        try self.idx_buffer.ensureUnusedCapacity(idx_count);
    }

    pub fn primQuadUV(
        self: *DrawList,
        a: Vec2,
        b: Vec2,
        c: Vec2,
        d: Vec2,
        uv_a: Vec2,
        uv_b: Vec2,
        uv_c: Vec2,
        uv_d: Vec2,
        col: u32,
    ) !void {
        const idx = self.vtx_current_idx;

        // Add indices for two triangles
        try self.idx_buffer.appendSlice(&[_]u32{
            idx, idx + 1, idx + 2,
            idx, idx + 2, idx + 3,
        });

        // Add vertices
        try self.vtx_buffer.appendSlice(&[_]DrawVert{
            DrawVert{ .pos = a, .uv = uv_a, .color = col },
            DrawVert{ .pos = b, .uv = uv_b, .color = col },
            DrawVert{ .pos = c, .uv = uv_c, .color = col },
            DrawVert{ .pos = d, .uv = uv_d, .color = col },
        });

        self.vtx_current_idx += 4;
    }

    pub fn pathArcToFastEx(
        self: *DrawList,
        center: Vec2,
        radius: f32,
        a_min_sample: i32,
        a_max_sample: i32,
        a_step_in: i32,
    ) !void {
        if (radius < 0.5) {
            try self.path.append(center);
            return;
        }

        var a_step = a_step_in;
        if (a_step <= 0) {
            a_step = @divTrunc(DRAWLIST_ARCFAST_SAMPLE_MAX, calcCircleAutoSegmentCount(radius));
        }

        a_step = std.math.clamp(a_step, 1, DRAWLIST_ARCFAST_TABLE_SIZE / 4);
        const a_next_step = a_step;

        const sample_range = @as(i32, @intCast(@abs(a_max_sample - a_min_sample)));
        var samples = sample_range + 1;
        var extra_max_sample = false;

        if (a_step > 1) {
            samples = @divTrunc(sample_range, a_step) + 1;
            const overstep = @mod(sample_range, a_step);

            if (overstep > 0) {
                extra_max_sample = true;
                samples += 1;

                if (sample_range > 0) {
                    a_step -= @divTrunc(a_step - overstep, 2);
                }
            }
        }

        const start_len = self.path.items.len;
        try self.path.resize(start_len + @as(usize, @intCast(samples)));

        var sample_index = a_min_sample;
        if (sample_index < 0 or sample_index >= DRAWLIST_ARCFAST_SAMPLE_MAX) {
            sample_index = @mod(sample_index, DRAWLIST_ARCFAST_SAMPLE_MAX);
            if (sample_index < 0) {
                sample_index += DRAWLIST_ARCFAST_SAMPLE_MAX;
            }
        }

        var out_idx = start_len;

        if (a_max_sample >= a_min_sample) {
            var a = a_min_sample;
            while (a <= a_max_sample) {
                if (sample_index >= DRAWLIST_ARCFAST_SAMPLE_MAX) {
                    sample_index -= DRAWLIST_ARCFAST_SAMPLE_MAX;
                }

                const s = self.data.arc_fast_vtx[@as(usize, @intCast(sample_index))];
                self.path.items[out_idx] = Vec2{ center[0] + s[0] * radius, center[1] + s[1] * radius };
                out_idx += 1;

                a += a_step;
                sample_index += a_step;
                a_step = a_next_step;
            }
        } else {
            var a = a_min_sample;
            while (a >= a_max_sample) {
                if (sample_index < 0) {
                    sample_index += DRAWLIST_ARCFAST_SAMPLE_MAX;
                }

                const s = self.data.arc_fast_vtx[@as(usize, @intCast(sample_index))];
                self.path.items[out_idx] = Vec2{ center[0] + s[0] * radius, center[1] + s[1] * radius };
                out_idx += 1;

                a -= a_step;
                sample_index -= a_step;
                a_step = a_next_step;
            }
        }

        if (extra_max_sample) {
            var normalized_max_sample = @mod(a_max_sample, DRAWLIST_ARCFAST_SAMPLE_MAX);
            if (normalized_max_sample < 0) {
                normalized_max_sample += DRAWLIST_ARCFAST_SAMPLE_MAX;
            }

            const s = self.data.arc_fast_vtx[@as(usize, @intCast(normalized_max_sample))];
            self.path.items[out_idx] = Vec2{ center[0] + s[0] * radius, center[1] + s[1] * radius };
            out_idx += 1;
        }

        std.debug.assert(self.path.items.len == out_idx);
    }

    pub fn pathArcToN(
        self: *DrawList,
        center: Vec2,
        radius: f32,
        a_min: f32,
        a_max: f32,
        num_segments: usize,
    ) !void {
        if (radius < 0.5) {
            try self.path.append(center);
            return;
        }

        const path_size = self.path.items.len;
        try self.path.ensureTotalCapacity(path_size + num_segments + 1);
        var i: usize = 0;
        while (i <= num_segments) : (i += 1) {
            const a = a_min + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_segments))) * (a_max - a_min);
            try self.path.append(.{ center[0] + @cos(a) * radius, center[1] + @sin(a) * radius });
        }
    }

    pub fn pathArcTo(
        self: *DrawList,
        center: Vec2,
        radius: f32,
        a_min: f32,
        a_max: f32,
        num_segments: usize,
    ) !void {
        if (radius < 0.5) {
            try self.path.append(center);
            return;
        }

        if (num_segments > 0) {
            try self.pathArcToN(center, radius, a_min, a_max, num_segments);
            return;
        }

        if (radius <= DRAWLIST_ARCFAST_RADIUS_CUTOFF) {
            const a_is_reverse = a_max < a_min;

            const a_min_sample_f = DRAWLIST_ARCFAST_SAMPLE_MAX * @divTrunc(a_min, (std.math.pi * 2.0));
            const a_max_sample_f = DRAWLIST_ARCFAST_SAMPLE_MAX * @divTrunc(a_max, (std.math.pi * 2.0));

            const a_min_sample = if (a_is_reverse) @as(i32, @intFromFloat(@floor(a_min_sample_f))) else @as(i32, @intFromFloat(@ceil(a_min_sample_f)));
            const a_max_sample = if (!a_is_reverse) @as(i32, @intFromFloat(@floor(a_max_sample_f))) else @as(i32, @intFromFloat(@ceil(a_max_sample_f)));
            const a_mid_samples = if (a_is_reverse) @max(a_min_sample - a_max_sample, 0) else @max(a_max_sample - a_min_sample, 0);

            const a_min_segment_angle = @divTrunc((@as(f32, @floatFromInt(a_min_sample)) * std.math.pi * 2.0), DRAWLIST_ARCFAST_SAMPLE_MAX);
            const a_max_segment_angle = @divTrunc((@as(f32, @floatFromInt(a_max_sample)) * std.math.pi * 2.0), DRAWLIST_ARCFAST_SAMPLE_MAX);
            const a_emit_start = @abs(a_min_segment_angle - a_min) >= 1e-5;
            const a_emit_end = @abs(a_max - a_max_segment_angle) >= 1e-5;

            const path_size = self.path.items.len;
            try self.path.ensureTotalCapacity(path_size + (a_mid_samples + 1 + @intFromBool(a_emit_start) + @intFromBool(a_emit_end)));
            if (a_emit_start) {
                try self.path.append(.{ (center[0] * @cos(a_min) * radius), (center[1] * @sin(a_min) * radius) });
            }
            if (a_mid_samples > 0) {
                try self.pathArcToFastEx(center, radius, a_min_sample, a_max_sample, 0);
            }
            if (a_emit_end) {
                try self.path.append(.{ (center[0] * @cos(a_max) * radius), (center[1] * @sin(a_max) * radius) });
            }
        } else {
            const arc_length = @abs(a_max - a_min);
            const circle_segment_count = calcCircleAutoSegmentCount(radius);
            const arc_segment_count = @max(
                @as(usize, @intFromFloat(
                    @ceil(@as(f32, @floatFromInt(circle_segment_count)) * arc_length) /
                        std.math.pi * 2.0,
                )),
                @as(usize, @intFromFloat(@divTrunc(2.0 * std.math.pi, arc_length))),
            );
            try self.pathArcToN(center, radius, a_min, a_max, arc_segment_count);
        }
    }

    pub fn pathStroke(self: *DrawList, col: u32, flags: DrawFlags, thickness: f32) !void {
        try self.addPolyline(self.path.items, col, flags, thickness);
        self.path.clearRetainingCapacity();
    }

    pub fn pathFillConvex(self: *DrawList, col: u32) !void {
        try self.addConvexPolyFilled(self.path.items, col);
        self.path.clearRetainingCapacity();
    }

    pub fn addCircle(self: *DrawList, center: Vec2, radius: f32, col: u32, num_segments: usize, thickness: f32) !void {
        if ((col & COL32_A_MASK) == 0 or radius < 0.5) {
            return;
        }

        if (num_segments <= 0) {
            try self.pathArcToFastEx(center, radius - 0.5, 0, DRAWLIST_ARCFAST_SAMPLE_MAX, 0);
            // We need to remove a duplicate last point since first and last points are identical
            if (self.path.items.len > 0) {
                _ = self.path.pop();
            }
        } else {
            const segments: usize = std.math.clamp(num_segments, 3, DRAWLIST_CIRCLE_AUTO_SEGMENT_MAX);
            const a_max = (std.math.pi * 2.0) * (@as(f32, @floatFromInt(segments)) - 1.0) / @as(f32, @floatFromInt(segments));
            try self.pathArcTo(center, radius - 0.5, 0.0, a_max, segments - 1);
        }

        try self.pathStroke(col, DrawFlags{ .closed = true }, thickness);
    }

    pub fn addCircleFilled(self: *DrawList, center: Vec2, radius: f32, col: u32, num_segments: usize) !void {
        if ((col & COL32_A_MASK) == 0 or radius < 0.5) {
            return;
        }

        if (num_segments <= 0) {
            try self.pathArcToFastEx(center, radius, 0, DRAWLIST_ARCFAST_SAMPLE_MAX, 0);
            if (self.path.items.len > 0) {
                _ = self.path.pop();
            }
        } else {
            const segments = std.math.clamp(num_segments, 3, DRAWLIST_CIRCLE_AUTO_SEGMENT_MAX);
            const a_max = (std.math.pi * 2.0) * (@as(f32, @floatFromInt(segments)) - 1.0) / @as(f32, @floatFromInt(segments));
            try self.pathArcTo(center, radius, 0.0, a_max, segments - 1);
        }

        try self.pathFillConvex(col);
    }

    pub fn addConvexPolyFilled(self: *DrawList, points: []const Vec2, col: u32) !void {
        if (points.len < 3 or (col & COL32_A_MASK) == 0) {
            return;
        }

        const uv = self.data.tex_uv_white_pixel;
        if (self.flags.anti_aliased) {
            const aa_size = self.data.fringe_scale;
            const col_trans = col & ~COL32_A_MASK;

            const idx_count = (points.len - 2) * 3 + points.len * 6;
            const vtx_count = points.len * 2;

            try self.primReserve(@intCast(idx_count), @intCast(vtx_count));

            const vtx_inner_idx: u32 = self.vtx_current_idx;
            const vtx_outer_idx: u32 = self.vtx_current_idx + 1;
            for (2..points.len) |i| {
                try self.idx_buffer.appendSlice(&[_]u32{
                    vtx_inner_idx,
                    vtx_inner_idx + @as(u32, @intCast(i - 1)) * 2,
                    vtx_inner_idx + @as(u32, @intCast(i)) * 2,
                });
            }

            try self.data.temp_buffer.resize(points.len);
            const temp_normals = self.data.temp_buffer.items;

            // Compute edge normals (per edge, left-handed, normalized)
            var i_0: usize = points.len - 1;
            var i_1: usize = 0;
            while (i_1 < points.len) : (i_0 = i_1) {
                const p0 = points[i_0];
                const p1 = points[i_1];
                var dx: f32 = p1[0] - p0[0];
                var dy: f32 = p1[1] - p0[1];
                {
                    const d2 = dx * dx + dy * dy;
                    if (d2 > 0.0) {
                        const inv_len = 1.0 / @sqrt(d2);
                        dx *= inv_len;
                        dy *= inv_len;
                    }
                }
                temp_normals[i_0][0] = dy;
                temp_normals[i_0][1] = -dx;
                i_1 += 1;
            }

            i_0 = points.len - 1;
            i_1 = 0;
            while (i_1 < points.len) : (i_0 = i_1) {
                const n0 = temp_normals[i_0];
                const n1 = temp_normals[i_1];
                // Average normals
                var dm_x: f32 = (n0[0] + n1[0]) * 0.5;
                var dm_y: f32 = (n0[1] + n1[1]) * 0.5;
                {
                    const d2 = dm_x * dm_x + dm_y * dm_y;
                    if (d2 > 0.000001) {
                        var inv_len2: f32 = 1.0 / d2;
                        if (inv_len2 > 100.0) inv_len2 = 100.0;
                        dm_x *= inv_len2;
                        dm_y *= inv_len2;

                        dm_x *= aa_size * 0.5;
                        dm_y *= aa_size * 0.5;
                    } else {
                        // If the average normal is too small, keep dm at zero so vertices collapse correctly
                        dm_x = 0.0;
                        dm_y = 0.0;
                    }
                }

                try self.vtx_buffer.append(DrawVert{
                    .pos = Vec2{ points[i_1][0] - dm_x, points[i_1][1] - dm_y },
                    .uv = uv,
                    .color = col,
                });
                try self.vtx_buffer.append(DrawVert{
                    .pos = Vec2{ points[i_1][0] + dm_x, points[i_1][1] + dm_y },
                    .uv = uv,
                    .color = col_trans,
                });

                // Fringe indices (two triangles forming a quad between inner & outer ring)
                try self.idx_buffer.appendSlice(&[_]u32{
                    vtx_inner_idx + @as(u32, @intCast(i_1)) * 2,
                    vtx_inner_idx + @as(u32, @intCast(i_0)) * 2,
                    vtx_outer_idx + @as(u32, @intCast(i_0)) * 2,
                    vtx_outer_idx + @as(u32, @intCast(i_0)) * 2,
                    vtx_outer_idx + @as(u32, @intCast(i_1)) * 2,
                    vtx_inner_idx + @as(u32, @intCast(i_1)) * 2,
                });
                i_1 += 1;
            }

            self.vtx_current_idx += @intCast(vtx_count);
        } else {
            // Non anti-aliased fill
            const idx_count = (points.len - 2) * 3;
            const vtx_count = points.len;

            try self.primReserve(@intCast(idx_count), @intCast(vtx_count));

            for (points) |point| {
                try self.vtx_buffer.append(DrawVert{ .pos = point, .uv = uv, .color = col });
            }

            for (2..points.len) |i| {
                try self.idx_buffer.appendSlice(&[_]u32{
                    self.vtx_current_idx,
                    self.vtx_current_idx + @as(u32, @intCast(i - 1)),
                    self.vtx_current_idx + @as(u32, @intCast(i)),
                });
            }

            self.vtx_current_idx += @intCast(vtx_count);
        }
    }

    pub fn addPolyline(self: *DrawList, points: []const Vec2, col: u32, flags: DrawFlags, thickness: f32) !void {
        if (points.len < 2 or (col & COL32_A_MASK) == 0) {
            return;
        }

        const closed = flags.closed;
        const opaque_uv = self.data.tex_uv_white_pixel;
        const count = if (closed) points.len else points.len - 1;
        const thick_line = thickness > self.data.fringe_scale;
        const anti_aliased = flags.anti_aliased;

        if (anti_aliased) {
            const aa_size = self.data.fringe_scale;
            const col_trans = col & ~COL32_A_MASK;

            const actual_thickness = @max(thickness, 1.0);

            const idx_count = if (thick_line) count * 18 else count * 12;
            const vtx_count = if (thick_line) points.len * 4 else points.len * 3;

            try self.primReserve(@intCast(idx_count), @intCast(vtx_count));

            try self.data.temp_buffer.resize(points.len);
            const temp_normals = self.data.temp_buffer.items;

            for (0..count) |segment_i| {
                const next_i = if ((segment_i + 1) == points.len) 0 else segment_i + 1;
                var dx: f32 = points[next_i][0] - points[segment_i][0];
                var dy: f32 = points[next_i][1] - points[segment_i][1];
                // Normalize over zero
                const d2 = dx * dx + dy * dy;
                if (d2 > 0.0) {
                    const inv_len = 1.0 / @sqrt(d2);
                    dx *= inv_len;
                    dy *= inv_len;
                }
                temp_normals[segment_i][0] = dy;
                temp_normals[segment_i][1] = -dx;
            }
            if (!closed) {
                temp_normals[points.len - 1] = temp_normals[points.len - 2];
            }

            if (!thick_line) {
                const half_draw_size = aa_size;

                for (0..points.len) |i| {
                    const i_prev = if (i == 0) (if (closed) points.len - 1 else 0) else i - 1;
                    var dm_x: f32 = (temp_normals[i_prev][0] + temp_normals[i][0]) * 0.5;
                    var dm_y: f32 = (temp_normals[i_prev][1] + temp_normals[i][1]) * 0.5;

                    const d2 = dm_x * dm_x + dm_y * dm_y;
                    if (d2 > 0.000001) {
                        var inv_len2: f32 = 1.0 / d2;
                        if (inv_len2 > 100.0) inv_len2 = 100.0;
                        dm_x *= inv_len2;
                        dm_y *= inv_len2;

                        dm_x *= half_draw_size;
                        dm_y *= half_draw_size;
                    } else {
                        dm_x = 0.0;
                        dm_y = 0.0;
                    }

                    try self.vtx_buffer.appendSlice(&[_]DrawVert{
                        DrawVert{ .pos = points[i], .uv = opaque_uv, .color = col },
                        DrawVert{ .pos = Vec2{ points[i][0] + dm_x, points[i][1] + dm_y }, .uv = opaque_uv, .color = col_trans },
                        DrawVert{ .pos = Vec2{ points[i][0] - dm_x, points[i][1] - dm_y }, .uv = opaque_uv, .color = col_trans },
                    });
                }
            } else {
                const half_inner_thickness = (actual_thickness - aa_size) * 0.5;

                for (0..points.len) |i| {
                    const i_prev = if (i == 0) (if (closed) points.len - 1 else 0) else i - 1;
                    var dm_x: f32 = (temp_normals[i_prev][0] + temp_normals[i][0]) * 0.5;
                    var dm_y: f32 = (temp_normals[i_prev][1] + temp_normals[i][1]) * 0.5;

                    const d2 = dm_x * dm_x + dm_y * dm_y;
                    if (d2 > 0.000001) {
                        var inv_len2: f32 = 1.0 / d2;
                        if (inv_len2 > 100.0) inv_len2 = 100.0;
                        dm_x *= inv_len2;
                        dm_y *= inv_len2;
                    } else {
                        dm_x = 0.0;
                        dm_y = 0.0;
                    }

                    const dm_out_x = dm_x * (half_inner_thickness + aa_size);
                    const dm_out_y = dm_y * (half_inner_thickness + aa_size);
                    const dm_in_x = dm_x * half_inner_thickness;
                    const dm_in_y = dm_y * half_inner_thickness;

                    try self.vtx_buffer.appendSlice(&[_]DrawVert{
                        DrawVert{ .pos = Vec2{ points[i][0] + dm_out_x, points[i][1] + dm_out_y }, .uv = opaque_uv, .color = col_trans },
                        DrawVert{ .pos = Vec2{ points[i][0] + dm_in_x, points[i][1] + dm_in_y }, .uv = opaque_uv, .color = col },
                        DrawVert{ .pos = Vec2{ points[i][0] - dm_in_x, points[i][1] - dm_in_y }, .uv = opaque_uv, .color = col },
                        DrawVert{ .pos = Vec2{ points[i][0] - dm_out_x, points[i][1] - dm_out_y }, .uv = opaque_uv, .color = col_trans },
                    });
                }
            }

            var idx1 = self.vtx_current_idx;
            for (0..count) |i| {
                const vertex_increment: u32 = if (thick_line) 4 else 3;
                const idx2 = if ((i + 1) == points.len) self.vtx_current_idx else idx1 + vertex_increment;

                if (thick_line) {
                    // 18 indices for thick lines
                    try self.idx_buffer.appendSlice(&[_]u32{
                        idx2 + 1, idx1 + 1, idx1 + 2,
                        idx1 + 2, idx2 + 2, idx2 + 1,
                        idx2 + 1, idx1 + 1, idx1 + 0,
                        idx1 + 0, idx2 + 0, idx2 + 1,
                        idx2 + 2, idx1 + 2, idx1 + 3,
                        idx1 + 3, idx2 + 3, idx2 + 2,
                    });
                } else {
                    // 12 indices for thin lines
                    try self.idx_buffer.appendSlice(&[_]u32{
                        idx2 + 0, idx1 + 0, idx1 + 2,
                        idx1 + 2, idx2 + 2, idx2 + 0,
                        idx2 + 1, idx1 + 1, idx1 + 0,
                        idx1 + 0, idx2 + 0, idx2 + 1,
                    });
                }

                idx1 = idx2;
            }

            self.vtx_current_idx += @intCast(vtx_count);
        } else {
            // Non anti-aliased lines
            const idx_count = count * 6;
            const vtx_count = count * 4;

            try self.primReserve(@intCast(idx_count), @intCast(vtx_count));

            for (0..count) |i_1| {
                const i_2 = if ((i_1 + 1) == points.len) 0 else i_1 + 1;
                const p1 = points[i_1];
                const p2 = points[i_2];

                var dx = p2[0] - p1[0];
                var dy = p2[1] - p1[1];
                const len = @sqrt(dx * dx + dy * dy);
                if (len > 0.0) {
                    dx /= len;
                    dy /= len;
                }

                dx *= thickness * 0.5;
                dy *= thickness * 0.5;

                try self.vtx_buffer.appendSlice(&[_]DrawVert{
                    DrawVert{ .pos = Vec2{ p1[0] + dy, p1[1] - dx }, .uv = opaque_uv, .color = col },
                    DrawVert{ .pos = Vec2{ p2[0] + dy, p2[1] - dx }, .uv = opaque_uv, .color = col },
                    DrawVert{ .pos = Vec2{ p2[0] - dy, p2[1] + dx }, .uv = opaque_uv, .color = col },
                    DrawVert{ .pos = Vec2{ p1[0] - dy, p1[1] + dx }, .uv = opaque_uv, .color = col },
                });

                try self.idx_buffer.appendSlice(&[_]u32{
                    self.vtx_current_idx + 0, self.vtx_current_idx + 1, self.vtx_current_idx + 2,
                    self.vtx_current_idx + 0, self.vtx_current_idx + 2, self.vtx_current_idx + 3,
                });

                self.vtx_current_idx += 4;
            }
        }
    }
};

pub const Renderer2D = struct {
    allocator: std.mem.Allocator,
    dl: DrawList,

    pub fn init(allocator: std.mem.Allocator) !Renderer2D {
        const dl = try DrawList.init(allocator);

        return Renderer2D{
            .allocator = allocator,
            .dl = dl,
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        self.dl.deinit();
    }

    pub fn clearFrame(self: *Renderer2D) void {
        self.dl.clearFrame();
    }

    pub fn drawSprite(self: *Renderer2D, sprite_data: SpriteDrawData) !void {
        // Create sprite quad corners
        const corners = [_]Vec2{
            Vec2{ -0.5, -0.5 }, // bottom-left
            Vec2{ 0.5, -0.5 }, // bottom-right
            Vec2{ 0.5, 0.5 }, // top-right
            Vec2{ -0.5, 0.5 }, // top-left
        };

        var transformed_corners: [4]Vec2 = undefined;
        for (corners, 0..) |corner, i| {
            transformed_corners[i] = sprite_data.transform.transformPoint(corner);
        }

        const uv_min = Vec2{ sprite_data.uv_offset_scale[0], sprite_data.uv_offset_scale[1] };
        const uv_max = Vec2{ sprite_data.uv_offset_scale[0] + sprite_data.uv_offset_scale[2], sprite_data.uv_offset_scale[1] + sprite_data.uv_offset_scale[3] };

        const uvs = [_]Vec2{
            Vec2{ uv_min[0], uv_max[1] }, // bottom-left
            Vec2{ uv_max[0], uv_max[1] }, // bottom-right
            Vec2{ uv_max[0], uv_min[1] }, // top-right
            Vec2{ uv_min[0], uv_min[1] }, // top-left
        };

        const color_u32 = colorToU32(sprite_data.color);

        try self.dl.primReserve(6, 4);
        try self.dl.primQuadUV(transformed_corners[0], // a (bottom-left)
            transformed_corners[1], // b (bottom-right)
            transformed_corners[2], // c (top-right)
            transformed_corners[3], // d (top-left)
            uvs[0], // uv_a
            uvs[1], // uv_b
            uvs[2], // uv_c
            uvs[3], // uv_d
            color_u32);
    }

    pub fn drawCircle(
        self: *Renderer2D,
        center: Vec2,
        radius: f32,
        color: @Vector(4, f32),
    ) !void {
        const color_u32 = colorToU32(color);
        try self.dl.addCircle(center, radius, color_u32, 0, 1.0);
    }

    pub fn drawCircleFilled(
        self: *Renderer2D,
        center: Vec2,
        radius: f32,
        color: @Vector(4, f32),
    ) !void {
        const color_u32 = colorToU32(color);
        try self.dl.addCircleFilled(center, radius, color_u32, 0);
    }

    pub fn drawLine(
        self: *Renderer2D,
        start: Vec2,
        end: Vec2,
        thickness: f32,
        color: @Vector(4, f32),
    ) !void {
        const color_u32 = colorToU32(color);
        const points = [_]Vec2{ start, end };
        try self.dl.addPolyline(&points, color_u32, DrawFlags{}, thickness);
    }

    pub fn drawRect(
        self: *Renderer2D,
        position: Vec2,
        size: Vec2,
        color: @Vector(4, f32),
    ) !void {
        const color_u32 = colorToU32(color);
        const corners = [_]Vec2{
            position,
            Vec2{ position[0] + size[0], position[1] },
            Vec2{ position[0] + size[0], position[1] + size[1] },
            Vec2{ position[0], position[1] + size[1] },
        };
        try self.dl.addConvexPolyFilled(&corners, color_u32);
    }
};

fn colorToU32(color: @Vector(4, f32)) u32 {
    const r = @as(u32, @intFromFloat(std.math.clamp(color[0], 0.0, 1.0) * 255.0));
    const g = @as(u32, @intFromFloat(std.math.clamp(color[1], 0.0, 1.0) * 255.0));
    const b = @as(u32, @intFromFloat(std.math.clamp(color[2], 0.0, 1.0) * 255.0));
    const a = @as(u32, @intFromFloat(std.math.clamp(color[3], 0.0, 1.0) * 255.0));
    return (a << 24) | (b << 16) | (g << 8) | r;
}

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
