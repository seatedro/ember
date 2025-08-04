const ember = @import("../ember.zig");
const config = ember.config;
const game = @import("game");

const Context = ember.Context;

pub fn main() !void {
    const game_systems = game.ember_systems;

    var ctx = try ember.Context.init(game.cfg);
    defer ctx.deinit();

    try game_systems.init(ctx);
    defer game_systems.quit(ctx) catch {};

    while (ctx.running) {
        ctx.tick(game_systems.event, game_systems.update, game_systems.draw);
    }
}
