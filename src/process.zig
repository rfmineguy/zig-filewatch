const std = @import("std");

pub const Process = struct {
    id: u64,
    parent_id: ?u64,
    action: []const u8,

    pid: std.posix.pid_t,
    pgid: std.posix.pid_t,

    children: std.ArrayList(u64),

    state: State,

    pub const State = enum {
        starting,
        running,
        stopping,
        finished,
        failed,
        cancelled,
    };
};
