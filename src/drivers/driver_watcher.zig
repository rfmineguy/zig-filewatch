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
    _ = config;
    zm.init();
    defer zm.deinit();

    var w = try watcher.Watcher.init(init.gpa);
    defer w.deinit();
    try w.addPattern("**/*.zig");
    try w.start(".");
    while (true) {}
}
