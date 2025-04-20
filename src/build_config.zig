const Config = @import("build/Config.zig");

const config = Config.fromOptions();
pub const renderer = config.renderer;
