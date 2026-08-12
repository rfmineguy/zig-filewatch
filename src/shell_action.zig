const std = @import("std");

pub const Handles = struct {
    stdout: ?[]u8 = null,
    stderr: ?[]u8 = null,
};

pub const ShellAction = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    runOpts: std.process.RunOptions,
    handles: Handles,
    pub fn init(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8) @This() {
        return @This() {
            .alloc = alloc,
            .io = io,
            .runOpts = .{
                .argv = argv,
            },
            .handles = .{},
        };
    }
    pub fn deinit(self: @This()) void {
        if (self.handles.stdout) |stdout| self.alloc.free(stdout);
        if (self.handles.stderr) |stderr| self.alloc.free(stderr);
    }
    pub fn execute(self: *@This()) !*const Handles {
        const child = std.process.run(self.alloc, self.io, self.runOpts) catch |err| {
            std.debug.print("Error running child: {}\n", .{err});
            return error.FailedToRunChild;
        };
        std.debug.print("exit: {d}\n", .{child.term.exited});
        self.handles.stdout = child.stdout;
        self.handles.stderr = child.stderr;
        return &self.handles;
    }
};
