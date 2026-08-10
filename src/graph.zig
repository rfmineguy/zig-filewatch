const std = @import("std");
const testing = std.testing;

fn Formatted(comptime T: type, comptime Context: type) type {
    return struct {
        value: T,
        context: Context,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try self.context.format(self.value, writer);
        }
    };
}

pub fn GraphWithContext(T: type, TContext: type) type {
    return struct {
        context: TContext,
        alloc: std.mem.Allocator,
        nodes: std.HashMap(T, std.ArrayList(T), TContext, std.hash_map.default_max_load_percentage),

        const Cycle = struct {
            elements: std.ArrayList(T),
        };
        const BFSIterator = @import("graph_algs.zig").BFSIterator(T, TContext);
        const DFSIterator = @import("graph_algs.zig").DFSIterator(T, TContext);
        const Johnsons = @import("graph_algs.zig").Johnsons(T, TContext);

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This() {
                .context = .{},
                .alloc = alloc,
                .nodes = .init(alloc),
            };
        }

        pub fn bfs(self: *@This()) !BFSIterator {
            var it: BFSIterator = try .init(self);
            var it_ = self.nodes.keyIterator();
            while (it_.next()) |v| {
                try it.queue.pushFront(self.alloc, v.*);
            }
            return it;
        }

        pub fn dfs(self: *@This()) !DFSIterator {
            return try .init(self);
        }

        pub fn dot(self: *@This(), writer: *std.Io.Writer) !void {
            var it = try self.bfs();
            var index: u32 = 0;
            try writer.print("digraph {{\n", .{});
            while (try it.next()) |v| : (index += 1) {
                const formatted = Formatted(T, TContext){.value = v, .context = self.context};
                try writer.print("{f} [label=\"{f}\"]\n", .{formatted, formatted});
                try writer.print("{f} -> {{", .{formatted});
                if (self.nodes.get(v)) |v_| {
                    for (v_.items, 0..) |item, idx| {
                        const formatted2 = Formatted(T, TContext){.value = item, .context = self.context};
                        try writer.print("{f}", .{formatted2});
                        if (idx != v_.items.len - 1) try writer.print(",", .{});
                    }
                }
                try writer.print("}}\n", .{});
            }
            try writer.print("}}\n", .{});
        }

        //TODO: Implement cycle detection
        pub fn detectCycles(self: *@This()) ?std.ArrayList(std.ArrayList(T)) {
            var johnsons = Johnsons.init(self);
            defer johnsons.deinit();

            const cycles = johnsons.findAllCycles() catch return null;
            return cycles;
        }

        pub fn deinit(self: *@This()) void {
            var it = self.nodes.valueIterator();
            while (it.next()) |v| {
                v.deinit(self.alloc);
            }
            self.nodes.deinit();
        }

        pub fn add(self: *@This(), v: T) !void {
            try self.nodes.put(v, try .initCapacity(self.alloc, 10));
        }

        pub fn connect(self: *@This(), from: T, to: T) anyerror!void {
            if (!self.nodes.contains(from)) return error.MissingFrom;
            if (!self.nodes.contains(to)) return error.MissingTo;
            if (self.nodes.getPtr(from)) |list| {
                try list.append(self.alloc, to);
            }
        }
    };
}

const U32Context = struct {
    pub fn hash(_: @This(), key: []u32) u64 {
        var h = std.hash.Wyhash.init(3497);  // <- change the hash algo according to your needs... (WyHash...)
        h.update(key);
        return h.final();
    }

    pub fn eql(_: @This(), a: u32, b: u32) bool {
        return a == b;
    }

    pub fn cmp(_: @This(), a: u32, b: u32) i8 {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    }
};

test "u32:add_node" {
    var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
    defer g.deinit();

    try g.add(4);
    try g.add(5);

    try testing.expect(g.nodes.contains(4));
    try testing.expect(g.nodes.contains(5));
    for (0..3) |i| try testing.expect(!g.nodes.contains(@intCast(i)));
    for (6..10) |i| try testing.expect(!g.nodes.contains(@intCast(i)));
}

test "u32:connect_nodes" {
    var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
    defer g.deinit();

    try g.add(4);
    try g.add(5);

    try testing.expect(g.nodes.contains(4));
    try testing.expect(g.nodes.contains(5));
    for (0..3) |i| try testing.expect(!g.nodes.contains(@intCast(i)));
    for (6..10) |i| try testing.expect(!g.nodes.contains(@intCast(i)));

    try g.connect(4, 5);
    try testing.expect(g.nodes.get(4) != null);
    try testing.expect(std.mem.containsAtLeast(u32, g.nodes.get(4).?.items, 1, &[_]u32{5}));
    try testing.expect(!std.mem.containsAtLeast(u32, g.nodes.get(5).?.items, 1, &[_]u32{4}));
}

test "u32:connect_to_missing_nodes" {
    {
        var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
        defer g.deinit();

        try g.add(4);
        try testing.expectError(error.MissingTo, g.connect(4, 3));
    }
    {
        var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
        defer g.deinit();

        try g.add(3);
        try testing.expectError(error.MissingFrom, g.connect(4, 3));
    }
}

