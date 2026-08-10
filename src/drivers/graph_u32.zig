const std = @import("std");
const graph = @import("../graph.zig");

pub const Config = struct {
    show_title: bool = false,
    show_dot: bool = false,
    show_dfs_traverse: bool = false,
    show_cycles: bool = false,
};

pub fn driver_u32_graph(init: std.process.Init, config: Config) !void {
    var g = try graph.Graph(u32).init(init.arena.allocator());
    defer g.deinit();

    try g.add(0);
    try g.add(1);
    try g.add(2);
    try g.add(3);
    try g.add(4);
    try g.add(5);
    try g.add(6);
    try g.add(7);


    // create binary tree
    //       0
    //     /   \
    //    1     2
    //   / \   /\
    //  3   4 5  6
    // /
    // 7
    try g.connect(0, 1);
    try g.connect(1, 0);
    try g.connect(0, 2);
    try g.connect(1, 3);
    try g.connect(1, 4);
    try g.connect(2, 5);
    try g.connect(2, 6);
    try g.connect(3, 7);
    try g.connect(7, 0);
    try g.connect(6, 0);

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);

    if (config.show_title) {
        std.debug.print("=============================\n", .{});
        std.debug.print("     driver_u32_graph\n", .{});
        std.debug.print("=============================\n", .{});
    }
    if (config.show_dot) {
        try g.dot(&stdout_file_writer.interface);
        try stdout_file_writer.flush();
    }
    if (config.show_dfs_traverse) {
        var it = try g.dfs();
        defer it.deinit();
        var idx: u32 = 0;
        while (try it.next()) |v| : (idx += 1) {
            std.debug.print("{any},", .{v});
        }
        std.debug.print("\n", .{});
    }


    if (config.show_cycles) {
        if (g.detectCycles()) |cycles| {
            for (cycles.items) |cycle| {
                std.log.debug("Cycle [", .{});
                for (cycle.items) |item| {
                    std.log.debug("{any},", .{item});
                }
                std.log.debug("]\n", .{});
            }
        }
    }
}
