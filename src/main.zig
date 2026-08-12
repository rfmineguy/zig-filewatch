const std = @import("std");
const Io = std.Io;

const zig_filewatch = @import("zig_filewatch");
const graph = @import("graph.zig");
const configuration = @import("configuration.zig");
const Config = configuration.Config;
const Watcher = @import("watcher.zig").Watcher;
const zm = @import("zigmon");
const zigcli = @import("zigcli");
const structargs = zigcli.structargs;
const Options = @import("args.zig").Options;

const graph_constu8_driver = @import("drivers/graph_const_u8.zig").driver_constu8_graph;
const graph_u32_driver = @import("drivers/graph_u32.zig").driver_u32_graph;
const graph_from_config_driver = @import("drivers/graph_from_config.zig").graph_from_config_driver;
const driver_process_spawn = @import("drivers/driver_process_spawn.zig").driver_process_spawn;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = init.io;

    var opt = structargs.parse(alloc, io, init.minimal.args, Options, .{.print_help_on_error = true}) catch |err| {
        std.debug.print("error: {}\n", .{err});
        return;
    };
    defer opt.deinit();

    switch (opt.options.__commands__) {
        .driver_graph_const_u8 => |config|
            try graph_constu8_driver(init, config),
        .driver_graph_u32 => |config|
            try graph_u32_driver(init, config),
        .driver_graph_from_config => |config| 
            try graph_from_config_driver(init, config),
        .driver_process_spawn => |config|
            try driver_process_spawn(init, config),
    }
}
