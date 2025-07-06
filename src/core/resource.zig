const std = @import("std");
const renderer = @import("../build_config.zig").renderer;

pub const BackendTexture = struct {
    texture: switch (renderer) {
        .WGPU => @import("../rendering/backend/wgpu.zig").Texture,
        .OpenGL => @import("../rendering/backend/opengl.zig").Texture,
        .SDL => @import("../rendering/backend/sdl.zig").Texture,
    },
    width: u32,
    height: u32,
};

pub const TextureFormat = enum {
    RGBA8,
    RGB8,
    RG8,
    R8,
    RGBA16F,
    DEPTH24_STENCIL8,
};

pub const TextureAsset = struct {
    width: u32,
    height: u32,
    format: TextureFormat,
    path: []const u8, // owned copy for debugging
    backend_data: BackendTexture,

    pub fn deinit(self: *TextureAsset, a: std.mem.Allocator) void {
        if (self.path.len > 0) a.free(self.path);
    }

    pub fn size(self: *const TextureAsset) @Vector(2, f32) {
        return @Vector(2, f32){
            @floatFromInt(self.width),
            @floatFromInt(self.height),
        };
    }
};

pub fn Handle(comptime T: type) type {
    _ = T; // gonads
    return struct {
        const Self = @This();

        index: u32,
        generation: u32,

        pub const INVALID = Self{ .index = std.math.maxInt(u32), .generation = 0 };

        pub fn isValid(self: Self) bool {
            return self.index != std.math.maxInt(u32);
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.index == other.index and self.generation == other.generation;
        }
    };
}

pub fn Assets(comptime T: type) type {
    return struct {
        const Self = @This();
        const AssetHandle = Handle(T);

        assets: std.ArrayList(T),
        generations: std.ArrayList(u32),
        free_indices: std.ArrayList(u32),
        allocator: std.mem.Allocator,

        // profiling
        stats: struct {
            total_allocated: usize = 0,
            peak_allocated: usize = 0,
            allocations: u64 = 0,
            deallocations: u64 = 0,
        } = .{},

        pub fn init(a: std.mem.Allocator) Self {
            return Self{
                .assets = std.ArrayList(T).init(a),
                .generations = std.ArrayList(u32).init(a),
                .free_indices = std.ArrayList(u32).init(a),
                .allocator = a,
            };
        }

        pub fn initCapacity(a: std.mem.Allocator, cap: usize) !Self {
            var self = Self{
                .assets = try std.ArrayList(T).initCapacity(a, cap),
                .generations = try std.ArrayList(u32).initCapacity(a, cap),
                .free_indices = try std.ArrayList(u32).initCapacity(a, cap / 4),
                .allocator = a,
            };

            try self.generations.resize(cap);
            @memset(self.generations.items, 0);
            self.generations.items.len = 0;

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(T, "deinit")) {
                // Only deinit assets that are not in the free list
                for (self.assets.items, 0..) |*asset, i| {
                    const index = @as(u32, @intCast(i));
                    var is_free = false;
                    for (self.free_indices.items) |free_idx| {
                        if (free_idx == index) {
                            is_free = true;
                            break;
                        }
                    }
                    if (!is_free) {
                        asset.deinit(self.allocator);
                    }
                }
            }
            self.assets.deinit();
            self.generations.deinit();
            self.free_indices.deinit();
        }

        pub fn add(self: *Self, asset: T) !AssetHandle {
            const index = if (self.free_indices.items.len > 0) blk: {
                const idx = self.free_indices.pop() orelse unreachable;
                self.assets.items[idx] = asset;
                self.generations.items[idx] +%= 1; // wrapping add
                break :blk idx;
            } else blk: {
                const idx = self.assets.items.len;
                try self.assets.append(asset);
                try self.generations.append(1);
                break :blk @as(u32, @intCast(idx));
            };

            // -- stats
            self.stats.allocations += 1;
            self.stats.total_allocated = self.assets.items.len - self.free_indices.items.len;
            self.stats.peak_allocated = @max(self.stats.peak_allocated, self.stats.total_allocated);

            return AssetHandle{
                .index = index,
                .generation = self.generations.items[index],
            };
        }

        pub inline fn get(self: *const Self, h: AssetHandle) ?*const T {
            if (!h.isValid() or h.index >= self.assets.items.len) return null;
            if (self.generations.items[h.index] != h.generation) return null;
            return &self.assets.items[h.index];
        }

        pub inline fn getMut(self: *Self, h: AssetHandle) ?*T {
            if (!h.isValid() or h.index >= self.assets.items.len) return null;
            if (self.generations.items[h.index] != h.generation) return null;
            return &self.assets.items[h.index];
        }

        pub fn remove(self: *Self, h: AssetHandle) bool {
            if (!h.isValid() or h.index >= self.assets.items.len) return false;
            if (self.generations.items[h.index] != h.generation) return false;

            if (@hasDecl(T, "deinit")) {
                self.assets.items[h.index].deinit(self.allocator);
            }

            self.generations.items[h.index] +%= 1;
            self.free_indices.append(h.index) catch return false;

            // stats
            self.stats.deallocations += 1;
            self.stats.total_allocated = self.assets.items.len - self.free_indices.items.len;

            return true;
        }

        pub fn addBatch(self: *Self, assets: []const T) ![]AssetHandle {
            const handles = try self.allocator.alloc(AssetHandle, assets.len);
            for (assets, 0..) |asset, i| {
                handles[i] = try self.add(asset);
            }
            return handles;
        }

        pub fn removeBatch(self: *Self, handles: []const AssetHandle) void {
            for (handles) |h| {
                _ = self.remove(h);
            }
        }

        pub fn len(self: *const Self) usize {
            return self.assets.items.len - self.free_indices.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            if (@hasDecl(T, "deinit")) {
                for (self.assets.items) |*asset| {
                    asset.deinit(self.allocator);
                }
            }
            self.assets.clearRetainingCapacity();
            self.generations.clearRetainingCapacity();
            self.free_indices.clearRetainingCapacity();
            self.stats.total_allocated = 0;
        }
    };
}

