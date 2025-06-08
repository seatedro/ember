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
    const wgpu_native_dep = b.dependency("wgpu_native_zig", .{
        .target = config.target,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "cimgui", .module = cimgui_mod },
            .{ .name = "sdl", .module = cimgui_dep.module("sdl") },
        },
    });
    if (config.renderer == .OpenGL) {
        if (b.lazyDependency("opengl", .{})) |dep| {
            exe_mod.addImport("opengl", dep.module("opengl"));
        }
        exe_mod.addIncludePath(b.path("vendor/glad/include"));
        exe_mod.addCSourceFile(.{
            .file = b.path("vendor/glad/src/gl.c"),
            .flags = &.{},
        });
    }
    exe_mod.addImport("wgpu", wgpu_native_dep.module("wgpu"));
    exe_mod.addOptions("build_options", options);
    exe_mod.linkLibrary(cimgui_dep.artifact("cimgui_impl"));

    const exe = b.addExecutable(.{
        .name = "ember",
        .root_module = exe_mod,
    });

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
