const std = @import("std");
const testing = std.testing;

pub fn Graph(T: type) type {
    return GraphWithContext(T, std.hash_map.AutoContext(T));
}

pub fn GraphWithContext(T: type, TContext: type) type {
    return struct {
        alloc: std.mem.Allocator,
        nodes: std.HashMap(T, std.ArrayList(T), TContext, std.hash_map.default_max_load_percentage),

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This() {
                .alloc = alloc,
                .nodes = .init(alloc),
            };
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

test "u32:add_node" {
    var g = try Graph(u32).init(testing.allocator);
    defer g.deinit();

    try g.add(4);
    try g.add(5);

    try testing.expect(g.nodes.contains(4));
    try testing.expect(g.nodes.contains(5));
    for (0..3) |i| try testing.expect(!g.nodes.contains(@intCast(i)));
    for (6..10) |i| try testing.expect(!g.nodes.contains(@intCast(i)));
}

test "u32:connect_nodes" {
    var g = try Graph(u32).init(testing.allocator);
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
        var g = try Graph(u32).init(testing.allocator);
        defer g.deinit();

        try g.add(4);
        try testing.expectError(error.MissingTo, g.connect(4, 3));
    }
    {
        var g = try Graph(u32).init(testing.allocator);
        defer g.deinit();

        try g.add(3);
        try testing.expectError(error.MissingFrom, g.connect(4, 3));
    }
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
