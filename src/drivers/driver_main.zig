const std = @import("std");
const Configuration = @import("../configuration.zig").Config;
const zigcli = @import("zigcli");
const pt = zigcli.pretty_table;
const Table = pt.Table;
const Cell = pt.Cell;

pub const Config = struct {
    file: []const u8 = "test.zig.zon",
    dotfile: ?[]const u8,

    pub const __messages__ = .{};
};

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

pub fn driver_main(init: std.process.Init, config: Config) !void {
    const alloc = init.gpa;
    const zonConfig = try Configuration.fromZonFile(init.arena.allocator(), init.io, config.file);
    defer zonConfig.deinit();

    var g = try zonConfig.calculateGraph(init.arena.allocator());
    defer g.deinit();

    if (config.dotfile) |file| {
        try g.dotFilename(init.io, file);
    }

    var table = pt.Table(1).Owned.init(.{
        .mode = .box,
        .padding = 1,
        .column_align = .{ .left },
        .row_separator = false,
    });
    defer table.deinit(alloc);
    table.setHeader(.{"Cycle"});

    var cycle_strs = std.ArrayList(std.ArrayList(u8)).empty;
    defer {
        for (cycle_strs.items) |*str|
            str.deinit(alloc);
        cycle_strs.deinit(alloc);
    }
    if (g.detectCycles()) |cycles| {
        for (cycles.items) |cycle| {
            var cycle_str = std.ArrayList(u8).empty;

            for (cycle.items, 0..) |node, i| {
                if (i != 0) {
                    try cycle_str.appendSlice(alloc, " -> ");
                }

                try cycle_str.appendSlice(alloc, node);
            }
            try cycle_strs.append(alloc, cycle_str);
            try table.addRow(alloc, .{cycle_str.items});
        }
    }

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    try writer.interface.print("{f}", .{table});
    try writer.interface.flush();
}
