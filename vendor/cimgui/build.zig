const std = @import("std");
const wgpu = @import("wgpu/root.zig");

pub fn build(b: *std.Build) !void {
    const renderer_opt = b.option(
        enum { SDL, OpenGL, WGPU },
        "renderer",
        "Renderer backend: sdl | opengl | wgpu (default: wgpu)",
    );
    const renderer = renderer_opt orelse .WGPU;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const imgui_dep = b.dependency("imgui", .{});
    const imgui_source_path = imgui_dep.path("");
    const imgui_backend_path = imgui_dep.path("backends");

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });

    const sdl_image_dep = b.dependency("SDL_image", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_include_path = sdl_dep.path("include");
    const sdl_mod = b.addModule("sdl", .{
        .root_source_file = b.path("sdl.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    sdl_mod.linkLibrary(sdl_lib);
    sdl_mod.linkLibrary(sdl_image_dep.artifact("SDL3_image"));
    sdl_mod.addIncludePath(sdl_include_path);

    const cimgui_mod = b.addModule("cimgui", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdl", .module = sdl_mod },
        },
    });
    const wgpuHeaderPath = try wgpu.getIncludePath(b, optimize, target);
    cimgui_mod.addIncludePath(wgpuHeaderPath);
    cimgui_mod.addIncludePath(b.path("dist"));
    cimgui_mod.addIncludePath(imgui_source_path);
    cimgui_mod.addIncludePath(sdl_include_path);

    const lib_cimgui = b.addStaticLibrary(.{
        .name = "cimgui_impl",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_cimgui.linkLibCpp();

    lib_cimgui.addIncludePath(wgpuHeaderPath);
    lib_cimgui.addIncludePath(sdl_include_path);
    lib_cimgui.addIncludePath(b.path("dist"));
    lib_cimgui.addIncludePath(imgui_source_path);
    lib_cimgui.addIncludePath(imgui_backend_path);

    var common_cpp_flags = std.ArrayList([]const u8).init(b.allocator);
    defer common_cpp_flags.deinit();
    try common_cpp_flags.appendSlice(&.{
        "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1",
        "-DIMGUI_IMPL_API=extern\t\"C\"",
        // "-DIMGUI_USE_WCHAR32=1", // Add if needed
    });
    if (renderer == .WGPU) {
        try common_cpp_flags.append("-DIMGUI_IMPL_WEBGPU_BACKEND_WGPU=1");
    }

    lib_cimgui.addCSourceFile(.{
        .file = b.path("dist/cimgui.cpp"),
        .flags = common_cpp_flags.items,
    });
    lib_cimgui.addCSourceFiles(.{
        .files = &.{
            "imgui.cpp",
            "imgui_demo.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
        },
        .root = imgui_source_path,
        .flags = common_cpp_flags.items,
    });
    lib_cimgui.addCSourceFile(.{
        .file = imgui_dep.path("backends/imgui_impl_sdl3.cpp"),
        .flags = common_cpp_flags.items,
    });
    switch (renderer) {
        .SDL => {
            lib_cimgui.addCSourceFile(.{
                .file = imgui_dep.path("backends/imgui_impl_sdlrenderer3.cpp"),
                .flags = common_cpp_flags.items,
            });
        },
        .OpenGL => {
            lib_cimgui.addCSourceFile(.{
                .file = imgui_dep.path("backends/imgui_impl_opengl3.cpp"),
                .flags = common_cpp_flags.items,
            });
        },
        .WGPU => {
            lib_cimgui.addCSourceFile(.{
                .file = imgui_dep.path("backends/imgui_impl_wgpu.cpp"),
                .flags = common_cpp_flags.items,
            });
        },
        else => unreachable,
    }

    if (target.result.os.tag == .windows) {
        lib_cimgui.linkSystemLibrary("imm32");
    }

    b.installArtifact(lib_cimgui);

    const test_exe = b.addTest(.{
        .root_module = cimgui_mod,
        .target = target,
        .optimize = optimize,
    });
    test_exe.linkLibrary(lib_cimgui);
    test_exe.linkLibrary(sdl_dep.artifact("SDL3"));
    if (target.result.os.tag == .windows) {
        test_exe.linkSystemLibrary("imm32");
    }

    const run_unit_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run cimgui unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
