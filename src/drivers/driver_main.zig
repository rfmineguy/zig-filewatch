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

const ProcessTree = @import("../process_tree.zig").ProcessTree;
const Process = @import("../process.zig").Process;
const process_events = @import("../process_events.zig");

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

    // the following apply to --watch mode
    //   0 - root, 1 - action, 2 - shell
    __internal_mode: ?u32 = 0,
    //   if __internal_mode is 1, this should have a value
    __internal__run: ?[]const u8 = null,
    /// These are passed only between filewatch's managed processes.  The FD is
    /// inherited across exec, so nested actions can report to the same root.
    __internal_event_fd: ?std.posix.fd_t = null,
    __internal_process_id: ?u64 = null,

    pub const __messages__ = .{};
};

fn eventReader(fd: std.posix.fd_t, queue: *ConcurrentQueue(process_events.Event)) void {
    while (true) {
        var bytes: [process_events.Event.wire_len]u8 = undefined;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const count = std.c.read(fd, bytes[offset..].ptr, bytes.len - offset);
            if (count <= 0) return;
            offset += @intCast(count);
        }
        const event = process_events.Event.decode(&bytes) catch continue;
        queue.enqueue(event) catch return;
    }
}

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
        // TODO
        //   We are moving to a process tree oriented architecture, where a parent waits on its children before marking as finished
        //    - this allows us to cleanly kill a process and its children when a new watch event comes through
        //    - this also may allow us to more easily implement concurrent actions
        //    - progress would be tracked simply by waiting for the process handle to exit, and reporting its status
        //    - children notify root of new what's going on
        //
        //   root
        //    \__ build_zig             (action)
        //        \__ zig build         (shell)
        //
        // root
        if (config.__internal_mode == 0) {
            if (zonConfig.config_data.watchers == null) return error.NoWatchersConfigured;
            if (g.detectCycles()) |cycles| {
                if (cycles.items.len != 0) {
                    try show_cycles(init, cycles);
                    std.debug.print("Error: can't run with cycles present\n", .{});
                    return;
                }
            }
            const Watcher = nightwatch.Create(nightwatch.default_variant);
            var arg_it = std.process.Args.Iterator.init(init.minimal.args);
            const executable = arg_it.next() orelse return error.MissingExecutablePath;
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

            var process_tree = try ProcessTree.init(init.gpa);
            defer process_tree.deinit();
        
            var queue = try ConcurrentQueue(Event).init(init.io, init.gpa);
            defer queue.deinit();
            var event_queue = try ConcurrentQueue(process_events.Event).init(init.io, init.gpa);
            defer event_queue.deinit();

            var event_fds: [2]std.posix.fd_t = undefined;
            if (std.c.pipe(&event_fds) != 0) return error.EventPipeFailed;
            defer _ = std.posix.system.close(event_fds[0]);
            defer _ = std.posix.system.close(event_fds[1]);
            const reader_thread = try std.Thread.spawn(.{}, eventReader, .{ event_fds[0], &event_queue });
            reader_thread.detach();

            std.debug.print("Starting watcher...\n", .{});
            var h = H{ .queue = &queue, .handler = .{ .vtable = &H.vtable } };
            var watcher = try nightwatch.Default.init(init.io, init.gpa, &h.handler);
            try watcher.watch(".");
            std.debug.print("Started watcher...\n", .{});

            while (true) {
                while (try event_queue.dequeue()) |event| {
                    const state: Process.State = switch (event.kind) {
                        .started => .running,
                        .finished => .finished,
                        .failed => .failed,
                        .cancelled => .cancelled,
                    };
                    process_tree.handleEvent(event.process_id, state);
                    std.debug.print("{s} process {d} (status {d})\n", .{ @tagName(event.kind), event.process_id, event.status });
                }
                while (try queue.dequeue()) |event| {
                    const sequence = switch (event) {
                        .change => |change| zonConfig.getSequenceForFile(init.arena.allocator(), change.path),
                        .rename => |rename| zonConfig.getSequenceForFile(init.arena.allocator(), rename.dst),
                    } orelse continue;
                    for (sequence) |entry| {
                        const action = switch (entry) {
                            .action => |name| name orelse continue,
                            // Shell entries deliberately stay inside an action process. A
                            // watcher sequence should name an action so it can be cancelled.
                            .shell => continue,
                        };
                        try process_tree.cancel(action);
                        const process_id = process_tree.nextId();
                        const fd_text = try std.fmt.allocPrint(init.arena.allocator(), "{d}", .{event_fds[1]});
                        const id_text = try std.fmt.allocPrint(init.arena.allocator(), "{d}", .{process_id});
                        const argv = [_][]const u8{
                            executable, "driver_main", "--file", config.file, "--watch",
                            "--__internal_mode", "1", "--__internal__run", action,
                            "--__internal_event_fd", fd_text, "--__internal_process_id", id_text,
                        };
                        _ = try process_tree.spawn(init, null, action, &argv);
                    }
                }
            }
        }
        // action
        else if (config.__internal_mode == 1) {
            const action = config.__internal__run orelse return error.MissingInternalAction;
            const fd = config.__internal_event_fd orelse return error.MissingEventPipe;
            const process_id = config.__internal_process_id orelse return error.MissingProcessId;
            try process_events.write(fd, .{ .kind = .started, .process_id = process_id });
            var outputs = std.StringHashMap(shell_action.CmdResult).init(init.arena.allocator());
            defer outputs.deinit();
            var progress = std.Progress.start(init.io, .{ .root_name = action });
            defer progress.end();
            run_action(init, zonConfig, &g, action, &outputs, progress) catch |err| {
                process_events.write(fd, .{ .kind = .failed, .process_id = process_id, .status = -1 }) catch {};
                return err;
            };
            try process_events.write(fd, .{ .kind = .finished, .process_id = process_id });
        }
        // shell
        else if (config.__internal_mode == 2) {
        }
        // unknown
        else unreachable;
    }
}
