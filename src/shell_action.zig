const std = @import("std");

pub const CmdOutput = struct {
    stdout: ?[]u8 = null,
    stderr: ?[]u8 = null,
    exitCode: u8 = 0,
};

pub const ShellAction = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    runOpts: std.process.RunOptions,
    cmdOutput: CmdOutput,
    pub fn init(alloc: std.mem.Allocator, io: std.Io, argv: []const []const u8) @This() {
        return @This() {
            .alloc = alloc,
            .io = io,
            .runOpts = .{
                .argv = argv,
            },
            .cmdOutput = .{},
        };
    }
    pub fn deinit(self: @This()) void {
        if (self.cmdOutput.stdout) |stdout| self.alloc.free(stdout);
        if (self.cmdOutput.stderr) |stderr| self.alloc.free(stderr);
    }
    pub fn execute(self: *@This()) ?*const CmdOutput {
        // std.debug.print("Running command: ", .{});
        // for (self.runOpts.argv) |arg| std.debug.print("{s} ", .{arg});
        // std.debug.print("\n", .{});

        const child = std.process.run(self.alloc, self.io, self.runOpts) catch |err| {
            std.debug.print("Failed to run command: {s}\n", .{self.runOpts.argv[0]});
            std.debug.print("Error: {}\n", .{err});
            return null;
        };
        self.cmdOutput.stdout = child.stdout;
        self.cmdOutput.stderr = child.stderr;
        self.cmdOutput.exitCode = child.term.exited;
        return &self.cmdOutput;
    }
};
