const std = @import("std");
const testing = std.testing;
const zm = @import("zigmon");
const ZMWatcher = zm.Watcher(i64);
const wildmatch = @cImport(
    @cInclude("wildmatch.h")
);
const event_queue = @import("event_queue.zig");

var idx: u32 = 0;

pub const Watcher = struct {
    alloc: std.mem.Allocator,
    watcher: ZMWatcher,
    patterns: std.ArrayList([]const u8),
    callback: ?*const fn(file: []const u8) void = null,
    shared_queue: ?*event_queue.ConcurrentQueue([]const u8),
    idx: u32,
    pub fn init(alloc: std.mem.Allocator, queue: ?*event_queue.ConcurrentQueue([]const u8)) !@This() {
        idx += 1;
        return .{
            .alloc = alloc,
            .watcher = undefined,
            .patterns = try .initCapacity(alloc, 10),
            .shared_queue = queue,
            .idx = idx,
        };
    }
    pub fn deinit(self: *@This()) void {
        self.patterns.deinit(self.alloc);
    }
    pub fn addPattern(self: *@This(), pattern: []const u8) !void {
        try self.patterns.append(self.alloc, pattern);
    }

    pub fn start(self: *@This(), root: [*c]const u8) !void {
        self.watcher = .{
            .root = root,
            .data = 1337,
            .user_ptr = self,
            .on_change = Watcher.on_change,
        };
        try self.watcher.watch();
        std.debug.print("Started watcher {d} with patterns:", .{self.idx});
        for (self.patterns.items) |p| std.debug.print("{s}, ", .{p});
        std.debug.print("\n", .{});
    }

    pub fn stop(self: *@This()) void {
        self.watcher.unwatch();
        std.debug.print("Stopped watcher with patterns: {}\n", .{self.patterns});
    }

    pub fn on_change(watcher: ZMWatcher, action: zm.Action, path: []const u8, oldpath: ?[]const u8) void {
        _ = action;
        _ = oldpath;

        if (watcher.user_ptr) |ptr| {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            // for (self.patterns.items) |p| std.debug.print("{s}, ", .{p});
            const c_path = std.fmt.allocPrintSentinel(self.alloc, "{s}", .{path}, 0) catch "error";
            defer self.alloc.free(c_path);
            for (self.patterns.items) |pattern| {
                const c_pattern = std.fmt.allocPrintSentinel(self.alloc, "{s}", .{pattern}, 0) catch "error";
                defer self.alloc.free(c_pattern);
                // std.debug.print("matching {s} with {s}\n", .{path, pattern});
                const v = wildmatch.wildmatch(c_pattern, c_path, wildmatch.WM_WILDSTAR);
                if (v == wildmatch.WM_MATCH) {
                    if (self.shared_queue) |q| {
                        const owned = self.alloc.dupe(u8, path) catch return;
                        errdefer self.alloc.free(owned);
                        q.enqueue(owned) catch return;
                    }
                    // std.debug.print("{s} matched {s}\n", .{path, pattern});
                }
            }
        }
    }
};
