pub const c = @import("c.zig").c;
pub const glad = @import("glad.zig");
pub const Buffer = @import("Buffer.zig");
pub const Framebuffer = @import("FrameBuffer.zig");
pub const Program = @import("Program.zig");
pub const Shader = @import("Shader.zig");
pub const Texture = @import("Texture.zig");
pub const VertexArray = @import("VertexArray.zig");
const std = @import("std");

pub const Error = error{
    InvalidEnum,
    InvalidValue,
    InvalidOperation,
    InvalidFramebufferOperation,
    OutOfMemory,

    Unknown,
};

/// getError returns the error (if any) from the last OpenGL operation.
pub fn getError() Error!void {
    return switch (glad.context.GetError.?()) {
        c.GL_NO_ERROR => {},
        c.GL_INVALID_ENUM => Error.InvalidEnum,
        c.GL_INVALID_VALUE => Error.InvalidValue,
        c.GL_INVALID_OPERATION => Error.InvalidOperation,
        c.GL_INVALID_FRAMEBUFFER_OPERATION => Error.InvalidFramebufferOperation,
        c.GL_OUT_OF_MEMORY => Error.OutOfMemory,
        else => Error.Unknown,
    };
}

/// mustError just calls getError but always results in an error being returned.
/// If getError has no error, then Unknown is returned.
pub fn mustError() Error!void {
    try getError();
    return Error.Unknown;
}

pub fn clearColor(r: f32, g: f32, b: f32, a: f32) void {
    glad.context.ClearColor.?(r, g, b, a);
}

pub fn clear(mask: c.GLbitfield) void {
    glad.context.Clear.?(mask);
}

pub fn drawArrays(mode: c.GLenum, first: c.GLint, count: c.GLsizei) !void {
    glad.context.DrawArrays.?(mode, first, count);
    try getError();
}

pub fn drawElements(mode: c.GLenum, count: c.GLsizei, typ: c.GLenum, offset: usize) !void {
    const offsetPtr = if (offset == 0) null else @as(*const anyopaque, @ptrFromInt(offset));
    glad.context.DrawElements.?(mode, count, typ, offsetPtr);
    try getError();
}

pub fn drawElementsInstanced(
    mode: c.GLenum,
    count: c.GLsizei,
    typ: c.GLenum,
    primcount: usize,
) !void {
    glad.context.DrawElementsInstanced.?(mode, count, typ, null, @intCast(primcount));
    try getError();
}

pub fn enable(cap: c.GLenum) !void {
    glad.context.Enable.?(cap);
    try getError();
}

pub fn frontFace(mode: c.GLenum) !void {
    glad.context.FrontFace.?(mode);
    try getError();
}

pub fn blendFunc(sfactor: c.GLenum, dfactor: c.GLenum) !void {
    glad.context.BlendFunc.?(sfactor, dfactor);
    try getError();
}

pub fn viewport(x: c.GLint, y: c.GLint, width: c.GLsizei, height: c.GLsizei) !void {
    glad.context.Viewport.?(x, y, width, height);
}

pub fn pixelStore(mode: c.GLenum, value: anytype) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .ComptimeInt, .Int => glad.context.PixelStorei.?(mode, value),
        else => unreachable,
    }
    try getError();
}