pub const AssetManager = struct {
    textures: Assets(TextureAsset),
    allocator: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !AssetManager {
        return AssetManager{
            .textures = try Assets(TextureAsset).initCapacity(a, 256),
            .allocator = a,
        };
    }

    pub fn deinit(self: *AssetManager) void {
        self.textures.deinit();
    }

    pub fn loadTexture(
        self: *AssetManager,
        path: []const u8,
        backend_texture: BackendTexture,
    ) !TextureHandle {
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        const tex = TextureAsset{
            .width = backend_texture.width,
            .height = backend_texture.height,
            .format = .RGBA8,
            .path = owned_path,
            .backend_data = backend_texture,
        };
        return try self.textures.add(tex);
    }

    pub fn getTexture(self: *const AssetManager, h: TextureHandle) ?*const TextureAsset {
        return self.textures.get(h);
    }

    pub fn getTextureMut(self: *AssetManager, h: TextureHandle) ?*TextureAsset {
        return self.textures.getMut(h);
    }

    pub fn destroyTexture(self: *AssetManager, h: TextureHandle) void {
        _ = self.textures.remove(h);
    }

    pub fn destroyTextures(self: *AssetManager, handles: []const TextureHandle) void {
        self.textures.removeBatch(handles);
    }

    pub fn getStats(self: *const AssetManager) AssetStats {
        return AssetStats{
            .texture_count = self.textures.len(),
            .texture_stats = self.textures.stats,
        };
    }
};

pub const AssetStats = struct {
    texture_count: usize,
    texture_stats: @TypeOf(Assets(TextureAsset).stats),
};

pub const TextureHandle = Handle(TextureAsset);

test "asset system basic operations" {
    var manager = try AssetManager.init(std.testing.allocator);
    defer manager.deinit();

    const invalid = TextureHandle.INVALID;
    try std.testing.expect(!invalid.isValid());
}

test "handle size and alignment" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(TextureHandle));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(TextureHandle));
}
