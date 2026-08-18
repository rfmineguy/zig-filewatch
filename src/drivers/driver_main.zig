const std = @import("std");
const Configuration = @import("../configuration.zig");
const ZigFilewatchConfig = Configuration.Config;
const graph = @import("../graph.zig");
const zigcli = @import("zigcli");
const pt = zigcli.pretty_table;
const Table = pt.Table;
const Cell = pt.Cell;
const shell_action = @import("../shell_action.zig");
const nightwatch = @import("nightwatch");
const runbatch = @import("../runBatch.zig");

// const zm = @import("zigmon");
// const watcher = @import("../watcher.zig");
const ConcurrentQueue = @import("../event_queue.zig").ConcurrentQueue;

const U8Graph = graph.GraphWithContext([]const u8, Configuration.ConstU8Context);

pub const Config = struct {
    file: []const u8 = "test.zig.zon",
    show_cycles: bool = false,
    dotfile: ?[]const u8,
    action: ?[]const u8,
    watch: bool = false,
    verbose: bool = false,

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

fn run_sequence(init: std.process.Init, zoncfg: ZigFilewatchConfig, g: *U8Graph, seq: []Configuration.SequenceEntry, output_map: *std.StringHashMap(shell_action.CmdResult), node: std.Progress.Node) !void {
    const n = node.start(seq.len);
    defer n.end();
    for (seq) |seq_item| {
        switch (seq_item) {
            .shell => |s| {
                var parts = std.ArrayList([]const u8).empty;
                errdefer parts.deinit(init.gpa);

                var it = std.mem.tokenizeScalar(u8, s.?, ' ');
                while (it.next()) |part| try parts.append(init.gpa, part);

                const argv = try parts.toOwnedSlice(init.gpa);
                defer init.gpa.free(argv);

                const shell_node = n.start(argv[0], 1);
                defer shell_node.end();
                var shell = shell_action.ShellAction.init(init.gpa, init.io, argv);
                defer shell.deinit();
                const result = try shell.execute();
                shell_node.completeOne();
                try output_map.put(argv[0], result);
            },
            .action => |a| {
                if (zoncfg.actions_map.get(a.?)) |action| {
                    try run_sequence(init, zoncfg, g, action.sequence, output_map, n);
                }
            },
        }
        n.completeOne();
    }
}

fn run_action(init: std.process.Init, zoncfg: ZigFilewatchConfig, g: *U8Graph, action_name: []const u8, output_map: *std.StringHashMap(shell_action.CmdResult), node: std.Progress.Node) !void {
    if (zoncfg.config_data.actions == null) return error.NullActions;
    if (zoncfg.actions_map.get(action_name) == null) return error.NoActionForActionName;
    if (g.nodes.get(action_name) == null) return error.NullAction;
    // std.debug.print("{any}\n", .{g.nodes.get(action_name).?});
    // std.debug.print("Running action {s} [{d} dependencies]\n", .{action_name, zoncfg.actions_map.get(action_name).?.sequence.len});

    const thisnode = node.start(action_name, zoncfg.actions_map.get(action_name).?.sequence.len);
    defer thisnode.end();
    for (zoncfg.actions_map.get(action_name).?.sequence) |entry| {
        switch (entry) {
            .shell => |s| {
                // std.debug.print("Executing shell seq entry {s}\n", .{s.?});
                var parts = std.ArrayList([]const u8).empty;
                errdefer parts.deinit(init.gpa);

                var it = std.mem.tokenizeScalar(u8, s.?, ' ');
                while (it.next()) |part| try parts.append(init.gpa, part);

                const argv = try parts.toOwnedSlice(init.gpa);
                defer init.gpa.free(argv);

                const shell_node = thisnode.start(s.?, 1);
                defer shell_node.end();
                var shell = shell_action.ShellAction.init(init.arena.allocator(), init.io, argv);
                defer shell.deinit();
                const result = try shell.execute();
                shell_node.completeOne();
                try output_map.put(s.?, result);

            },
            .action => |action| {
                // std.debug.print("Executing action seq entry: '{s}'\n", .{action.?});
                try run_action(init, zoncfg, g, action.?, output_map, thisnode);
                thisnode.completeOne();
            }
        }
    }
    try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(100), .awake);
}

