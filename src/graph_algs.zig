const GraphWithContext = @import("graph.zig").GraphWithContext;
const std = @import("std");

pub fn DFSIterator(T: type, TContext: type) type {
    return struct {
        graph: *const GraphWithContext(T, TContext),
        nodes_iterator: std.HashMap(T, std.ArrayList(T), TContext, std.hash_map.default_max_load_percentage).Iterator,
        stack: std.ArrayList(T),
        visited: std.HashMap(T, void, TContext, std.hash_map.default_max_load_percentage),
        index: u32,

        pub fn init(graph: *const GraphWithContext(T, TContext)) !@This() {
            var it: @This() = .{
                .graph = graph,
                .nodes_iterator = graph.nodes.iterator(),
                .stack = try .initCapacity(graph.alloc, 10),
                .visited = .init(graph.alloc),
                .index = 0,
            };
            var it_ = graph.nodes.iterator();
            if (it_.next()) |entry| try it.stack.append(graph.alloc, entry.key_ptr.*);

            return it;
        }

        pub fn deinit(self: *@This()) void {
            self.stack.deinit(self.graph.alloc);
            self.visited.deinit();
        }

        pub fn next(self: *@This()) !?T {
            while (self.stack.pop()) |v| {
                if (self.visited.contains(v)) continue;
                try self.visited.put(v, {});

                if (self.graph.nodes.get(v)) |connections| {
                    for (connections.items) |conn| {
                        if (self.visited.contains(conn)) continue;
                        try self.stack.append(self.graph.alloc, conn);
                    }
                }
                self.index += 1;
                return v;
            }

            // Current component is exhausted
            while (self.nodes_iterator.next()) |entry| {
                const v = entry.key_ptr.*;
                if (self.visited.contains(v)) continue;

                try self.stack.append(self.graph.alloc, v);
                return self.next();
            }
            return null;
        }
    };
}

