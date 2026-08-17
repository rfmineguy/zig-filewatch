const std = @import("std");
const nightwatch = @import("nightwatch");
const confguration = @import("../configuration.zig");

pub const Config = struct {
    root_directory: []const u8 = ".",
};


pub fn driver_watcher(init: std.process.Init, config: Config) !void {

    const Watcher = nightwatch.Create(nightwatch.default_variant);
    const H = struct {
        handler: Watcher.Handler,

        const vtable = Watcher.Handler.VTable{ .change = change, .rename = rename };

        fn change(_: *Watcher.Handler, path: []const u8, event: nightwatch.EventType, _: nightwatch.ObjectType) error{HandlerFailed}!void {
            std.debug.print("{s}  {s}\n", .{ @tagName(event), path });
        }

        fn rename(_: *Watcher.Handler, src: []const u8, dst: []const u8, _: nightwatch.ObjectType) error{HandlerFailed}!void {
            std.debug.print("rename  {s}  ->  {s}\n", .{ src, dst });
        }
    };
    
    var h = H{ .handler = .{ .vtable = &H.vtable } };
    var watcher = try nightwatch.Default.init(init.io, init.gpa, &h.handler);
    try watcher.watch(config.root_directory);

    while (true) {}
}
