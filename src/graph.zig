const std = @import("std");
const testing = std.testing;

pub fn Graph(comptime T: type) type {
    return GraphWithContext(T, std.hash_map.AutoContext(T));
}

pub fn GraphWithContext(comptime T: type, comptime TContext: type) type {
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
