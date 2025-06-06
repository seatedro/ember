const std = @import("std");
pub fn getIncludePath(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) !std.Build.LazyPath {
    const target_res = target.result;
    const os_str = @tagName(target_res.os.tag);
    const arch_str = @tagName(target_res.cpu.arch);

    const mode_str = switch (optimize) {
        .Debug => "debug",
        else => "release",
    };
    const abi_str = switch (target_res.os.tag) {
        .windows => switch (target_res.abi) {
            .msvc => "_msvc",
            else => "_gnu",
        },
        else => "",
    };
    const target_name_slices = [_][:0]const u8{ "wgpu_", os_str, "_", arch_str, abi_str, "_", mode_str };
    const maybe_target_name = std.mem.concatWithSentinel(b.allocator, u8, &target_name_slices, 0);
    const target_name = maybe_target_name catch |err| {
        std.debug.panic("Failed to format target name: {s}", .{@errorName(err)});
    };
    for (b.available_deps) |dep| {
        const name, _ = dep;
        if (std.mem.eql(u8, name, target_name)) {
            break;
        }
    } else {
        std.debug.panic("Could not find dependency matching target {s}", .{target_name});
    }

    const wgpu_dep = b.lazyDependency(target_name, .{}) orelse return error.DependencyError;

    return wgpu_dep.path("include");
}
