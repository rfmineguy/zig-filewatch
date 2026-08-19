const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    std.debug.print("Hello from test_main\n", .{});
    var it = try init.minimal.args.iterateAllocator(init.gpa);
    std.debug.print("args: [", .{});
    while (it.next()) |arg| std.debug.print("{s}, ", .{arg});
    std.debug.print("]\n", .{});

    try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(4), .awake);
    return 1;
}
