const std = @import("std");
const graph = @import("../graph.zig");
const shell_action = @import("../shell_action.zig");

pub const Config = struct {
    show_all: bool = true,
};
const StringList = struct {
    values: []const []const u8,

    pub fn format(
        self: StringList,
        writer: *std.Io.Writer,
    ) !void {
        try writer.writeByte('[');

        for (self.values, 0..) |value, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{s}", .{value});
        }

        try writer.writeByte(']');
    }
};
fn helper(alloc: std.mem.Allocator, io: std.Io, config: Config, index: u32, argv: []const []const u8) !void {
    _ = config;
    std.debug.print("==========================\n", .{});
    std.debug.print("Shell Action {d} ({f})\n", .{index, StringList{.values = argv}});
    std.debug.print("==========================\n", .{});
    var sa = shell_action.ShellAction.init(alloc, io, argv);
    defer sa.deinit();
    const handles = sa.execute();
    if (handles) |h| {
        if (h.stdout) |buf| std.debug.print("stdout:\n {s}\n", .{buf});
        if (h.stderr) |buf| std.debug.print("stderr:\n {s}\n", .{buf});
    }
}

pub fn driver_process_spawn(init: std.process.Init, config: Config) !void {
    const alloc = init.arena.allocator();
    const io = init.io;

    try helper(alloc, io, config, 0, &.{ "ls" });
    try helper(alloc, io, config, 1, &.{ "echo", "hello", "world" });
    try helper(alloc, io, config, 2, &.{ "uname" });
    try helper(alloc, io, config, 3, &.{ "uname", "-r" });

    std.debug.print("driver_process_spawn... finished\n", .{});
}
