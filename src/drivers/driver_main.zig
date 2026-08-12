const std = @import("std");
const Configuration = @import("../configuration.zig");
const ZigFilewatchConfig = Configuration.Config;
const graph = @import("../graph.zig");
const zigcli = @import("zigcli");
const pt = zigcli.pretty_table;
const Table = pt.Table;
const Cell = pt.Cell;

pub const Config = struct {
    file: []const u8 = "test.zig.zon",
    show_cycles: bool = false,
    dotfile: ?[]const u8,
    action: ?[]const u8,

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

fn show_cycles(init: std.process.Init, cycles: std.ArrayList(std.ArrayList([]const u8))) !void {
    var table = pt.Table(1).Owned.init(.{
        .mode = .box,
        .padding = 1,
        .column_align = .{ .left },
        .row_separator = false,
    });
    defer table.deinit(init.gpa);
    table.setHeader(.{"Cycle"});

    var cycle_strs = std.ArrayList(std.ArrayList(u8)).empty;
    defer {
        for (cycle_strs.items) |*str|
            str.deinit(init.gpa);
        cycle_strs.deinit(init.gpa);
    }

    for (cycles.items) |cycle| {
        var cycle_str = std.ArrayList(u8).empty;

        for (cycle.items, 0..) |node, i| {
            if (i != 0) {
                try cycle_str.appendSlice(init.gpa, " -> ");
            }

            try cycle_str.appendSlice(init.gpa, node);
        }
        try cycle_strs.append(init.gpa, cycle_str);
        try table.addRow(init.gpa, .{cycle_str.items});
    }

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    try writer.interface.print("{f}", .{table});
    try writer.interface.flush();
}

fn run_action(init: std.process.Init, g: *graph.GraphWithContext([]const u8,Configuration.ConstU8Context), action: []const u8) !void {
    _ = init;
    _ = g;
    _ = action;
}

pub fn driver_main(init: std.process.Init, config: Config) !void {
    const zonConfig = try ZigFilewatchConfig.fromZonFile(init.arena.allocator(), init.io, config.file);
    defer zonConfig.deinit();

    var g = try zonConfig.calculateGraph(init.arena.allocator());
    defer g.deinit();

    if (config.dotfile) |file| {
        try g.dotFilename(init.io, file);
    }

    if (config.show_cycles) {
        if (g.detectCycles()) |cycles| try show_cycles(init, cycles);
    }

    if (config.action) |action| {
        if (g.detectCycles()) |cycles| {
            if (cycles.items.len != 0) {
                try show_cycles(init, cycles);
                std.debug.print("Error: can't run with cycles present\n", .{});
            }
            return;
        }
        try run_action(init, &g, action);
    }
}
