const std = @import("std");
const zon = std.zon;
const graph = @import("graph.zig");
const wildmatch = @cImport(
    @cInclude("wildmatch.h")
);

pub const SequenceEntry = union(enum) {
    action: ?[]const u8,
    shell: ?[]const u8,
};

pub const WatcherCfg = struct {
    sequence: []SequenceEntry,
    patterns: []const []const u8,
};

pub const Action = struct {
    id: []const u8,
    sequence: []SequenceEntry,
};

pub const ConstU8Context = struct {
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

const ConfigData = struct {
    watchers: ?[]WatcherCfg,
    actions: ?[]Action,
};

pub const Config = struct {
    config_data: ConfigData,
    actions_map: std.HashMap([]const u8, *Action, ConstU8Context, std.hash_map.default_max_load_percentage),
    pub fn default() Config {
        return @This() {
            .watchers = null,
            .actions = null,
        };
    }
    pub fn format(self: Config, writer: *std.Io.Writer) !void {
        try zon.stringify.serialize(self.config_data, .{}, writer);
    }
    pub fn fromZonFile(alloc: std.mem.Allocator, io: std.Io, filepath: []const u8) !Config {
        const source = std.Io.Dir.cwd().readFileAlloc(io, filepath, alloc, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading '{s}': {}\n", .{ filepath, err });
            return error.ReadFailed;
        };
        defer alloc.free(source);

        const source_z = try alloc.allocSentinel(u8, source.len, 0);
        defer alloc.free(source_z);

        @memcpy(source_z[0..source_z.len], source);

        var diag: zon.parse.Diagnostics = .{};
        const parsed = zon.parse.fromSliceAlloc(ConfigData, alloc, source_z, &diag, .{}) catch |err| {
            printZonDiagnostic(source_z, &diag, err);
            return error.FailedParse;
        };
        var config = @This() {
            .config_data = parsed,
            .actions_map = .init(alloc),
        };

        if (parsed.actions) |actions| {
            for (actions) |*action| try config.actions_map.put(action.id, action);
        }

        // var it = config.actions_map.iterator();
        // while (it.next()) |pair| {
        //     std.debug.print("{s}: {any}\n", .{pair.key_ptr.*, pair.value_ptr.*});
        // }
        return config;
    }
    pub fn getWatcherCfgForFile(self: @This(), alloc: std.mem.Allocator, path: []const u8) ?WatcherCfg {
        if (self.config_data.watchers) |watchers| {
            for (watchers) |w| {
                for (w.patterns) |pattern| {
                    const c_pattern = std.fmt.allocPrintSentinel(alloc, "**/{s}", .{pattern}, 0) catch return null;
                    defer alloc.free(c_pattern);
                    const c_path = std.fmt.allocPrintSentinel(alloc, "{s}", .{path}, 0) catch return null;
                    defer alloc.free(c_path);

                    const v = wildmatch.wildmatch(c_pattern, c_path, wildmatch.WM_WILDSTAR);
                    if (v == wildmatch.WM_MATCH) {
                        return w;
                    }
                }
            }
        }
        return null;
    }
    pub fn getSequenceForFile(self: @This(), alloc: std.mem.Allocator, path: []const u8) ?[]SequenceEntry {
        return if (self.getWatcherCfgForFile(alloc, path)) |cfg| cfg.sequence else null;

    }
    fn printZonDiagnostic(
        source: []const u8,
        diag: *const std.zon.parse.Diagnostics,
        err: anyerror,
    ) void {
        std.debug.print("ZON Parse Error: {}\n", .{err});

        // Extract line and column information if available
        var it = diag.iterateErrors();
        while (it.next()) |zonErr| {
            const loc = zonErr.getLocation(diag);
            // Find the line text in the source to highlight the error snippet
            var line_it = std.mem.splitScalar(u8, source, '\n');
            var current_line: usize = 1;
            while (line_it.next()) |line_text| : (current_line += 1) {
                if (current_line == loc.line) {
                    std.debug.print("   {d: >3} | {s}\n", .{current_line ,line_text});
                    // Point directly to the offending column
                    std.debug.print("   {d: >3} | ", .{current_line + 1});
                    var i: usize = 0;
                    while (i < loc.column - 1) : (i += 1) {
                        std.debug.print(" ", .{});
                    }
                    std.debug.print("^\n", .{});
                    break;
                }
            }
        }
    }
    pub fn deinit(self: *@This()) void {
        self.actions_map.deinit();
    }
    pub fn calculateGraph(self: @This(), alloc: std.mem.Allocator) !graph.GraphWithContext([]const u8, ConstU8Context) {
        var graph_ = try graph.GraphWithContext([]const u8, ConstU8Context).init(alloc);
        if (self.config_data.actions) |actions| {
            for (actions) |action| {
                const id = action.id;
                try graph_.add(id);
            }
            for (actions) |action| {
                for (action.sequence) |seq_entry| {
                    switch (seq_entry) {
                        .shell => |shell| {
                            _ = shell;
                        },
                        .action => |action_| {
                             try graph_.connect(action.id, action_.?);
                        },
                    }
                }
            }
        }
        return graph_;
    }
};

test "load config" {
    const alloc = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer alloc.deinit();

    const config: Config = Config.fromZonFile(alloc.child_allocator, std.testing.io, "test.zig.zon") catch Config.default();
    defer config.deinit();
    std.debug.print("{f}\n", .{config});
}
