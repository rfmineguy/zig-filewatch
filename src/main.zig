const std = @import("std");
const Io = std.Io;

const zig_filewatch = @import("zig_filewatch");
const graph = @import("graph.zig");
const configuration = @import("configuration.zig");
const Config = configuration.Config;
const Watcher = @import("watcher.zig").Watcher;
const zm = @import("zigmon");

const graph_constu8_driver = @import("drivers/graph_const_u8.zig").driver_constu8_graph;
const graph_u32_driver = @import("drivers/graph_u32.zig").driver_u32_graph;

const ConstU8Context = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        var h = std.hash.Wyhash.init(3497);  // <- change the hash algo according to your needs... (WyHash...)
        h.update(key);
        return h.final();
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    pub fn cmp(_: @This(), a: []const u8, b: []const u8) i8 {
        return switch (std.mem.order(u8, a, b)) {
            .eq => 0,
            .lt => -1,
            .gt => 1,
        };
    }

    pub fn format(_: @This(), v: []const u8, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{v});
    }
};

pub fn main(init: std.process.Init) !void {
    zm.init();
    defer zm.deinit();

    const config = try Config.fromZonFile(init.arena.allocator(), init.io, "test.zig.zon");
    defer config.deinit();

    var g = try graph.GraphWithContext([]const u8, ConstU8Context).init(init.arena.allocator());
    defer g.deinit();

    // std.debug.print("{f}\n", .{config});

    if (config.actions) |actions| {
        for (actions) |action| {
            try g.add(action.id);
        }
        for (actions) |action| {
            for (action.sequence) |seq_entry| {
                switch (seq_entry) {
                    .action => |a| {
                        try g.connect(action.id, a.?);
                    },
                    else => {},
                }
            }
        }
    }

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    try g.dot(&stdout_file_writer.interface);
    try stdout_file_writer.flush();

    // if (g.detectCycles()) |cycles| {
    //     for (cycles.items, 0..) |cycle, i| {
    //         std.log.debug("{d}: {any}\n", .{i, cycle});
    //     }
    // }

    // try graph_constu8_driver(init, .{.verbose = true});
    // try graph_u32_driver(init, .{.show_dot = true, .show_cycles = true});
}
