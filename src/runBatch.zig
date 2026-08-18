const ConcurrentQueue = @import("event_queue.zig").ConcurrentQueue;
const std = @import("std");

pub fn RunBatch(T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        sem: std.Io.Semaphore,
        io: std.Io,
        events: std.ArrayList(T),
        progress: ?std.Progress.Node,
        pub fn init(alloc: std.mem.Allocator, io: std.Io) !@This() {
            var sem = std.Io.Semaphore{};
            sem.post(io);
            return @This() {
                .alloc = alloc,
                .events = try .initCapacity(alloc, 10),
                .io = io,
                .sem = sem,
                .progress = null,
            };
        }
        pub fn deinit(self: *@This()) void {
            self.events.deinit(self.alloc);
        }
        pub fn wait(self: *@This()) !void {
            try self.sem.wait(self.io);
        }
        pub fn clear(self: *@This()) !void {
            self.events.clearRetainingCapacity();
        }
        pub fn empty(self: @This()) !bool {
            return self.events.items.len == 0;
        }
        pub fn next(self: *@This(), queue: *ConcurrentQueue(T)) !void {
            try self.sem.wait(self.io);
            errdefer self.sem.post(self.io);

            try self.clear();
            try queue.wait();
            while (try queue.dequeue()) |v| {
                try self.add(v);
            }
        }
        pub fn add(self: *@This(), v: T) !void {
            try self.events.append(self.alloc, v);
        }
        pub fn start(self: *@This()) std.Progress.Node {
            if (self.progress) |_| {}
            else self.progress = std.Progress.start(self.io, .{});

            return self.progress.?;
        }
        pub fn end(self: *@This()) void {
            if (self.progress) |progress| {
                progress.end();
                self.progress = null;
            }

            self.sem.post(self.io);
        }
    };
}
