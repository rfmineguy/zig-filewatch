const std = @import("std");
const graph = @import("../graph.zig");
const Config = @import("driver.zig").Config;

const ConstU8Context = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        var h = std.hash.Wyhash.init(3497);  // <- change the hash algo according to your needs... (WyHash...)
        h.update(key);
        return h.final();
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};
pub fn driver_constu8_graph(init: std.process.Init, config: Config) !void {
    var g = try graph.GraphWithContext([]const u8, ConstU8Context).init(init.arena.allocator());
    defer g.deinit();

    try g.add("0");
    try g.add("1");
    try g.add("2");
    try g.add("3");
    try g.add("4");
    try g.add("5");
    try g.add("6");

    // create binary tree
    //     0
    //    / \
    //   1   2
    //  / \   \
    // 3   4   5
    //      \
    //       6
    try g.connect("0", "1");
    try g.connect("0", "2");
    try g.connect("1", "3");
    try g.connect("1", "4");
    try g.connect("2", "5");
    try g.connect("4", "6");

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);

    if (config.verbose) {
        std.debug.print("=============================\n", .{});
        std.debug.print("     driver_constu8_graph\n", .{});
        std.debug.print("=============================\n", .{});
        try g.dot(&stdout_file_writer.interface);
        try stdout_file_writer.flush();
    }
}
