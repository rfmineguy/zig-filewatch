const std = @import("std");
const Process = @import("process.zig").Process;

pub const ProcessTree = struct {
    alloc: std.mem.Allocator,
    next_id: u64 = 1,
    processes: std.AutoHashMap(u64, Process),
    actions: std.StringHashMap(u64),

    pub fn init(alloc: std.mem.Allocator) !@This() {
        return @This() {
            .alloc = alloc,
            .processes = .init(alloc),
            .actions = .init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.processes.valueIterator();
        while (it.next()) |v| {
            v.children.deinit(self.alloc);
        }
        self.processes.deinit();
        self.actions.deinit();
    }

    pub fn nextId(self: @This()) u64 {
        return self.next_id;
    }

    /// Each root action owns its own process group. Killing the group therefore
    /// also stops shell commands and other descendants it launches.
    pub fn spawn(self: *@This(), init_: std.process.Init, parent: ?u64, action: []const u8, argv: []const []const u8) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        const child = try std.process.spawn(init_.io, .{
            .argv = argv,
            .pgid = 0,
        });

        const pid = child.id orelse return error.ChildMissingPid;

        const process = Process{
            .id = id,
            .parent_id = parent,
            .action = action,
            .pid = pid,
            .pgid = pid,
            .children = .empty,
            .state = .starting,
        };

        try self.processes.put(id, process);
        try self.actions.put(action, id);

        if (parent) |parent_id| {
            const parent_proc = self.processes.getPtr(parent_id).?;
            try parent_proc.children.append(self.alloc, id);
        }
        return id;
    }

    pub fn find_action(self: @This(), action: []const u8) ?*Process {
        const id = self.actions.get(action) orelse return null;
        return self.processes.getPtr(id);
    }

    pub fn handleEvent(self: *@This(), id: u64, state: Process.State) void {
        if (self.processes.getPtr(id)) |process| process.state = state;
    }

    pub fn cancel(self: *@This(), action: []const u8) !void {
        const process = self.find_action(action) orelse return;
        if (process.state == .finished or process.state == .failed or process.state == .cancelled) return;
        std.posix.kill(-process.pgid, .TERM) catch |err| switch (err) {
            error.ProcessNotFound => {},
            else => return err,
        };
        process.state = .cancelled;
    }

};