pub fn driver_main(init: std.process.Init, config: Config) !void {
    var zonConfig = try ZigFilewatchConfig.fromZonFile(init.arena.allocator(), init.io, config.file);
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
                return;
            }
        }
        var progress = std.Progress.start(init.io, .{
            .root_name = action,
        });
        defer progress.end();
        var outputs = std.StringHashMap(shell_action.CmdResult).init(init.arena.allocator());
        defer outputs.deinit();
        defer {
            var it = outputs.iterator();
            while (it.next()) |v| {
                switch (v.value_ptr.*) {
                    .success => |v_| {
                        defer v_.deinit();

                        std.debug.print("Command {s}\n", .{v.key_ptr.*});
                        std.debug.print("   stdout: {s}\n", .{v_.stdout.?});
                        std.debug.print("   stderr: {s}\n", .{v_.stderr.?});
                    },
                    .fail => |err| {
                        std.debug.print("Error: {any}\n", .{err});
                    },
                }
            }
        }
        // std.debug.print("Running action: {s}\n", .{action});
        try run_action(init, zonConfig, &g, action, &outputs, progress);
        try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(1), .awake);
    }

    if (config.watch) {
        if (zonConfig.config_data.watchers == null) return error.NoWatchersConfigured;
        if (g.detectCycles()) |cycles| {
            if (cycles.items.len != 0) {
                try show_cycles(init, cycles);
                std.debug.print("Error: can't run with cycles present\n", .{});
                return;
            }
        }

        const Watcher = nightwatch.Create(nightwatch.default_variant);
        const Event = union(enum) {
            change: struct {
                path: []const u8,
                event: nightwatch.EventType,
                object: nightwatch.ObjectType,
            },

            rename: struct {
                src: []const u8,
                dst: []const u8,
                object: nightwatch.ObjectType,
            },
        };
        const H = struct {
            handler: Watcher.Handler,
            queue: *ConcurrentQueue(Event),

            const vtable = Watcher.Handler.VTable{ .change = change, .rename = rename };

            fn change(handler: *Watcher.Handler, path: []const u8, event: nightwatch.EventType, object: nightwatch.ObjectType) error{HandlerFailed}!void {
                const self: *@This() = @fieldParentPtr("handler", handler);
                self.queue.enqueue(.{
                    .change = .{
                        .path = path,
                        .event = event,
                        .object = object,
                    },
                }) catch return error.HandlerFailed;
            }

            fn rename(handler: *Watcher.Handler, src: []const u8, dst: []const u8, object: nightwatch.ObjectType) error{HandlerFailed}!void {
                const self: *@This() = @fieldParentPtr("handler", handler);
                self.queue.enqueue(.{
                    .rename = .{
                        .dst = dst,
                        .src = src,
                        .object = object,
                    },
                }) catch return error.HandlerFailed;
            }
        };
        
        var queue = try ConcurrentQueue(Event).init(init.io, init.gpa);
        defer queue.deinit();

        std.debug.print("Starting watcher...\n", .{});
        var h = H{ .queue = &queue, .handler = .{ .vtable = &H.vtable } };
        var watcher = try nightwatch.Default.init(init.io, init.gpa, &h.handler);
        try watcher.watch(".");
        std.debug.print("Started watcher...\n", .{});

        var runBatch = try runbatch.RunBatch(Event).init(init.gpa, init.io);
        defer runBatch.deinit();

        const progress = std.Progress.start(init.io, .{});
        defer progress.end();
        while (true) {
            var outputs = std.StringHashMap(shell_action.CmdResult).init(init.arena.allocator());
            defer outputs.deinit();
            try runBatch.next(&queue);
            defer runBatch.end();

            if (try runBatch.empty()) continue;

            const node = progress.start("watch", runBatch.events.items.len);
            defer node.end();

            for (runBatch.events.items) |event| {
                switch (event) {
                    .change => |ch| {
                        const seq = zonConfig.getSequenceForFile(init.gpa, ch.path) orelse continue;
                        for (seq) |item| {
                            switch (item) {
                                .action => |action| {
                                    run_action(init, zonConfig, &g, action.?, &outputs, node) catch std.debug.print("Error running action {s}\n", .{action.?});
                                },
                                .shell => |shell| {
                                    _ = shell;
                                }
                            }
                            node.completeOne();
                        }
                    },
                    .rename => |rn| { _ = rn; },
                }
            }
        }
    }
}
