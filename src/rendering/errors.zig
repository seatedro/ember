const std = @import("std");

pub const RenderError = error{
    InitializationFailed,
    BeginFrameFailed,
    EndFrameFailed,
    RenderImGuiFailed,
    ResizeFailed,
    UnsupportedBackend,
    SdlError,
    VSyncFailed,
    OutOfMemory,

    ShaderCompileFailed,
    ShaderLinkFailed,

    InvalidParameter,
    InvalidOperation,
    InvalidState,

    TextureLoadFailed,
    BufferCreationFailed,

    Unknown,
};

pub inline fn errifyGL(result: anytype) @TypeOf(result) {
    if (@typeInfo(@TypeOf(result)) == .error_union) {
        return result catch |err| switch (err) {
            error.OutOfMemory => return RenderError.OutOfMemory,
            error.InvalidEnum => return RenderError.InvalidParameter,
            error.InvalidValue => return RenderError.InvalidParameter,
            error.InvalidOperation => return RenderError.InvalidOperation,
            error.InvalidFramebufferOperation => return RenderError.InvalidState,
            error.Unknown => return RenderError.Unknown,
            else => return RenderError.Unknown,
        };
    } else {
        return result;
    }
}
