const std = @import("std");
const zm = @import("zigmon");
const watcher = @import("../watcher.zig");

const Watcher = zm.Watcher(i64);

pub const Config = struct {
    root_directory: []const u8 = ".",
};


fn on_change(w: Watcher, action: zm.Action, path: []const u8, oldpath: ?[]const u8) void {
    _ = action;
    _ = oldpath;
    std.debug.print("\nSomething happened ({}): {s}\n", .{w.data, path});
}

pub fn driver_watcher(init: std.process.Init, config: Config) !void {
    _ = init;
    _ = config;
    zm.init();
    defer zm.deinit();

    var my_watcher: Watcher = .{
        .root = ".",
        .data = 1337,

        .on_change = on_change,
    };
    try my_watcher.watch();
    defer my_watcher.unwatch();

    while (true) {}
}
