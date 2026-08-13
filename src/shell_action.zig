const std = @import("std");

pub const SuccessCmdOutput = struct {
    alloc: std.mem.Allocator,
    stdout: ?[]u8 = null,
    stderr: ?[]u8 = null,
    exitCode: u8 = 0,

    pub fn init(alloc: std.mem.Allocator, stdout: []u8, stderr: []u8, exitCode: u8) !@This() {
        return @This() {
            .alloc = alloc,
            .stdout = stdout,
            .stderr = stderr,
            .exitCode = exitCode,
        };
    }

    pub fn deinit(self: @This()) void {
        if (self.stdout) |stdout| {
            std.log.debug("freed stdout\n", .{});
            self.alloc.free(stdout);
        }
        if (self.stderr) |stderr| {
            std.log.debug("freed stderr\n", .{});
            self.alloc.free(stderr);
        }
    }
};

pub const CmdResult = union(enum) {
    success: SuccessCmdOutput,
    fail: anyerror,
};

pub const ShellAction = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    runOpts: std.process.RunOptions,
    pub fn init(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8) @This() {
        return @This() {
            .alloc = alloc,
            .io = io,
            .runOpts = .{
                .argv = argv,
            },
        };
    }
    pub fn deinit(self: @This()) void {
        _ = self;
    }
    pub fn execute(self: *@This()) !CmdResult {
        const child = std.process.run(self.alloc, self.io, self.runOpts) catch |err| {
            std.debug.print("Failed to run command: {s}\n", .{self.runOpts.argv[0]});
            std.debug.print("Error: {}\n", .{err});
            return .{ .fail = err };
        };
        return .{ .success = try .init(self.alloc, child.stdout, child.stderr, child.term.exited) };
    }
};
