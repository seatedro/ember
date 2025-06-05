const std = @import("std");
const Config = @import("src/build/Config.zig");

pub fn build(b: *std.Build) void {
    const config = try Config.init(b);
    const options = b.addOptions();
    try config.addOptions(options);

    const cimgui_dep = b.dependency("cimgui", .{
        .target = config.target,
        .optimize = config.optimize,
        .renderer = config.renderer,
    });
    const cimgui_mod = cimgui_dep.module("cimgui");
    const objc_dep = b.dependency("zig_objc", .{
        .target = config.target,
        .optimize = config.optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "cimgui", .module = cimgui_mod },
            .{ .name = "sdl", .module = cimgui_dep.module("sdl") },
            .{ .name = "objc", .module = objc_dep.module("objc") },
        },
    });
    if (b.lazyDependency("opengl", .{})) |dep| {
        exe_mod.addImport("opengl", dep.module("opengl"));
    }
    exe_mod.addIncludePath(b.path("vendor/glad/include"));
    exe_mod.addCSourceFile(.{
        .file = b.path("vendor/glad/src/gl.c"),
        .flags = &.{},
    });
    exe_mod.addOptions("build_options", options);
    exe_mod.linkLibrary(cimgui_dep.artifact("cimgui_impl"));

    const exe = b.addExecutable(.{
        .name = "ember",
        .root_module = exe_mod,
    });

    // Add Metal shader compilation step for macOS targets
    if (config.target.result.os.tag == .macos and config.renderer == .Metal) {
        const metal_shader_step = addMetalShaderStep(b);
        exe.step.dependOn(&metal_shader_step.step);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn addMetalShaderStep(b: *std.Build) *std.Build.Step.Run {
    // Create directory for compiled shaders
    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", "src/rendering/backend/metal/compiled" });

    // Compile .metal to .air
    const metal_compile_step = b.addSystemCommand(&.{ "xcrun", "metal", "-std=osx-metal2.0", "-o", "src/rendering/backend/metal/compiled/texture_shaders.air", "src/rendering/backend/metal/texture_shaders.metal" });
    metal_compile_step.step.dependOn(&mkdir_step.step);

    // Create metal archive
    const metal_ar_step = b.addSystemCommand(&.{ "xcrun", "metal-ar", "r", "src/rendering/backend/metal/compiled/texture_shaders.metal-ar", "src/rendering/backend/metal/compiled/texture_shaders.air" });
    metal_ar_step.step.dependOn(&metal_compile_step.step);

    // Create metallib
    const metallib_step = b.addSystemCommand(&.{ "xcrun", "metallib", "-o", "src/rendering/backend/metal/compiled/texture_shaders.metallib", "src/rendering/backend/metal/compiled/texture_shaders.metal-ar" });
    metallib_step.step.dependOn(&metal_ar_step.step);

    return metallib_step;
}