test "u32:bfs_iterator" {
    std.debug.print("u32:bfs_iterator\n", .{});
    var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
    defer g.deinit();

    try g.add(0);
    try g.add(1);
    try g.add(2);
    try g.add(3);
    try g.add(10);

    // create linear graph
    try g.connect(0, 1);
    try g.connect(1, 2);
    try g.connect(2, 3);
    try g.connect(1, 10);

    var it = try g.bfs();
    defer it.deinit();
    var idx: u32 = 0;
    while (try it.next()) |v| : (idx += 1) {
        std.debug.print("{},", .{v});
    }
    std.debug.print("\n", .{});
}

test "u32:dfs_iterator" {
    std.debug.print("u32:dfs_iterator\n", .{});
    var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
    defer g.deinit();

    try g.add(0);
    try g.add(1);
    try g.add(2);
    try g.add(3);
    try g.add(4);
    try g.add(5);
    try g.add(6);

    // create binary tree
    //     A
    //    / \
    //   B   C
    //  / \   \
    // D   E   F
    //      \
    //       G
    try g.connect(0, 1);
    try g.connect(0, 2);
    try g.connect(1, 3);
    try g.connect(1, 4);
    try g.connect(2, 5);
    try g.connect(4, 6);

    // const io = testing.io;
    // var stdout_buffer: [1024]u8 = undefined;
    // var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);

    // try g.dot(&stdout_file_writer.interface);
    // try stdout_file_writer.flush();

    var it = try g.dfs();
    defer it.deinit();
    var idx: u32 = 0;
    while (try it.next()) |v| : (idx += 1) {
        std.debug.print("{any},", .{v});
    }
    std.debug.print("\n", .{});
}

test "u32:cycles" {
    std.debug.print("u32:dfs_iterator\n", .{});
    var g = try GraphWithContext(u32, U32Context).init(testing.allocator);
    defer g.deinit();

    try g.add(0);
    try g.add(1);
    try g.add(2);
    try g.add(3);
    try g.add(4);
    try g.add(5);
    try g.add(6);
    try g.add(7);

    try g.connect(0, 1);
    try g.connect(1, 0);
    try g.connect(0, 2);
    try g.connect(1, 3);
    try g.connect(1, 4);
    try g.connect(2, 5);
    try g.connect(2, 6);
    try g.connect(3, 7);
    try g.connect(7, 0);
    try g.connect(6, 0);

    const expected = [_][]const u32{
        &.{ 0, 1 },
        &.{ 0, 1, 3, 7 },
        &.{ 0, 2, 6 },
    };
    var actual = g.detectCycles();
    try testing.expect(actual != null);
    try testing.expect(actual.?.items.len == expected.len);
    for (expected, actual.?.items) |expected_cycle, *actual_cycle| {
        try testing.expectEqualSlices(u32, expected_cycle, actual_cycle.items);
        actual_cycle.deinit(g.alloc);
    }
    actual.?.deinit(g.alloc);
}

const ConstU8TestContext = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        var h = std.hash.Wyhash.init(3497);  // <- change the hash algo according to your needs... (WyHash...)
        h.update(key);
        return h.final();
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};
fn contains(ctx: anytype, haystack: [][]const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (ctx.eql(needle, item)) return true;
    }
    return false;
}

test "[]const u8:add_node" {
    var g = try GraphWithContext([]const u8, ConstU8TestContext).init(testing.allocator);
    defer g.deinit();

    try g.add("hello");
    try testing.expect(g.nodes.get("hello") != null);
}

test "[]const u8:connect_nodes" {
    var g = try GraphWithContext([]const u8, ConstU8TestContext).init(testing.allocator);
    defer g.deinit();

    try g.add("hello");
    try g.add("goodbye");

    try testing.expect(g.nodes.contains("hello"));
    try testing.expect(g.nodes.contains("goodbye"));

    try g.connect("hello", "goodbye");
    try testing.expect(g.nodes.get("hello") != null);
    try testing.expect(contains(g.context, g.nodes.get("hello").?.items, "goodbye"));
    try testing.expect(!contains(g.context, g.nodes.get("goodbye").?.items, "hello"));
}

test "struct:add_node" {
    const Test = struct {
        hi: []const u8
    };
    const TestContext = struct {
        pub fn hash(_: @This(), key: Test) u64 {
            var h = std.hash.Wyhash.init(3497);  // <- change the hash algo according to your needs... (WyHash...)
            h.update(key.hi);
            return h.final();
        }

        pub fn eql(_: @This(), a: Test, b: Test) bool {
            return std.mem.eql(u8, a.hi, b.hi);
        }
    };
    var g = try GraphWithContext(Test, TestContext).init(testing.allocator);
    defer g.deinit();

    try g.add(.{.hi = "Hello"});
    try testing.expect(g.nodes.contains(.{.hi = "Hello"}));
    try testing.expect(!g.nodes.contains(.{.hi = "Goodbye"}));
}
