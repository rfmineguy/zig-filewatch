const std = @import("std");
const Io = std.Io;

const zig_filewatch = @import("zig_filewatch");
const graph = @import("graph.zig");
const Config = @import("configuration.zig").Config;
const test_ = @import("test.zig");

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
pub fn main(init: std.process.Init) !void {
    var g = try graph.GraphWithContext([]const u8, ConstU8Context).init(init.arena.allocator());
    defer g.deinit();

    const config = Config.fromZonFile(init.arena.allocator(), init.io, "test.zig.zon") catch Config.default();
    defer config.deinit();

    if (config.actions) |actions| {
        for (actions) |item| {
            try g.add(item.id);
        }
        for (actions) |item| {
            for (item.sequence) |seq| {
                switch (seq) {
                    .action => |v| {
                        try g.connect(item.id, v.?);
                    },
                    .shell => {},
                }
            }
        }
    }

    // std.debug.print("{}", .{g});

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);

    try g.dot(&stdout_file_writer.interface);
    try stdout_file_writer.flush();
    // var it = try g.bfs();
    // while (try it.next()) |v| {
    //     std.debug.print("v={s}\n", .{v});
    // }

    // try g.add("hello");
}
