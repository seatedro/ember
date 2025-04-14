const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const imgui_dep = b.dependency("imgui", .{});
    const imgui_include_path = imgui_dep.path("");
    const imgui_backend_path = imgui_dep.path("backends");
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    const sdl_include_path = sdl_dep.path("include");

    // --- C/C++ Flags ---
    var common_flags = std.ArrayList([]const u8).init(b.allocator);
    defer common_flags.deinit();
    try common_flags.appendSlice(&.{
        "-DIMGUI_USE_WCHAR32=1",
        "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1",
    });
    // Add target-specific flags (WASM, Windows DLL export, etc.) if necessary

    // --- Static Library (Local cimgui.cpp + ImGui Core + Backends) ---
    const lib_cimgui_impl = b.addStaticLibrary(.{
        .name = "cimgui_impl", // Library containing all C++ implementations
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_cimgui_impl.linkLibCpp();

    // Include paths needed by the C++ sources
    lib_cimgui_impl.addIncludePath(sdl_include_path);
    lib_cimgui_impl.addIncludePath(b.path("dist")); // For local cimgui.h
    lib_cimgui_impl.addIncludePath(imgui_include_path); // For imgui.h, imconfig.h
    lib_cimgui_impl.addIncludePath(imgui_backend_path); // For backend headers

    // Add LOCAL cimgui.cpp source
    lib_cimgui_impl.addCSourceFile(.{
        .file = b.path("dist/cimgui.cpp"), // Local file
        .flags = common_flags.items,
    });

    // Add Core ImGui sources FROM DEPENDENCY
    lib_cimgui_impl.addCSourceFiles(.{
        .files = &.{
            // Paths relative to the imgui dependency root
            "imgui.cpp",
            "imgui_demo.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
        },
        .root = imgui_include_path, // Specify root for these paths
        .flags = common_flags.items,
    });

    // Add Backend sources FROM DEPENDENCY
    lib_cimgui_impl.addCSourceFiles(.{
        .files = &.{
            // Paths relative to the imgui dependency's backend dir
            "imgui_impl_sdl3.cpp",
            "imgui_impl_sdlrenderer3.cpp",
        },
        .root = imgui_backend_path, // Specify root for these paths
        .flags = common_flags.items,
    });

    // Add other backends (opengl3, metal, osx) or features (freetype)
    // from the imgui dependency similar to the Ghostty example if needed.
    // Example:
    // lib_cimgui_impl.addCSourceFile(.{
    //     .file = imgui_dep.path("backends/imgui_impl_opengl3.cpp"),
    //     .flags = common_flags.items,
    // });
    // if (target.result.os.tag.isDarwin()) { ... }

    // Link system libraries if needed by backends (e.g., imm32 on windows)
    if (target.result.os.tag == .windows) {
        lib_cimgui_impl.linkSystemLibrary("imm32");
    }

    // Make the implementation library available to the main build
    b.installArtifact(lib_cimgui_impl);

    // --- Translate LOCAL cimgui.h ---
    const translate_cimgui = b.addTranslateC(.{
        .root_source_file = b.path("dist/cimgui.h"), // Local header
        .target = target, // Use target, not host, if header might have target specifics
        .optimize = optimize,
        // IMPORTANT: Provide include path for "imgui.h" which cimgui.h includes
        // .include_dirs = &.{imgui_include_path},
        // .c_flags = common_flags.items, // Pass defines
    });

    const translate_sdl3_backend = b.addTranslateC(.{
        .root_source_file = imgui_dep.path("backends/imgui_impl_sdl3.h"),
        .target = target,
        .optimize = optimize,
    });

    // Translate imgui_impl_sdlrenderer3.h
    const translate_sdlrenderer3_backend = b.addTranslateC(.{
        .root_source_file = imgui_dep.path("backends/imgui_impl_sdlrenderer3.h"),
        .target = target,
        .optimize = optimize,
    });

    // --- Create Backend Zig Modules ---
    const mod_cimgui_sdl3 = b.addModule("cimgui_sdl3", .{
        .root_source_file = translate_sdl3_backend.getOutput(),
        .target = target,
        .optimize = optimize,
    });
    mod_cimgui_sdl3.linkLibrary(lib_cimgui_impl);

    const mod_cimgui_sdlrenderer3 = b.addModule("cimgui_sdlrenderer3", .{
        .root_source_file = translate_sdlrenderer3_backend.getOutput(),
        .target = target,
        .optimize = optimize,
    });
    mod_cimgui_sdlrenderer3.linkLibrary(lib_cimgui_impl);

    // --- Create and expose the core cimgui Zig module ---
    const mod_cimgui = b.addModule("cimgui", .{
        .root_source_file = translate_cimgui.getOutput(),
        .target = target,
        .optimize = optimize,
    });
    // Link the C++ implementations to this module
    mod_cimgui.linkLibrary(lib_cimgui_impl);

    const sdl_mod = b.addModule("sdl", .{
        .root_source_file = b.path("sdl.zig"),
        .target = target,
        .optimize = optimize,
    });
    sdl_mod.linkLibrary(sdl_lib);
}
