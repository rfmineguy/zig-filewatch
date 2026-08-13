// credit to https://gist.github.com/yougg/e7c4ffde91ad31f0d1b23111244c2ee5

const std = @import("std");
const Configuration = @import("../configuration.zig");
const ZigFilewatchConfig = Configuration.Config;
const Progress = std.Progress;

const indent_unicode = "│   ";
const indent_space = "    ";
const suffix_last = "└──";
const suffix_mid = "├──";

pub const Config = struct {
    print_progress: bool = false,
};

fn print_progress(init: std.process.Init) !void {
    std.debug.print("progress...", .{});
    var progress = std.Progress.start(init.io, .{
        .root_name = "build",
    });
    defer progress.end();

    const build_zig = progress.start("build_zig", 1);
    defer build_zig.end();

    const compile = build_zig.start("compile", 100);
    defer compile.end();

    for (0..100) |_| {
        compile.completeOne();
        try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(100), .awake);
    }

    build_zig.completeOne();

    // Give Progress time to render the final state.
    try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(1), .awake);
}

pub fn driver_fancy_output(init: std.process.Init, config: Config) !void {
    if (config.print_progress) {
        try print_progress(init);
    }
}
