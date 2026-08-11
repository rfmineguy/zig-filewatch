const std = @import("std");
const graph = @import("../graph.zig");
const Configuration =  @import("../configuration.zig").Config;

pub const Config = struct {
    file: []const u8,
    generate_dot_file: ?[]const u8,
    show_cycles: bool = false,
    show_dot: bool = false,
    show_title: bool = false,
    show_all: bool = false,

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

pub fn graph_from_config_driver(init: std.process.Init, config: Config) !void {
    const zonConfig = try Configuration.fromZonFile(init.arena.allocator(), init.io, config.file);
    defer zonConfig.deinit();

    var g = try zonConfig.calculateGraph(init.arena.allocator());
    defer g.deinit();

    if (config.generate_dot_file) |fp|
        try g.dotFilename(init.io, fp);

    if (config.show_dot) {
        const io = init.io;
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
        try g.dot(&stdout_file_writer.interface);
        try stdout_file_writer.flush();
    }

    if (config.show_cycles or config.show_all) {
        var actual = g.detectCycles();
        std.debug.print("cycles: {}\n", .{ actual.?.items.len });
        for (actual.?.items) |*actual_cycle| {
            for (actual_cycle.items, 0..) |item, i| {
                std.debug.print("{s}", .{item});
                if (i != actual_cycle.items.len - 1) std.debug.print(",", .{});
            }
            std.debug.print("\n", .{});
            actual_cycle.deinit(g.alloc);
        }
        actual.?.deinit(g.alloc);
    }
}
