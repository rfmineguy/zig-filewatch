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

pub fn main(init: std.process.Init) !void {
    zm.init();
    defer zm.deinit();

    // try graph_constu8_driver(init, .{.verbose = true});
    try graph_u32_driver(init, .{.show_dfs_traverse = true, .show_dot = true});
}
