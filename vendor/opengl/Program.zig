const Program = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.opengl);

const c = @import("c.zig").c;
const Shader = @import("Shader.zig");
const gl = @import("main.zig");
const glad = @import("glad.zig");

id: c.GLuint,

pub const Binding = struct {
    pub fn unbind(_: Binding) void {
        glad.context.UseProgram.?(0);
    }
};

pub fn create() !Program {
    const id = glad.context.CreateProgram.?();
    if (id == 0) try gl.mustError();
    log.debug("program created id={}", .{id});
    return .{ .id = id };
}

/// Create a program from a vertex and fragment shader source. This will
/// compile and link the vertex and fragment shader.
pub fn createVF(vsrc: [:0]const u8, fsrc: [:0]const u8) !Program {
    const vs = try Shader.create(c.GL_VERTEX_SHADER);
    try vs.setSourceAndCompile(vsrc);
    defer vs.destroy();

    const fs = try Shader.create(c.GL_FRAGMENT_SHADER);
    try fs.setSourceAndCompile(fsrc);
    defer fs.destroy();

    const p = try create();
    try p.attachShader(vs);
    try p.attachShader(fs);
    try p.link();

    return p;
}

pub fn destroy(p: Program) void {
    assert(p.id != 0);
    glad.context.DeleteProgram.?(p.id);
    log.debug("program destroyed id={}", .{p.id});
}

pub fn attachShader(p: Program, s: Shader) !void {
    glad.context.AttachShader.?(p.id, s.id);
    try gl.getError();
}

pub fn link(p: Program) !void {
    glad.context.LinkProgram.?(p.id);

    // Check if linking succeeded
    var success: c_int = undefined;
    glad.context.GetProgramiv.?(p.id, c.GL_LINK_STATUS, &success);
    if (success == c.GL_TRUE) {
        log.debug("program linked id={}", .{p.id});
        return;
    }

    log.err("program link failure id={} message={s}", .{
        p.id,
        std.mem.sliceTo(&p.getInfoLog(), 0),
    });
    return error.CompileFailed;
}

pub fn use(p: Program) !Binding {
    glad.context.UseProgram.?(p.id);
    try gl.getError();
    return .{};
}

pub fn uniformBlockBinding(
    self: Program,
    index: c.GLuint,
    binding: c.GLuint,
) !void {
    glad.context.UniformBlockBinding.?(self.id, index, binding);
    try gl.getError();
}

/// Requires the program is currently in use.
pub fn setUniform(
    p: Program,
    n: [:0]const u8,
    value: anytype,
) !void {
    const loc = glad.context.GetUniformLocation.?(
        p.id,
        @ptrCast(n.ptr),
    );
    if (loc < 0) {
        return error.UniformNameInvalid;
    }
    try gl.getError();

    // Perform the correct call depending on the type of the value.
    switch (@TypeOf(value)) {
        bool => glad.context.Uniform1i.?(loc, if (value) 1 else 0),
        comptime_int => glad.context.Uniform1i.?(loc, value),
        f32 => glad.context.Uniform1f.?(loc, value),
        @Vector(2, f32) => glad.context.Uniform2f.?(loc, value[0], value[1]),
        @Vector(3, f32) => glad.context.Uniform3f.?(loc, value[0], value[1], value[2]),
        @Vector(4, f32) => glad.context.Uniform4f.?(loc, value[0], value[1], value[2], value[3]),
        [4]@Vector(4, f32) => glad.context.UniformMatrix4fv.?(
            loc,
            1,
            c.GL_FALSE,
            @ptrCast(&value),
        ),
        else => {
            log.warn("unsupported uniform type {}", .{@TypeOf(value)});
            unreachable;
        },
    }
    try gl.getError();
}

/// getInfoLog returns the info log for this program. This attempts to
/// keep the log fully stack allocated and is therefore limited to a max
/// amount of elements.
//
// NOTE(mitchellh): we can add a dynamic version that uses an allocator
// if we ever need it.
pub fn getInfoLog(s: Program) [512]u8 {
    var msg: [512]u8 = undefined;
    glad.context.GetProgramInfoLog.?(s.id, msg.len, null, &msg);
    return msg;
}
