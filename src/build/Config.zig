const Config = @This();

const std = @import("std");
const Renderer = @import("../rendering/renderer.zig");

/// Standard build configuration options.
optimize: std.builtin.OptimizeMode,
target: std.Build.ResolvedTarget,

/// Comptime interfaces
renderer: Renderer.BackendType = .SDL,

/// This is for the zig build -D options
pub fn init(b: *std.Build) !Config {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var config: Config = .{
        .optimize = optimize,
        .target = target,
    };
    config.renderer = b.option(
        Renderer.BackendType,
        "renderer",
        "Renderer backend: sdl | opengl | metal (default: sdl)",
    ) orelse Renderer.BackendType.default(target.result);

    return config;
}

/// This is for adding it to the build_options import
pub fn addOptions(self: *const Config, step: *std.Build.Step.Options) !void {
    step.addOption(Renderer.BackendType, "renderer", self.renderer);
}

/// This is so we can use the comptime values across different files
/// imported from "build_config.zig"
pub fn fromOptions() Config {
    const options = @import("build_options");
    return .{
        // Unused at runtime.
        .optimize = undefined,
        .target = undefined,

        .renderer = std.meta.stringToEnum(Renderer.BackendType, @tagName(options.renderer)).?,
    };
}
