const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    std.debug.print("Hello from test_main\n", .{});
    var it = init.minimal.args.iterate();
    std.debug.print("args: [", .{});
    while (it.next()) |arg| std.debug.print("{s}, ", .{arg});
    std.debug.print("]\n", .{});
    return 1;
}