pub fn BFSIterator(T: type, TContext: type) type {
    return struct {
        graph: *const GraphWithContext(T, TContext),
        queue: std.Deque(T),
        visited: std.HashMap(T, void, TContext, std.hash_map.default_max_load_percentage),
        index: u32,

        pub fn init(graph: *const GraphWithContext(T, TContext)) !@This() {
            return .{
                .graph = graph,
                .queue = try .initCapacity(graph.alloc, 10),
                .visited = .init(graph.alloc),
                .index = 0,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.queue.deinit(self.graph.alloc);
            self.visited.deinit();
        }

        pub fn next(self: *@This()) !?T {
            // The end of the iteration
            if (self.queue.len == 0) {
                return null;
            }

            const v = self.queue.popFront().?; // ensured to be non null due to prior check
            if (self.visited.contains(v)) return null;
            try self.visited.put(v, {});
            if (self.graph.nodes.get(v)) |connections| {
                for (connections.items) |conn| {
                    if (self.visited.contains(conn)) continue;
                    try self.queue.pushFront(self.graph.alloc, conn);
                }
            }

            self.index += 1;
            return v;
        }
    };
}

pub fn Johnsons(T: type, TContext: type) type {
    return struct {

        const Graph = GraphWithContext(T, TContext);

        graph: *const Graph,
        stack: std.ArrayList(T),
        blocked: std.AutoHashMap(T, void),

        b: std.AutoHashMap(T, std.ArrayList(T)),
        sub_nodes: std.AutoHashMap(T, void),

        pub fn init(graph: *const Graph) @This() {
            return .{
                .graph = graph,
                .stack = .empty,
                .blocked = .init(graph.alloc),
                .b = .init(graph.alloc),
                .sub_nodes = .init(graph.alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.stack.deinit(self.graph.alloc);
            self.blocked.deinit();
            self.sub_nodes.deinit();

            var it = self.b.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.graph.alloc);
            }
            self.b.deinit();
        }

        fn getScc(
            self: *@This(),
        ) !?std.ArrayList(T) {
            var index: usize = 0;

            var indices = std.AutoHashMap(T, usize).init(self.graph.alloc);
            defer indices.deinit();

            var lowlink = std.AutoHashMap(T, usize).init(self.graph.alloc);
            defer lowlink.deinit();

            var on_stack = std.AutoHashMap(T, void).init(self.graph.alloc);
            defer on_stack.deinit();

            var stack = std.ArrayList(T).empty;
            defer stack.deinit(self.graph.alloc);

            var best_scc: ?std.ArrayList(T) = null;

            // Tarjan over all vertices still in sub_nodes.
            var vertices = self.graph.nodes.iterator();

            while (vertices.next()) |v| {
                if (!self.sub_nodes.contains(v.key_ptr.*)) {
                    continue;
                }

                if (indices.contains(v.key_ptr.*)) {
                    continue;
                }

                try self.strongConnect(
                    v.key_ptr.*,
                    &index,
                    &indices,
                    &lowlink,
                    &on_stack,
                    &stack,
                    &best_scc,
                );
            }

            return best_scc;
        }

        fn strongConnect(
            self: *@This(),
            v: T,
            index: *usize,
            indices: *std.AutoHashMap(T, usize),
            lowlink: *std.AutoHashMap(T, usize),
            on_stack: *std.AutoHashMap(T, void),
            stack: *std.ArrayList(T),
            best_scc: *?std.ArrayList(T),
        ) !void {
            try indices.put(v, index.*);
            try lowlink.put(v, index.*);
            index.* += 1;

            try stack.append(self.graph.alloc, v);
            try on_stack.put(v, {});

            const neighbors = self.graph.nodes.get(v).?;
            for (neighbors.items) |w| {
                if (!self.sub_nodes.contains(w)) {
                    continue;
                }

                if (!indices.contains(w)) {
                    try self.strongConnect(
                        w,
                        index,
                        indices,
                        lowlink,
                        on_stack,
                        stack,
                        best_scc,
                    );

                    const v_low = lowlink.get(v).?;
                    const w_low = lowlink.get(w).?;

                    try lowlink.put(v, @min(v_low, w_low));
                } else if (on_stack.contains(w)) {
                    const v_low = lowlink.get(v).?;
                    const w_index = indices.get(w).?;

                    try lowlink.put(v, @min(v_low, w_index));
                }
            }

            // v is the root of an SCC.
            if (lowlink.get(v).? == indices.get(v).?) {
                var scc = std.ArrayList(T).empty;

                while (true) {
                    const w = stack.pop().?;

                    _ = on_stack.remove(w);

                    try scc.append(self.graph.alloc, w);

                    if (std.meta.eql(w, v)) {
                        break;
                    }
                }

                // Only SCCs with >1 vertex can contain a cycle,
                // except for a vertex with an edge to itself.
                var is_cyclic = scc.items.len > 1;

                if (scc.items.len == 1) {
                    const node = scc.items[0];

                    const edges = self.graph.nodes.get(node).?;
                    for (edges.items) |w| {
                        if (std.meta.eql(w, node)) {
                            is_cyclic = true;
                            break;
                        }
                    }
                }

                if (is_cyclic) {
                    if (best_scc.*) |*current| {
                        if (candidateMin(scc.items) < candidateMin(current.items)) {
                            current.deinit(self.graph.alloc);
                            best_scc.* = scc;
                        } else {
                            scc.deinit(self.graph.alloc);
                        }
                    } else {
                        best_scc.* = scc;
                    }
                } else {
                    scc.deinit(self.graph.alloc);
                }
            }
        }
        
        pub fn findAllCycles(
            self: *@This(),
        ) !std.ArrayList(std.ArrayList(T)) {
            var cycles = std.ArrayList(std.ArrayList(T)).empty;
            errdefer {
                for (cycles.items) |*cycle| {
                    cycle.deinit(self.graph.alloc);
                }
                cycles.deinit(self.graph.alloc);
            }

            // sub_nodes = all vertices
            var vertices = self.graph.nodes.iterator();

            while (vertices.next()) |v| {
                try self.sub_nodes.put(v.key_ptr.*, {});
            }

            while (self.sub_nodes.count() > 0) {
                // Find SCCs in the current subgraph.
                var scc = try self.getScc() orelse break;
                defer scc.deinit(self.graph.alloc);

                if (scc.items.len == 0) {
                    break;
                }

                // Turn SCC into lookup set.
                var scc_nodes = std.AutoHashMap(T, void).init(
                    self.graph.alloc,
                );
                defer scc_nodes.deinit();

                for (scc.items) |v| {
                    try scc_nodes.put(v, {});
                }

                const s = candidateMin(scc.items);

                // Reset Johnson state.
                self.blocked.clearRetainingCapacity();

                var b_it = self.b.valueIterator();
                while (b_it.next()) |list| {
                    list.clearRetainingCapacity();
                }

                self.stack.clearRetainingCapacity();

                // Find every cycle beginning at s.
                _ = try self.circuit(
                    s,
                    s,
                    &scc_nodes,
                    &cycles,
                );

                // Remove s from the remaining graph.
                _ = self.sub_nodes.remove(s);
            }

            return cycles;
        }

        fn candidateMin(candidate: []const T) T {
            var min = candidate[0];

            for (candidate[1..]) |v| {
                if (v < min) {
                    min = v;
                }
            }

            return min;
        }

        fn contains(items: []const T, value: T) bool {
            for (items) |item| {
                if (item == value) {
                    return true;
                }
            }

            return false;
        }

        fn circuit(
            self: *@This(),
            v: T,
            start: T,
            scc_nodes: *const std.AutoHashMap(T, void),
            cycles: *std.ArrayList(std.ArrayList(T)),
        ) !bool {
            var found = false;

            try self.stack.append(self.graph.alloc, v);
            try self.blocked.put(v, {});

            const neighbors = self.graph.nodes.get(v).?;
            for (neighbors.items) |w| {
                if (!scc_nodes.contains(w)) {
                    continue;
                }

                if (std.meta.eql(w, start)) {
                    var cycle = std.ArrayList(T).empty;
                    //errdefer cycle.deinit(self.graph.alloc);

                    try cycle.appendSlice(
                        self.graph.alloc,
                        self.stack.items,
                    );

                    try cycles.append(
                        self.graph.alloc,
                        cycle,
                    );

                    found = true;
                } else if (!self.blocked.contains(w)) {
                    if (try self.circuit(
                        w,
                        start,
                        scc_nodes,
                        cycles,
                    )) {
                        found = true;
                    }
                }
            }

            if (found) {
                try self.unblock(v);
            } else {
                const neighbors2 = self.graph.nodes.get(v).?;

                for (neighbors2.items) |w| {
                    if (!scc_nodes.contains(w)) {
                        continue;
                    }

                    var entry = try self.b.getOrPut(w);

                    if (!entry.found_existing) {
                        entry.value_ptr.* = .empty;
                    }

                    if (!contains(entry.value_ptr.items, v)) {
                        try entry.value_ptr.append(
                            self.graph.alloc,
                            v,
                        );
                    }
                }
            }

            _ = self.stack.pop();

            return found;
        }

        fn unblock(self: *@This(), u: T) !void {
            if (!self.blocked.remove(u)) {
                return;
            }

            if (self.b.getPtr(u)) |list| {
                while (list.items.len > 0) {
                    const v = list.pop().?;

                    try self.unblock(v);
                }
            }
        }
    };
}
