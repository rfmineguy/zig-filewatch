const std = @import("std");
const testing = std.testing;

pub fn ConcurrentQueue(T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        mutex: std.Io.Mutex,
        sem: std.Io.Semaphore,
        io: std.Io,
        queue__internal: std.ArrayList(T),
        pub fn init(io: std.Io, alloc: std.mem.Allocator) !@This() {
            return @This() {
                .alloc = alloc,
                .io = io,
                .mutex = .init,
                .sem = .{},
                .queue__internal = try .initCapacity(alloc, 10),
            };
        }
        pub fn deinit(self: *@This()) void {
            self.queue__internal.deinit(self.alloc);
        }
        pub fn enqueue(self: *@This(), v: T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);

            try self.queue__internal.append(self.alloc, v);
            self.sem.post(self.io);
        }
        pub fn wait(self: *@This()) !void {
            try self.sem.wait(self.io);
        }
        pub fn dequeue(self: *@This()) !?T {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);

            if (self.queue__internal.items.len == 0)
                return null;

            return self.queue__internal.orderedRemove(0);
        }
    };
}

test "init/deinit" {
    var queue = try ConcurrentQueue(u8).init(testing.io, testing.allocator);
    defer queue.deinit();
}

test "enqueue/dequeue single thread" {
    var queue = try ConcurrentQueue(u8).init(testing.io, testing.allocator);
    defer queue.deinit();

    try queue.enqueue(4);
    try queue.enqueue(6);
    try queue.enqueue(3);
    try queue.enqueue(9);

    var i: u32 = 0;
    while (try queue.dequeue()) |v| : (i += 1) {
        std.debug.print("v = {d}, i = {d}\n", .{v, i});
    }
}

pub fn concurrent_queue_ticker(_: std.mem.Allocator, cancel_token: *std.atomic.Value(bool), idx: u32, max_count: u32, x: *ConcurrentQueue(u32)) void {
    var count: u32 = 0;
    std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(100 * idx), std.Io.Clock.awake) catch return;
    while (!cancel_token.load(.acquire)) : (count += 1) {
        std.debug.print("ticker[{d}]: count={d}\n", .{idx, count});
        std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.awake) catch continue;
        x.enqueue(count) catch continue;
        if (count >= max_count) break;
    }
}
test "enqueue multithread join" {
    {
        std.debug.print("===============================\n", .{});
        std.debug.print("Concurrent queue\n", .{});
        std.debug.print("===============================\n", .{});
        
        var queue = try ConcurrentQueue(u32).init(testing.io, testing.allocator);
        defer queue.deinit();

        var cancel_token = std.atomic.Value(bool).init(false);
        const t1 = try std.Thread.spawn(.{}, concurrent_queue_ticker, .{testing.allocator, &cancel_token, 0, 100, &queue});
        const t2 = try std.Thread.spawn(.{}, concurrent_queue_ticker, .{testing.allocator, &cancel_token, 1, 50,  &queue});

        t1.join();
        t2.join();

        var i: u32 = 0;
        while (try queue.dequeue()) |v| : (i += 1) {
           std.debug.print("v = {d}, i = {d}\n", .{v, i});
        }
    }
}

pub fn concurrent_queue_ticker2(_: std.mem.Allocator, cancel_token: *std.atomic.Value(bool), idx: u32, max_count: u32, x: *ConcurrentQueue(u32)) void {
    var count: u32 = 0;
    std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(100 * idx), std.Io.Clock.awake) catch return;
    while (!cancel_token.load(.acquire)) : (count += 1) {
        std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(100 + 10 * idx), std.Io.Clock.awake) catch continue;
        x.enqueue(count) catch continue;
        if (count >= max_count) break;
    }

    std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(500), std.Io.Clock.awake) catch return;
    x.enqueue(10000) catch return;
}

test "enqueue 2 thread, dequeue 1 thread" {
    std.debug.print("===============================\n", .{});
    std.debug.print("enqueue 2 thread, dequeue 1 thread\n", .{});
    std.debug.print("===============================\n", .{});
    
    var queue = try ConcurrentQueue(u32).init(testing.io, testing.allocator);
    defer queue.deinit();

    var cancel_token = std.atomic.Value(bool).init(false);
    const t1 = try std.Thread.spawn(.{}, concurrent_queue_ticker2, .{testing.allocator, &cancel_token, 0, 100, &queue});
    const t2 = try std.Thread.spawn(.{}, concurrent_queue_ticker2, .{testing.allocator, &cancel_token, 1, 50,  &queue});
    const t3 = try std.Thread.spawn(.{}, concurrent_queue_ticker2, .{testing.allocator, &cancel_token, 5, 50,  &queue});

    var i: u32 = 0;
    while (true) {
        try std.Io.sleep(testing.io, std.Io.Duration.fromSeconds(1), .awake);
        std.debug.print("Waiting for new enqueues...\n", .{});
        while (try queue.dequeue()) |v| : (i += 1) {
           std.debug.print("v = {d}, i = {d}\n", .{v, i});
        }
    }
    t1.join();
    t2.join();
    t3.join();
}
