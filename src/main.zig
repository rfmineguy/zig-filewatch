const std = @import("std");
const Io = std.Io;

const zig_filewatch = @import("zig_filewatch");
const Graph = @import("graph.zig").Graph;

pub fn main(init: std.process.Init) !void {
    var g = try Graph(u32).init(init.arena.allocator());
    defer g.deinit();

    try g.add(4);
}
